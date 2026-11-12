// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Water seen from above: the bottom bent by the waves, tinted teal; the
	reflection with Fresnel; a sharp GGX sun glint.
*/
#include "light.glsl"
#include "water.glsl"

// GGX highlight of the sun on a surface of roughness `alpha`
vec3 glint(Atmos a, vec3 n, vec3 v, float alpha, float F0, vec3 player, vec3 world)
{
	vec3 L = a.lightDir;
	float nl = dot(n, L);
	if (nl <= 0.0 || maxOf(a.directLight) < 1e-5)
		return vec3(0.0);
	vec3 h = normalize(L - v);
	float nh = max(dot(n, h), 0.0);
	float nv = max(dot(n, -v), 0.05);
	float a2 = alpha * alpha;
	float d = nh * nh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * d * d);
	float F = F0 + (1.0 - F0) * pow(1.0 - max(dot(h, -v), 0.0), 5.0);
	float vis = hardShadow(player) * cloudShadow(world, L, min(CLOUD_SHADOW_OCTAVES, 2));
	return a.directLight * min(D * F * PI / (4.0 * nv), 400.0) * vis;
}

vec3 reflectionOf(Atmos a, vec3 view, vec3 player, vec3 world, vec3 n, vec3 v)
{
	vec3 rWorld = reflect(v, n);
	// Where the trace misses: off-screen land, the far scene, or the sky
	vec3 far;
	float land = overheadReflection(player, rWorld, ign(gl_FragCoord.xy + 7.0));
	if (land > 0.0)
		far = hazeOnReflection(a, landColour(a, player + rWorld * land), world, rWorld, land);
	else
		far = farReflection(a, world, rWorld, skyReflection(rWorld), length(view));
	vec3 rView = normalize(mat3(prisma.viewMatrix) * rWorld);
	float hitDist;
	vec4 hit = traceReflection(view, rView, ign(gl_FragCoord.xy), hitDist);
	if (hit.a <= 0.0)
		return far;
	return mix(far, hazeOnReflection(a, hit.rgb, world, rWorld, hitDist), hit.a);
}

void main()
{
	vec3 color = texture(colorTex, texcoord).rgb;
	float depth = texture(depthTex, texcoord).r;
	// Seen from inside water, its upright and sloped faces mirror nothing
	bool fromInside = inLiquidNode() && !isSky(depth) && waterFace(texcoord).y < 0.7;
	if (isSky(depth) || underwater() || fromInside || !waterSurface(texcoord)) {
		fragColor = vec4(color, 1.0);
		return;
	}
	vec3 view = viewPosition(texcoord, depth);
	float dist = length(view);
	vec3 player = (prisma.viewMatrixInverse * vec4(view, 1.0)).xyz;
	vec3 v = player / max(dist, 1e-4);
	vec3 world = player + prisma.cameraPosition;
	float clarity = prismaLuantiFogClarity(dist);
	if (clarity < 0.01) {
		fragColor = vec4(color, 1.0);
		return;
	}

	Atmos a = atmosState();
	vec3 n = waterSurfaceNormal(texcoord, world, dist);
	// Refraction: the bottom shifted by the waves (only onto water)
	vec2 shift = (n - waterFace(texcoord)).xz * 0.05 / (1.0 + dist * 0.12);
	vec2 uv = texcoord + vec2(shift.x, -shift.y) * vec2(prisma.viewSize.y / prisma.viewSize.x, 1.0);
	if (waterSurface(uv) && !isSky(texture(depthTex, uv).r))
		color = texture(colorTex, uv).rgb;
	vec3 lin = toLinear(color);
	// Luanti's blue towards a deep teal
	vec3 deep = (a.ambient * 0.4 + a.directLight * 0.05) * vec3(0.06, 0.40, 0.40);
	lin = mix(lin, deep, options.water_tint * 0.7);

	float cosT = clamp(dot(-v, n), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
	if (options.water > 0.0) {
		vec3 refl = reflectionOf(a, view, player, world, n, v);
		lin = mix(lin, refl, clamp(fresnel * options.water, 0.0, 1.0) * clarity);
		lin += glint(a, n, v, 0.03, 0.02, player, world) * options.water * clarity;
	}
	fragColor = vec4(toSrgb(lin), 1.0);
}
