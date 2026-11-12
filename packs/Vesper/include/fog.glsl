// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Haze (thick near the ground, thinner with height) and mist banks in the
	valleys (3D noise; thicker at dawn, at night and in rain). 18_fog.frag
	marches each ray near the camera; each step asks the shadow map and the
	clouds whether the sun reaches it, giving true light shafts. Sky light
	fills open air (overhead map); torches and glowing blocks light the air
	around them. The rest of the ray is closed form; energy conserving.
*/
#ifndef VESPER_FOG
#define VESPER_FOG

#include "clouds.glsl"
#include "shadows.glsl"

#if FOG_QUALITY == FOG_QUALITY_LOW
const int FOG_STEPS = 8;
#elif FOG_QUALITY == FOG_QUALITY_MEDIUM
const int FOG_STEPS = 14;
#elif FOG_QUALITY == FOG_QUALITY_HIGH
const int FOG_STEPS = 22;
#else
const int FOG_STEPS = 36;
#endif

const float SKY_FOG_DIST = 3500.0;

struct FogParams {
	float haze;      // density at fog_height
	float hazeK;     // falloff of the haze with height
	float mist;      // density of the mist banks
	float mistTop;   // height where the mist thins out
	vec3 drift;      // the mist drifts with the wind
};

FogParams fogParams(Atmos a)
{
	FogParams f;
	float weather = 1.0 + a.overcast * 0.4 + a.w.rain * 0.9 + a.w.storm * 0.5;
	f.haze = options.fog_density * weather * (1.0 + a.golden * 0.35 + a.night * 0.25);
	f.hazeK = options.fog_falloff;
	float dawn = a.golden * step(0.0, a.sunDir.x); // the sun rises at +x in Luanti
	f.mist = options.mist * 0.010 * (1.0 + dawn * 0.8 + a.night * 0.5 + a.w.rain * 0.8);
	f.mistTop = options.fog_height;
	float t = prisma.frameTimeCounter;
	vec2 wind = normalize(vec2(1.0, 0.35)) * (0.6 + 4.0 * options.wind + 3.0 * a.w.storm);
	f.drift = vec3(wind.x, 0.15, wind.y) * t;
	return f;
}

// Density of the haze alone at height `y`
float hazeDensity(FogParams f, float y)
{
	return f.haze * exp(-f.hazeK * clamp(y - f.mistTop, -12.0, 1e4));
}

// Density of the mist banks at `world`
float mistDensity(FogParams f, vec3 world)
{
	if (f.mist <= 0.0)
		return 0.0;
	float above = world.y - f.mistTop;
	if (above > 40.0)
		return 0.0;
	vec3 q = (world - f.drift) * vec3(0.018, 0.045, 0.018);
	float n = fbm3(q, 2);
	float banks = smoothstep(0.38, 0.78, n);
	return f.mist * banks * banks * 2.0 * exp(-0.12 * max(above, 0.0));
}

float fogDensity(FogParams f, vec3 world)
{
	return hazeDensity(f, world.y) + mistDensity(f, world);
}

// Optical depth of d0 * exp(-k * (height - h0)) from height `y`, rising `dy` per node, over `t` nodes
float expPart(float d0, float h0, float k, float y, float dy, float t)
{
	float yEnd = y + dy * t;
	if (abs(k * dy * t) < 1e-4)
		return d0 * exp(-k * (0.5 * (y + yEnd) - h0)) * t;
	return max(d0 * (exp(-k * (y - h0)) - exp(-k * (yEnd - h0))) / (k * dy), 0.0);
}

// The same with the density capped `under` nodes below h0
float expLayerDepth(float d0, float h0, float k, float y, float dy, float t, float under)
{
	float floorY = h0 - under;
	float capD = d0 * exp(under * k);
	bool below = y < floorY;
	float sc = abs(dy) > 1e-6 ? (floorY - y) / dy : -1.0;
	if (sc > 0.0 && sc < t) {
		if (below)
			return capD * sc + expPart(d0, h0, k, floorY, dy, t - sc);
		return expPart(d0, h0, k, y, dy, sc) + capD * (t - sc);
	}
	return below ? capD * t : expPart(d0, h0, k, y, dy, t);
}

