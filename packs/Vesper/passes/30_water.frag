// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Water: a dark, murky mirror (Fresnel), the bottom bent by the waves and
	stained brown, a sun or moon glint, rain ripples. Wet ground shines with
	the sky; puddles are flat mirrors.
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
	float vis = hardShadow(player) * cloudShadow(a, world, L, 2);
	return a.directLight * min(D * F * PI / (4.0 * nv), 200.0) * vis;
}

vec3 reflectionOf(Atmos a, vec3 view, vec3 world, vec3 n, vec3 v, bool trace)
{
	vec3 rWorld = reflect(v, n);
	vec3 sky = skyReflection(a, rWorld);
	if (!trace)
		return sky;
	vec3 rView = normalize(mat3(prisma.viewMatrix) * rWorld);
	float hitDist;
	vec4 hit = traceReflection(view, rView, ign(gl_FragCoord.xy), hitDist);
	if (hit.a <= 0.0)
		return sky;
	return mix(sky, hazeOnReflection(a, hit.rgb, world, rWorld, hitDist), hit.a);
}

void main()
{
	vec3 color = texture(colorTex, texcoord).rgb;
	float depth = texture(depthTex, texcoord).r;
	if (isSky(depth) || underwater()) {
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

	if (waterSurface(texcoord)) {
		if (options.water <= 0.0 && options.water_murk <= 0.0) {
			fragColor = vec4(color, 1.0);
			return;
		}
		Atmos a = atmosState();
		vec3 n = waterNormal(a, world, dist);
		// Refraction: the bottom shifted by the waves (only onto water)
		vec2 shift = n.xz * 0.04 / (1.0 + dist * 0.12);
		vec2 uv = texcoord + vec2(shift.x, -shift.y) * vec2(prisma.viewSize.y / prisma.viewSize.x, 1.0);
		if (waterSurface(uv) && !isSky(texture(depthTex, uv).r))
			color = texture(colorTex, uv).rgb;
		vec3 lin = toLinear(color);
		// Murky: Luanti's blue goes brown and dark
		vec3 deep = (a.ambient * 0.3 + a.directLight * 0.025) * vec3(0.55, 0.48, 0.32);
		lin = mix(vec3(luminance(lin)), lin, 0.35);
		lin = mix(lin, deep, options.water_murk * 0.85);

		float cosT = clamp(dot(-v, n), 0.0, 1.0);
		float fresnel = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
		vec3 refl = reflectionOf(a, view, world, n, v, true);
		lin = mix(lin, refl, clamp(fresnel * options.water, 0.0, 1.0) * clarity);
		lin += glint(a, n, v, mix(0.035, 0.09, a.w.rain), 0.02, player, world) * options.water * clarity;
		fragColor = vec4(toSrgb(lin), 1.0);
		return;
	}

	// Wet ground and puddles
	Atmos a = atmosState();
	if (a.w.wet <= 0.001) {
		fragColor = vec4(color, 1.0);
		return;
	}
	vec3 normal = gbufferNormal(texcoord);
	int kind = gbufferMaterial(texcoord);
	if (dot(normal, normal) < 0.5 || kind == PRISMA_MAT_ENTITY || kind == PRISMA_MAT_LIQUID_OPAQUE) {
		fragColor = vec4(color, 1.0);
		return;
	}
	float wet = wetness(a, player, normal, gbufferSkyLight(texcoord));
	if (wet <= 0.01) {
		fragColor = vec4(color, 1.0);
		return;
	}
	float puddle = puddleMask(a, world, normal, wet);
	vec3 n = normal;
	if (puddle > 0.0) {
		vec2 ripples = rainRipples(world.xz, prisma.frameTimeCounter, a.w.rain) * (1.0 - smoothstep(8.0, 40.0, dist));
		n = normalize(mix(normal, normalize(vec3(-ripples.x, 1.0, -ripples.y)), puddle));
	}
	vec3 lin = toLinear(color);
	float cosT = clamp(dot(-v, n), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
	float amount = mix(wet * 0.35, 1.0, puddle) * fresnel * clarity;
	vec3 refl = reflectionOf(a, view, world, n, v, puddle > 0.05);
	lin = mix(lin, refl, saturate(amount));
	lin += glint(a, n, v, mix(0.25, 0.05, puddle), 0.02, player, world) * mix(wet * 0.3, 1.0, puddle) * clarity;
	fragColor = vec4(toSrgb(lin), 1.0);
}
