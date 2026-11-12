// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Relights Luanti's colour, split with the G-buffer into sky light and
	torch light:
	  * sun or moon: a share of the daylight, through soft, cloud and
	    contact shadows; deep on clear days, faint when overcast;
	  * sky: fill in the shade, with ambient occlusion;
	  * torches: warm, flickering, pooling around the flame;
	  * coloured light of glowing blocks, light through leaves, wet ground.
	Luanti's fog is undone here; 40_fog_apply.frag adds the pack's.
*/
#ifndef VESPER_LIGHT
#define VESPER_LIGHT

#include "clouds.glsl"
#include "shadows.glsl"

const vec3 TORCH = vec3(1.00, 0.58, 0.28);

// ---- Ambient occlusion ------------------------------------------------------------

// 16_ao.frag's occlusion, smoothed with neighbours at a similar distance
float occlusionAt(vec2 uv, float dist)
{
#if AO_QUALITY == AO_QUALITY_OFF
	return 1.0;
#else
	if (options.ambient_occlusion <= 0.0)
		return 1.0;
	vec2 size = vec2(textureSize(ao, 0));
	vec2 base = uv * size - 0.5;
	float sum = 0.0;
	float weight = 0.0;
	for (int x = -1; x <= 2; x++)
		for (int y = -1; y <= 2; y++) {
			ivec2 c = clamp(ivec2(floor(base)) + ivec2(x, y), ivec2(0), ivec2(size) - 1);
			vec2 s = texelFetch(ao, c, 0).rg;
			vec2 off = vec2(c) - base;
			float w = exp(-dot(off, off) * 0.6) * (1.0 - smoothstep(0.0, 0.05 * dist + 0.15, abs(s.g - dist)));
			sum += s.r * w;
			weight += w;
		}
	float occ = weight > 0.01 ? sum / weight : 1.0;
	return pow(occ, options.ambient_occlusion);
#endif
}

// ---- Wet ground ---------------------------------------------------------------------

// Wetness (0..1): open to the sky, facing up
float wetness(Atmos a, vec3 player, vec3 normal, float skyLevel)
{
	if (a.w.wet <= 0.001 || underwater())
		return 0.0;
	float exposed = prisma.overheadAvailable ? overheadExposure(player + normal * 0.05, 0.4) : smoothstep(0.85, 1.0, skyLevel);
	float facing = dot(normal, normal) > 0.0 ? mix(0.35, 1.0, smoothstep(0.0, 0.8, normal.y)) : 0.6;
	return a.w.wet * exposed * facing;
}

// Puddles (0..1): flat, open, in the dips of a large noise
float puddleMask(Atmos a, vec3 world, vec3 normal, float wet)
{
	if (options.puddles <= 0.0 || wet <= 0.01 || normal.y < 0.9)
		return 0.0;
	float n = fbm2(world.xz * 0.11 + 3.0, 3);
	float level = mix(0.75, 0.35, options.puddles * smoothstep(0.2, 1.0, a.w.wet));
	return smoothstep(level, level + 0.08, n) * smoothstep(0.3, 0.8, wet);
}

// ---- Torches ----------------------------------------------------------------------

float torchFlicker(vec3 world)
{
	if (options.torch_flicker <= 0.0)
		return 1.0;
	float t = prisma.frameTimeCounter;
	// Each patch flickers on its own: slow breathing, quick sputters
	vec2 cell = floor(world.xz / 6.0);
	float seed = hash12(cell) * 50.0;
	float slow = vnoise2(vec2(t * 1.3 + seed, seed));
	float fast = vnoise2(vec2(t * 7.0 + seed * 3.0, seed + 9.0));
	return 1.0 + (slow * 0.6 + fast * 0.4 - 0.5) * 0.45 * options.torch_flicker;
}

// ---- The light ------------------------------------------------------------------------

