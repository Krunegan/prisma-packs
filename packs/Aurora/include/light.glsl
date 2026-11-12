// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Relights Luanti's colour, split with the G-buffer into sky light and
	torch light:
	  * sun or moon: most of the daylight, through soft, cloud and contact
	    shadows, with the surface's terminator;
	  * sky: blue fill in the shade, with ambient occlusion;
	  * torches: warm, pooling around the flame; no coloured light;
	  * light through leaves and grass, caustics under water;
	  * satin finish: a soft sun and sky sheen on sunlit blocks only.
	Luanti's fog is undone here; 40_fog_apply.frag adds the pack's.
*/
#ifndef AURORA_LIGHT
#define AURORA_LIGHT

#include "clouds.glsl"
#include "shadows.glsl"

const vec3 TORCH = vec3(1.00, 0.56, 0.24);

// ---- Ambient occlusion ------------------------------------------------------------

// 16_ao.frag's occlusion, smoothed with neighbours at a similar distance
float occlusionAt(vec2 uv, float dist)
{
#if AO_SLICES == 0
	return 1.0;
#else
	if (!options.ao || options.ambient_occlusion <= 0.0)
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

// ---- Satin finish ---------------------------------------------------------------------
/*
	Satin finish: a rough GGX sun lobe and a Fresnel sky sheen, white, like
	a clear coat. Direct light only: the shade stays matte.
*/
float satinGgx(float nh, float roughness)
{
	float a2 = roughness * roughness;
	a2 *= a2;
	float d = nh * nh * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d);
}

// Schlick's Fresnel for a rough surface (Lagarde's fit, roughness 0.55)
float satinFresnel(float cosT)
{
	return 0.04 + (0.45 - 0.04) * pow(1.0 - cosT, 5.0);
}

// The sun's highlight on `n` seen along `v`, without light or shadow
float satinSun(vec3 v, vec3 n, vec3 L)
{
	float nl = dot(n, L);
	if (nl <= 0.0)
		return 0.0;
	vec3 h = normalize(L - v);
	float nh = max(dot(n, h), 0.0);
	float nv = max(dot(n, -v), 1e-3);
	// Smith masking (Schlick-GGX): rough surfaces hide their highlight at grazing angles
	const float k = 0.55 * 0.55 * 0.5;
	float vis = 1.0 / ((nl * (1.0 - k) + k) * (nv * (1.0 - k) + k) * 4.0);
	float spec = satinGgx(nh, 0.55) * satinFresnel(max(dot(h, -v), 0.0)) * vis * nl;
	return spec * smoothstep(0.0, 0.1, nl);
}

