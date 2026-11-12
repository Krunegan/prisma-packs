// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Sun and moon shadows from Prisma's shadow map, filtered with PCSS: crisp
	near the caster, softer farther away. Contact shadows (High, Ultra)
	trace the depth buffer for detail the map misses. Both map directions
	are blended, so shadows glide.
*/
#ifndef AURORA_SHADOWS
#define AURORA_SHADOWS

#include "common.glsl"

vec2 vogel(int i, int n, float rot)
{
	float r = sqrt((float(i) + 0.5) / float(n));
	float t = float(i) * 2.39996323 + rot;
	return vec2(cos(t), sin(t)) * r;
}

// `lightSize`: tangent of the sun's angular radius (bigger = softer)
float pcss(sampler2D map, mat4 matrix, vec3 playerPos, vec3 normal, float lightSize, float rot)
{
	float texel = 2.0 * prisma.shadowDistance / prisma.shadowMapSize.x;
	vec3 L = prisma.lightDirection;
	bool hasNormal = dot(normal, normal) > 0.01;
	float cosL = hasNormal ? clamp(dot(normal, L), 0.05, 1.0) : 0.5;
	float sinL = sqrt(1.0 - cosL * cosL);
	vec3 p = playerPos + (hasNormal ? normal * texel * (1.0 + 1.5 * sinL) : L * texel * 2.0);
	vec3 sc = (matrix * vec4(p, 1.0)).xyz;
	if (sc.z >= 1.0 || !onScreenUv(sc.xy))
		return 1.0;
	float z = sc.z - texel * (1.0 + 2.0 * min(sinL / cosL, 4.0)) / prisma.shadowDepthRange;

	// Penumbra in texels per node between caster and receiver
	float spread = 2.0 * lightSize / texel;
	float radius = clamp(1.5 + spread * 2.0, 1.0, 6.0);
#if SHADOW_SEARCH > 0
	// Blocker search: average depth of what is in front
	float searchR = clamp(spread * 12.0, 2.0, 24.0);
	float blockers = 0.0, count = 0.0;
	for (int i = 0; i < SHADOW_SEARCH; i++) {
		vec2 st = sc.xy + vogel(i, SHADOW_SEARCH, rot) * searchR / prisma.shadowMapSize;
		float d = texture(map, st).r;
		if (d < z) {
			blockers += d;
			count += 1.0;
		}
	}
	if (count < 0.5)
		return 1.0;
	float nodes = (z - blockers / count) * prisma.shadowDepthRange;
	radius = clamp(0.75 + nodes * spread, 0.75, 24.0);
#endif
	float sum = 0.0;
	for (int i = 0; i < SHADOW_TAPS; i++) {
		vec2 st = sc.xy + vogel(i, SHADOW_TAPS, rot + 1.3) * radius / prisma.shadowMapSize;
		sum += prismaShadowTap(map, st, z);
	}
	float lit = sum / float(SHADOW_TAPS);
	vec2 edge = abs(sc.xy * 2.0 - 1.0);
	return mix(lit, 1.0, smoothstep(0.85, 1.0, max(edge.x, edge.y)));
}

float softShadow(vec3 playerPos, vec3 normal, float lightSize)
{
	if (!prisma.shadowAvailable || !options.shadows)
		return 1.0;
	float rot = ign(gl_FragCoord.xy) * TAU;
	float b = prisma.shadowBlend;
	float latest = b > 0.001 ? pcss(shadowTex, prisma.shadowMatrix, playerPos, normal, lightSize, rot) : 0.0;
	if (b >= 0.999)
		return latest;
	float prev = pcss(shadowTexPrev, prisma.shadowMatrixPrev, playerPos, normal, lightSize, rot);
	return mix(prev, latest, b);
}

// One bilinear tap of both maps (the fog uses it at every step)
float hardShadow(vec3 playerPos)
{
	if (!prisma.shadowAvailable || !options.shadows)
		return 1.0;
	vec3 sc = (prisma.shadowMatrix * vec4(playerPos, 1.0)).xyz;
	float lit = 1.0;
	if (sc.z < 1.0 && onScreenUv(sc.xy))
		lit = prismaShadowTap(shadowTex, sc.xy, sc.z - 0.6 / prisma.shadowDepthRange);
	if (prisma.shadowBlend < 0.999) {
		vec3 sp = (prisma.shadowMatrixPrev * vec4(playerPos, 1.0)).xyz;
		float prev = 1.0;
		if (sp.z < 1.0 && onScreenUv(sp.xy))
			prev = prismaShadowTap(shadowTexPrev, sp.xy, sp.z - 0.6 / prisma.shadowDepthRange);
		lit = mix(prev, lit, prisma.shadowBlend);
	}
	vec2 edge = abs(sc.xy * 2.0 - 1.0);
	return mix(lit, 1.0, smoothstep(0.9, 1.0, max(edge.x, edge.y)));
}

// Contact shadows: march towards the light in the depth buffer (1 = clear)
float contactShadow(vec3 view, vec3 L, float jitter)
{
	vec3 Lv = mat3(prisma.viewMatrix) * L;
	float dist = length(view);
	float len = mix(0.35, 1.2, saturate(dist / 24.0));
	const int N = 14;
	vec3 stepV = Lv * len / float(N);
	vec3 p = view + Lv * 0.02 + stepV * jitter;
	float thickness = 0.12 + dist * 0.004;
	for (int i = 0; i < N; i++) {
		p += stepV;
		vec2 uv = viewToUv(p);
		if (!onScreenUv(uv))
			return 1.0;
		float d = texture(depthTex, uv).r;
		if (isSky(d))
			continue;
		float sceneZ = viewPosition(uv, d).z;
		float diff = p.z - sceneZ;
		if (diff > 0.01 && diff < thickness)
			return float(i) / float(N) * 0.5;
	}
	return 1.0;
}

#endif