// Optical depth of both layers in closed form (mist at its average)
float fogDepth(FogParams f, vec3 world, vec3 dir, float t)
{
	float od = expLayerDepth(f.haze, f.mistTop, f.hazeK, world.y, dir.y, t, 12.0);
	od += expLayerDepth(f.mist * 0.25, f.mistTop, 0.12, world.y, dir.y, t, 0.0);
	return od;
}

// Light scattered per unit of optical depth: the sun's part (times visibility), the rest ambient
struct FogLight {
	vec3 sun;      // times visibility
	vec3 ambient;  // times sky visibility
	vec3 glow;     // torches and glowing blocks nearby
	float glowFrom; // how far that light is (14_glow.frag)
};

FogLight fogLight(Atmos a, vec3 dir, vec2 uv)
{
	FogLight l;
	float phase = hazePhase(dot(dir, a.lightDir));
	l.sun = a.directLight * PI * phase * options.shafts;
	l.ambient = a.ambient * 0.85 + FLASH * a.w.flash * 0.3;
	vec4 g = textureLod(glow, uv, 3.0);
	l.glow = g.rgb * options.colored_light * 4.0;
	l.glowFrom = g.a / max(luminance(g.rgb), 1e-5);
	return l;
}

// How much sky a point in the air sees (overhead map)
float airSkyVisibility(vec3 player)
{
	if (!prisma.overheadAvailable)
		return 1.0;
	return mix(0.12, 1.0, overheadExposure(player, 3.0));
}

/*
	Without steps: how open this pixel's air is, 0.12 (enclosed) to 1
	(outdoors), from Luanti's sky light of what the pixel shows. Smooth from
	node to node, unlike the camera's own cover or the maps.
*/
float pixelOpenness(vec2 uv, bool sky)
{
	if (sky)
		return 1.0;
	return mix(0.12, 1.0, smoothstep(0.05, 0.7, gbufferSkyLight(uv)));
}

// Distance the fog is computed to; past Luanti's fog the ray continues as sky
float fogDistance(float dist, bool sky)
{
	if (sky)
		return SKY_FOG_DIST;
	float clarity = prismaLuantiFogClarity(dist);
	return mix(SKY_FOG_DIST, dist, clarity);
}

/*
	rgb = light the air adds, a = transmittance. `dist`: see fogDistance().
*/
vec4 fogAlong(Atmos a, vec3 dir, float dist, bool sky, vec2 uv, float jitter)
{
	FogParams f = fogParams(a);
	FogLight l = fogLight(a, dir, uv);
	vec3 cam = prisma.cameraPosition;
	vec3 L = a.lightDir;
	// The sky (and land past Luanti's fog) gets the horizon haze
	float skyMix = sky ? 1.0 : smoothstep(0.0, SKY_FOG_DIST, dist);
	float hazeScale = mix(1.0, options.sky_haze, skyMix);
	float T = 1.0;
	vec3 light = vec3(0.0);
	float marchEnd = 0.0;

#if FOG_QUALITY != FOG_QUALITY_OFF
	marchEnd = min(dist, max(prisma.shadowDistance * 1.25, 96.0));
	for (int i = 0; i < FOG_STEPS; i++) {
		// Denser steps close to the camera
		float s = (float(i) + jitter) / float(FOG_STEPS);
		float s1 = (float(i) + 1.0 + jitter) / float(FOG_STEPS);
		float t0 = marchEnd * s * s;
		float t1 = marchEnd * min(s1 * s1, 1.0);
		float dt = t1 - t0;
		if (dt <= 0.0)
			continue;
		float tm = (t0 + t1) * 0.5;
		vec3 player = dir * tm;
		vec3 world = cam + player;
		float skyVis = airSkyVisibility(player);
		// Enclosed air (caves, houses) is thinner and has no mist
		float sigma = fogDensity(f, world) * hazeScale * mix(0.35, 1.0, skyVis);
		if (sigma < 1e-6)
			continue;
		float vis = 0.0;
		if (maxOf(l.sun) > 1e-5) {
			vis = hardShadow(player);
			if (vis > 0.0)
				vis *= cloudShadow(a, world, L, 1);
		}
		// Torch light lights the air near the torch only
		float near = exp(-abs(tm - l.glowFrom) / (2.0 + 0.12 * l.glowFrom));
		vec3 S = l.sun * vis + l.ambient * skyVis + l.glow * near;
		float stepT = exp(-sigma * dt);
		light += T * S * (1.0 - stepT);
		T *= stepT;
		if (T < 0.003)
			break;
	}
#endif

	// The rest of the ray in closed form, with the clouds' average shade
	float rest = dist - marchEnd;
	if (rest > 0.0 && T > 0.003) {
		vec3 start = cam + dir * marchEnd;
		float od = fogDepth(f, start, dir, rest) * hazeScale;
		float farVis = cloudShadow(a, start + dir * min(rest, 400.0), L, 1);
		// Without steps no shafts: the sun lights open air evenly
		float open = marchEnd > 0.0 ? 1.0 : pixelOpenness(uv, sky);
		float sunShare = marchEnd > 0.0 ? 1.0 : smoothstep(0.2, 0.7, open);
		// ...and evenly in all directions (no shadow map to say what is lit)
		vec3 sun = marchEnd > 0.0 ? l.sun : a.directLight * 0.25 * options.shafts;
		vec3 S = sun * farVis * sunShare + l.ambient * open;
		float restT = exp(-od);
		light += T * S * (1.0 - restT);
		T *= restT;
	}
	return vec4(light, T);
}