// Lights a pixel of the world: sRGB in (Luanti's colour), linear out
vec3 lightWorld(vec3 color, vec2 uv, float depth, Atmos a)
{
	vec3 view = viewPosition(uv, depth);
	vec3 player = (prisma.viewMatrixInverse * vec4(view, 1.0)).xyz;
	float dist = length(view);
	vec3 dir = player / max(dist, 1e-4);
	vec3 world = player + prisma.cameraPosition;

	// Undo Luanti's fog; past its end only sky (fog.glsl continues the ray)
	float clarity = prismaLuantiFogClarity(dist);
	vec3 background = skyDome(a, dir);
	if (clarity < 0.002)
		return background;
	vec3 oldFog = prismaLuantiFogTint(prisma.fogColor, clarity);
	vec3 base = toLinear(max((color - (1.0 - clarity) * oldFog) / clarity, vec3(0.0)));
	// Underwater Luanti tints everything blue; the pack's water gives the colour
	if (underwater())
		base = mix(vec3(luminance(base)), base, 0.3);
	vec3 original = base;

	bool liquid = waterSurface(uv);
	int kind = liquid ? PRISMA_MAT_LIQUID : gbufferMaterial(uv);
	vec3 normal = liquid ? vec3(0.0, 1.0, 0.0) : gbufferNormal(uv);
	bool hasNormal = dot(normal, normal) > 0.0;
	float natural = liquid ? 1.0 : 1.0 - pow(max(0.0, 1.0 - gbufferSunlight(uv)), 0.6);
	float skyLevel = gbufferSkyLight(uv);
	float blockLevel = gbufferBlockLight(uv);

	// Light sources keep their own colour and brightness
	float m = maxOf(color);
	float saturation = (m - min(color.r, min(color.g, color.b))) / max(m, 1e-3);
	float emissive = smoothstep(0.6, 0.95, m) * smoothstep(0.6, 0.95, blockLevel) * (1.0 - natural * a.day) *
		smoothstep(0.1, 0.4, saturation + 0.15);
	if (kind == PRISMA_MAT_LIQUID_OPAQUE) // lava
		emissive = 1.0;
	float receives = 1.0 - emissive;

	// ---- Sun or moon
	vec3 L = a.lightDir;
	float strength = prisma.sunAvailable ? prismaLuantiShadowStrength(1.0) : 0.0;
	float share = a.directShare * saturate(strength * 2.0);
	float vis = 1.0;
	float lit = 0.0;
	if (share > 0.001) {
		float sunSize = (0.004 + 0.008 * options.shadow_softness) * (1.0 + 2.5 * a.overcast);
		vis = softShadow(player, normal, sunSize);
		if (vis > 0.0)
			vis *= cloudShadow(a, world, L, 3);
		if (options.contact_shadows && vis > 0.0 && dist < 48.0 && !liquid)
			vis *= mix(contactShadow(view, L, ign(gl_FragCoord.xy)), 1.0, smoothstep(24.0, 48.0, dist));
		float terminator = hasNormal ? smoothstep(-0.02, 0.22, dot(normal, L)) : 1.0;
		lit = vis * terminator;
	}
	// Shadows fade at sunrise and sunset, as the light switches body
	lit = mix(1.0, lit, strength);

	// ---- Sky
	float occlusion = liquid ? 1.0 : occlusionAt(uv, dist);
	float up = hasNormal ? normal.y * 0.5 + 0.5 : 0.75;
	vec3 skyTint = normalizeLum(mix(a.horizon, a.zenith, up) + vec3(1e-4));
	skyTint = mix(vec3(1.0), skyTint, 0.55);

	vec3 direct = normalizeLum(a.directLight + vec3(1e-5)) * 1.12;
	vec3 mulNatural = direct * share * lit + skyTint * (1.0 - share) * occlusion;
	// A duller day under a grey sky, a dark one in a storm; blue nights
	float dayLevel = mix(1.0, 0.78, a.overcast) * mix(1.0, 0.7, a.w.storm);
	vec3 nightTint = mix(vec3(1.0), normalizeLum(MOON_BLUE), options.moon_blue * 0.85);
	vec3 nightLevel = nightTint * mix(1.0, 0.1, options.night_darkness);
	mulNatural *= mix(nightLevel, vec3(dayLevel), a.day);
	// Lightning: a flash on everything under the open sky
	mulNatural += FLASH * a.w.flash * skyLevel * skyLevel * 1.4;

	// ---- Torches
	float level = max(blockLevel, 1e-3);
	float falloff = pow(level, 1.0 + 1.6 * options.torch_falloff) / level;
	vec3 torchColor = mix(vec3(1.0), normalizeLum(TORCH), options.torch_warmth);
	vec3 mulTorch = torchColor * options.torch_brightness * falloff * torchFlicker(world) * mix(0.85, 1.0, occlusion);

	base *= mix(vec3(1.0), mix(mulTorch, mulNatural, natural), receives);

	// ---- Coloured light of glowing blocks
	vec3 albedo = min(original / max(luminance(original), 0.03), vec3(3.0)) * 0.3;
	vec3 glowLight = glowAt(uv, 1.5, dist) * 0.35 + glowAt(uv, 3.0, dist) * 0.65;
	base += albedo * glowLight * options.colored_light * 4.0 * receives * mix(0.6, 1.0, occlusion);

	// ---- Leaves and grass let the sun through when seen against it
	if ((kind == PRISMA_MAT_LEAVES || kind == PRISMA_MAT_PLANTS) && options.foliage > 0.0) {
		float against = pow(saturate(dot(dir, L)), 3.0);
		float through = vis * share * natural * (0.1 + against);
		base += original * direct * through * options.foliage * 0.9 * dayLevel;
	}

	// ---- Under the water: caustics where the sun reaches
	if (underwater() && hasNormal && options.caustics > 0.0) {
		vec2 p = world.xz - L.xz / max(L.y, 0.2) * world.y;
		float here = lit * share * natural * max(dot(normal, L), 0.0) * (1.0 - smoothstep(6.0, 32.0, dist));
		base *= 1.0 + caustics(p, prisma.frameTimeCounter) * options.caustics * 2.5 * here;
	}

	// ---- Wet ground: darker and richer (30_water.frag adds the shine)
	if (!liquid && kind != PRISMA_MAT_ENTITY) {
		float wet = wetness(a, player, normal, skyLevel) * receives;
		if (wet > 0.0) {
			float puddle = puddleMask(a, world, normal, wet);
			float darken = mix(1.0, 0.52, wet) * mix(1.0, 0.6, puddle);
			base = mix(vec3(luminance(base)), base, 1.0 + 0.25 * wet) * darken;
			base = max(base, vec3(0.0));
		}
	}

	return mix(background, base, clarity);
}

#endif