// The sky's sheen on normal `n` seen along `v`
vec3 satinSky(Atmos a, vec3 v, vec3 n)
{
	vec3 r = reflect(v, n);
	r.y = max(r.y, 0.02);
	// Rough: the sky's average light around r
	vec3 sky = mix(skyDome(a, normalize(r)), a.ambient, 0.5);
	return sky * (satinFresnel(max(dot(n, -v), 0.0)) - 0.04) * 0.3;
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
	vec3 behind = background(a, dir);
	if (clarity < 0.002)
		return behind;
	vec3 oldFog = prismaLuantiFogTint(prisma.fogColor, clarity);
	vec3 base = toLinear(max((color - (1.0 - clarity) * oldFog) / clarity, vec3(0.0)));
	// Underwater Luanti tints everything blue; the pack's water gives the colour
	if (underwater())
		base = mix(vec3(luminance(base)), base, 0.35);
	vec3 original = base;

	bool liquid = waterSurface(uv);
	int kind = liquid ? PRISMA_MAT_LIQUID : gbufferMaterial(uv);
	// A liquid's face from the depth buffer, turned up when seen from below
	vec3 normal = liquid ? depthFaceNormal(uv) : gbufferNormal(uv);
	if (liquid && normal.y < -0.7)
		normal = -normal;
	// Past gbuffer_distance (Potato): no normal, the face is lit whole
	bool hasNormal = dot(normal, normal) > 0.0;
	float natural = liquid ? 1.0 : 1.0 - pow(max(0.0, 1.0 - gbufferSunlight(uv)), 0.6);
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
	// Under a hidden sky: the horizon glow, when Prisma draws its shadows
	float strength = prisma.sunAvailable ? prismaLuantiShadowStrength(1.0)
		: (prisma.skyHidden && prisma.shadowAvailable ? 1.0 : 0.0);
	float share = a.directShare * saturate(strength * 2.0);
	float vis = 1.0;
	float lit = 0.0;
	if (share > 0.001) {
		float sunSize = (0.004 + 0.008 * options.shadow_softness) * (1.0 + 2.5 * a.overcast);
		vis = softShadow(player, normal, sunSize);
		if (vis > 0.0)
			vis *= cloudShadow(world, L, CLOUD_SHADOW_OCTAVES);
#if CONTACT_SHADOWS
		if (vis > 0.0 && dist < 48.0 && !liquid)
			vis *= mix(contactShadow(view, L, ign(gl_FragCoord.xy)), 1.0, smoothstep(24.0, 48.0, dist));
#endif
		float terminator = hasNormal ? smoothstep(-0.02, 0.22, dot(normal, L)) : 1.0;
		lit = vis * terminator;
	}
	// Shadows fade at sunrise and sunset, as the light switches body
	lit = mix(1.0, lit, strength);

	// ---- Sky: the blue of the sky above fills the shade
	float occlusion = liquid ? 1.0 : occlusionAt(uv, dist);
	float up = hasNormal ? normal.y * 0.5 + 0.5 : 0.75;
	vec3 skyTint = normalizeLum(mix(a.horizon, a.zenith, up) + vec3(1e-4));
	skyTint = mix(vec3(1.0), skyTint, 0.4);

	vec3 direct = normalizeLum(a.directLight + vec3(1e-5)) * 1.2;
	// Sun and shade far apart, more so at night so moonlit things stand out
	float directGain = mix(2.2, 1.4, a.day) / 1.2;
	float fillGain = mix(0.5, 0.85, a.day);
	vec3 mulNatural = direct * directGain * share * lit +
		skyTint * (1.0 - share) * occlusion * options.sky_light * fillGain;
	// A duller day under a grey sky; blue nights
	float dayLevel = mix(1.0, 0.8, a.overcast);
	vec3 nightTint = mix(vec3(1.0), normalizeLum(MOON_BLUE), 0.75);
	vec3 nightLevel = nightTint * mix(1.0, 0.1, options.night_darkness);
	mulNatural *= mix(nightLevel, vec3(dayLevel), a.day);

	// ---- Torches and lanterns
	float level = max(blockLevel, 1e-3);
	float falloff = pow(level, 1.0 + 1.6 * options.torch_falloff) / level;
	vec3 torchColor = mix(vec3(1.0), normalizeLum(TORCH), options.torch_warmth);
	vec3 mulTorch = torchColor * options.torch_brightness * falloff * torchFlicker(world) * mix(0.85, 1.0, occlusion);
	// Under a hidden sky a faint glow of the place's colour fills the shade
	if (prisma.skyHidden)
		mulTorch += normalizeLum(placeColour() + vec3(1e-4)) * HIDDEN_SKY_GLOW * occlusion;

	base *= mix(vec3(1.0), mix(mulTorch, mulNatural, natural), receives);
	// Under a hidden sky the shadow map alone says what the glow reaches
	if (prisma.skyHidden)
		base += original * normalizeLum(a.directLight + vec3(1e-5)) * maxOf(a.directLight) * 2.4 * share * lit * receives;

	// ---- Leaves and grass let the sun through when seen against it
	if ((kind == PRISMA_MAT_LEAVES || kind == PRISMA_MAT_PLANTS) && options.foliage > 0.0) {
		float against = pow(saturate(dot(dir, L)), 3.0);
		float through = vis * share * natural * (0.12 + against * 1.4);
		// Light through a leaf: a deeper, warmer green
		vec3 leaf = original * mix(vec3(1.0), vec3(1.05, 1.1, 0.7), 0.5);
		base += leaf * direct * through * options.foliage * dayLevel;
	}

	// ---- Satin finish: direct light only; not on light sources, liquids or plants
	float sunlit = lit * smoothstep(0.0, 0.3, share) * natural;
	if (options.satin > 0.0 && sunlit > 0.001 && hasNormal && !liquid && kind != PRISMA_MAT_LEAVES &&
		kind != PRISMA_MAT_PLANTS) {
		vec3 sun = a.directLight * satinSun(dir, normal, L) * lit * share;
		// The sky's sheen too, where the sky is seen
		vec3 sky = satinSky(a, dir, normal) * occlusion * smoothstep(0.2, 0.9, gbufferSkyLight(uv)) * sunlit;
		base += (sun + sky) * options.satin * receives;
	}

	// ---- Under the water: caustics where the sun reaches
	if (underwater() && hasNormal && options.caustics > 0.0) {
		vec2 p = world.xz - L.xz / max(L.y, 0.2) * world.y;
		float here = lit * share * natural * max(dot(normal, L), 0.0) * (1.0 - smoothstep(6.0, 32.0, dist));
		base *= 1.0 + caustics(p, prisma.frameTimeCounter) * options.caustics * 2.5 * here;
	}

	return mix(behind, base, clarity);
}

#endif