// ---- Under the water -------------------------------------------------------------------

// The colour water gives the light (linear), from the liquid's tint
vec3 waterTint()
{
	vec3 tint = toLinear(prisma.liquidColor.rgb);
	return mix(vec3(0.30, 0.42, 0.30), normalizeLum(tint + vec3(0.02)) * 0.4, 0.5);
}

/*
	Inside the water: sun shafts through the gaps above, swaying with the
	caustics. rgb = scattered light (already tinted), a = transmittance.
	40_fog_apply.frag applies the colour lost with distance.
*/
vec4 underwaterAlong(Atmos a, vec3 dir, float dist, float jitter)
{
	vec3 cam = prisma.cameraPosition;
	vec3 L = a.lightDir;
	vec3 tint = waterTint();
	float sigma = options.underwater_fog;
	float phase = mix(hgPhase(dot(dir, L), 0.6), 1.0 / (4.0 * PI), 0.3);
	vec3 sun = a.directLight * PI * phase * options.shafts * 1.5 * tint;
	float time = prisma.frameTimeCounter;
	float marchEnd = min(dist, 40.0);
	const int N = 16;
	float T = 1.0;
	vec3 light = vec3(0.0);
	for (int i = 0; i < N; i++) {
		float s = (float(i) + jitter) / float(N);
		float s1 = (float(i) + 1.0 + jitter) / float(N);
		float t0 = marchEnd * s * s;
		float t1 = marchEnd * min(s1 * s1, 1.0);
		float dt = t1 - t0;
		if (dt <= 0.0)
			continue;
		vec3 player = dir * ((t0 + t1) * 0.5);
		vec3 world = cam + player;
		float vis = maxOf(sun) > 1e-5 ? hardShadow(player) : 0.0;
		if (vis > 0.0) {
			// The waves overhead focus the light into moving bands
			vec2 p = world.xz - L.xz / max(L.y, 0.2) * world.y;
			vis *= 0.25 + 1.6 * caustics(p * 0.5, time * 0.8);
		}
		float depthBelow = max(cam.y - world.y, 0.0) + 2.0;
		vec3 S = sun * vis * exp(-sigma * depthBelow * 0.5) +
			a.ambient * tint * mix(0.12, 0.55, dir.y * 0.5 + 0.5);
		float stepT = exp(-sigma * dt);
		light += T * S * (1.0 - stepT);
		T *= stepT;
	}
	float rest = dist - marchEnd;
	if (rest > 0.0) {
		float restT = exp(-sigma * rest);
		light += T * a.ambient * tint * mix(0.12, 0.55, dir.y * 0.5 + 0.5) * (1.0 - restT);
		T *= restT;
	}
	return vec4(light, T);
}

// ---- The fog buffer: rgb = light, a = distance and transmittance packed --------

float packFog(float dist, float T)
{
	return floor(clamp(dist, 0.0, 4000.0) * 4.0) + clamp(T, 0.0, 1.0) * 0.999;
}

vec2 unpackFog(float a)
{
	return vec2(floor(a) * 0.25, fract(a) / 0.999);
}

#endif
