// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Ground-truth ambient occlusion (GTAO) at half resolution: the horizons on
	both sides of a few rotating directions, weighted by the G-buffer normal,
	averaged over frames. r = unoccluded light, g = distance.
*/
#prisma target ao
#include "common.glsl"

#if AO_QUALITY == AO_QUALITY_LOW
const int AO_SLICES = 1;
const int AO_STEPS = 4;
#elif AO_QUALITY == AO_QUALITY_MEDIUM
const int AO_SLICES = 2;
const int AO_STEPS = 5;
#else
const int AO_SLICES = 2;
const int AO_STEPS = 8;
#endif

float horizonCos(vec3 P, vec3 V, vec2 uv, vec2 stepUv, float radius, float jitter)
{
	float best = -1.0;
	for (int j = 0; j < AO_STEPS; j++) {
		float s = (float(j) + jitter) / float(AO_STEPS);
		s = s * s * 0.9 + 0.1 * s; // denser close to the pixel
		vec2 q = uv + stepUv * s;
		if (!onScreenUv(q))
			break;
		float d = texture(depthTex, q).r;
		if (isSky(d))
			continue;
		vec3 delta = viewPosition(q, d) - P;
		float len = length(delta);
		if (len < 1e-3)
			continue;
		float c = dot(delta / len, V);
		// Far samples count less
		float falloff = saturate((len - radius * 0.6) / (radius * 0.6));
		best = max(best, mix(c, -1.0, falloff));
	}
	return best;
}

void main()
{
	float depth = texture(depthTex, texcoord).r;
#if AO_QUALITY == AO_QUALITY_OFF
	fragColor = vec4(1.0, 1e4, 0.0, 1.0);
	return;
#else
	if (isSky(depth) || options.ambient_occlusion <= 0.0) {
		fragColor = vec4(1.0, 1e4, 0.0, 1.0);
		return;
	}
	vec3 P = viewPosition(texcoord, depth);
	float dist = length(P);
	vec3 worldN = gbufferNormal(texcoord);
	float fade = 1.0 - smoothstep(48.0, 96.0, dist);
	if (dot(worldN, worldN) < 0.5 || fade <= 0.0) {
		fragColor = vec4(1.0, dist, 0.0, 1.0);
		return;
	}
	vec3 N = normalize(mat3(prisma.viewMatrix) * worldN);
	vec3 V = normalize(-P);
	float radius = options.ao_radius;
	// The radius on screen, in pixels of the full image
	float radiusPx = radius * prisma.projectionMatrix[1][1] * 0.5 * prisma.viewSize.y / max(P.z, 0.05);
	radiusPx = min(radiusPx, 0.12 * prisma.viewSize.y);
	if (radiusPx < 1.5) {
		fragColor = vec4(1.0, dist, 0.0, 1.0);
		return;
	}

	float noiseA = ignAnim(gl_FragCoord.xy);
	float noiseB = fract(noiseA * 7.31 + ign(gl_FragCoord.yx + 17.0));
	float visibility = 0.0;
	for (int i = 0; i < AO_SLICES; i++) {
		float phi = (float(i) + noiseA) / float(AO_SLICES) * PI;
		vec2 omega = vec2(cos(phi), sin(phi));
		vec2 stepUv = omega * radiusPx * prisma.texelSize;
		vec3 dirV = vec3(omega, 0.0);
		vec3 ortho = dirV - dot(dirV, V) * V;
		vec3 axis = normalize(cross(ortho, V));
		vec3 projN = N - axis * dot(N, axis);
		float projLen = length(projN);
		if (projLen < 1e-3) {
			visibility += 1.0;
			continue;
		}
		float cosN = saturate(dot(projN, V) / projLen);
		float n = sign(dot(ortho, projN)) * acos(cosN);
		float c0 = horizonCos(P, V, texcoord, stepUv, radius, noiseB);
		float c1 = horizonCos(P, V, texcoord, -stepUv, radius, noiseB);
		float h0 = -acos(clamp(c1, -1.0, 1.0));
		float h1 = acos(clamp(c0, -1.0, 1.0));
		h0 = n + clamp(h0 - n, -0.5 * PI, 0.5 * PI);
		h1 = n + clamp(h1 - n, -0.5 * PI, 0.5 * PI);
		float arc0 = (cosN + 2.0 * h0 * sin(n) - cos(2.0 * h0 - n)) * 0.25;
		float arc1 = (cosN + 2.0 * h1 * sin(n) - cos(2.0 * h1 - n)) * 0.25;
		visibility += projLen * (arc0 + arc1);
	}
	float occ = saturate(visibility / float(AO_SLICES));
	occ = mix(1.0, occ, fade);

	// Temporal accumulation
	vec3 player = (prisma.viewMatrixInverse * vec4(P, 1.0)).xyz;
	vec3 before = prismaPreviousScreenPosition(player);
	if (before.z > 0.0 && onScreenUv(before.xy)) {
		vec2 history = texelFetch(ao, ivec2(before.xy * targetSize), 0).rg;
		float expected = length(player + prisma.cameraPosition - prisma.prevCameraPosition);
		if (abs(history.g - expected) < 0.04 * expected + 0.05)
			occ = mix(occ, history.r, 0.88);
	}
	fragColor = vec4(occ, dist, 0.0, 1.0);
#endif
}
