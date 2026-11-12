// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Haze (thinner with height) and low morning mist (3D noise banks).
	18_fog.frag marches each ray near the camera; each step asks the shadow
	map and the clouds whether the sun reaches it, giving true light shafts.
	Sky light fills the air where the sky is open (overhead map). The rest
	of the ray is integrated in closed form. Energy conserving per step.
*/
#ifndef AURORA_FOG
#define AURORA_FOG

#include "clouds.glsl"
#include "shadows.glsl"

// Haze under a hidden sky, relative to the open-air haze
const float HIDDEN_HAZE = 1.6;
// ...and from how far the glow lights it (not the air around the camera)
const vec2 HIDDEN_GLOW_NEAR = vec2(8.0, 56.0);

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
	f.haze = options.fog_density * (1.0 + a.overcast * 0.4 + a.golden * 1.2 + a.night * 0.2);
	if (prisma.skyHidden) {
		// Underground: the same thick haze everywhere, no mist
		f.haze = options.fog_density * HIDDEN_HAZE;
		f.hazeK = 0.0;
		f.mist = 0.0;
		f.mistTop = 0.0;
		f.drift = vec3(0.0);
		return f;
	}
	f.hazeK = options.fog_falloff;
	float dawn = a.golden * step(0.0, a.sunDir.x); // the sun rises at +x in Luanti
	// Mostly in the morning: by noon only a trace in the hollows
	f.mist = options.mist * 0.008 * (0.05 + dawn * 2.0 + a.night * 0.4);
	f.mistTop = options.fog_height;
	float t = prisma.frameTimeCounter;
	f.drift = vec3(WIND_DIR.x, 0.15, WIND_DIR.y) * t * 1.2;
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
#if !MIST_BANKS
	// Potato: no banks, the average density
	return f.mist * 0.25 * exp(-0.12 * max(above, 0.0));
#endif
	vec3 q = (world - f.drift) * vec3(0.018, 0.045, 0.018);
	float n = fbm3(q, 2);
	float banks = smoothstep(0.4, 0.8, n);
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

// Light scattered towards the eye per unit of optical depth
struct FogLight {
	vec3 sun;      // times the sun's visibility (the marched part)
	vec3 sunFar;   // the rest of the ray, in the open
	vec3 ambient;  // times the sky's visibility
};

FogLight fogLight(Atmos a, vec3 dir)
{
	FogLight l;
	float c = dot(dir, a.lightDir);
	l.sun = a.directLight * PI * hazePhase(c) * options.shafts;
	// Far away a gentler lobe, so a low sun glows instead of washing out
	l.sunFar = a.directLight * PI * mix(hgPhase(c, -0.2), hgPhase(c, 0.5), 0.6);
	l.ambient = a.ambient * 0.9;
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
	rgb = light the air adds, a = transmittance. `dist`: to the scene, or SKY_FOG_DIST.
*/
// Under a hidden sky: warm air in front of lamp-lit surfaces (G-buffer block light)
const vec3 LAMP_HAZE = vec3(1.00, 0.60, 0.30);

vec3 lampHaze(vec2 uv, float dist)
{
	float lamp = gbufferBlockLight(uv);
	vec3 warm = mix(vec3(1.0), normalizeLum(LAMP_HAZE), options.torch_warmth);
	return warm * lamp * lamp * (1.0 - exp(-dist / 40.0)) * 0.05 * options.torch_brightness;
}

vec4 fogAlong(Atmos a, vec3 dir, float dist, bool sky, float jitter)
{
	FogParams f = fogParams(a);
	FogLight l = fogLight(a, dir);
	vec3 cam = prisma.cameraPosition;
	vec3 L = a.lightDir;
	// The sky (and land past Luanti's fog) gets the horizon haze
	float skyMix = sky ? 1.0 : smoothstep(0.0, SKY_FOG_DIST, dist);
	float hazeScale = mix(1.0, options.sky_haze, skyMix);
	float T = 1.0;
	vec3 light = vec3(0.0);

	float marchEnd = min(dist, max(prisma.shadowDistance * 1.25, 96.0));
#if !FOG_CLOUD_PER_STEP
	// Potato: the clouds' shade once per ray
	float rayCloud = maxOf(l.sun) > 1e-5 ? cloudShadow(cam + dir * (marchEnd * 0.3), L, 1) : 1.0;
#endif
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
#if FOG_CLOUD_PER_STEP
			if (vis > 0.0)
				vis *= cloudShadow(world, L, 1);
#else
			vis *= rayCloud;
#endif
		}
		if (prisma.skyHidden)
			vis *= smoothstep(HIDDEN_GLOW_NEAR.x, HIDDEN_GLOW_NEAR.y, tm);
		vec3 S = l.sun * vis + l.ambient * skyVis;
		float stepT = exp(-sigma * dt);
		light += T * S * (1.0 - stepT);
		T *= stepT;
		if (T < 0.003)
			break;
	}

	// The rest of the ray in closed form, with the clouds' average shade
	float rest = dist - marchEnd;
	if (rest > 0.0 && T > 0.003) {
		vec3 start = cam + dir * marchEnd;
		float od = fogDepth(f, start, dir, rest) * hazeScale;
		// Far away, the clouds' average shade (one sample drew rings)
		float farVis = cloudShadow(start + dir * min(rest, 400.0), L, 1);
		float average = options.clouds ? 1.0 - options.cloud_shadows * options.cloud_cover * 0.45 : 1.0;
		farVis = mix(farVis, average, smoothstep(150.0, 800.0, rest));
		vec3 S = l.sunFar * farVis + l.ambient;
		float restT = exp(-od);
		light += T * S * (1.0 - restT);
		T *= restT;
	}
	return vec4(light, T);
}

// ---- Under the water -------------------------------------------------------------------

// The colour water gives the light (linear): blue-green, towards the liquid's tint
vec3 waterTint()
{
	vec3 tint = toLinear(prisma.liquidColor.rgb);
	return mix(vec3(0.16, 0.46, 0.52), normalizeLum(tint + vec3(0.02)) * 0.4, 0.35);
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
	float phase = mix(hgPhase(dot(dir, L), 0.65), 1.0 / (4.0 * PI), 0.3);
	vec3 sun = a.directLight * PI * phase * options.shafts * 1.6 * tint;
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
			a.ambient * tint * mix(0.15, 0.6, dir.y * 0.5 + 0.5);
		float stepT = exp(-sigma * dt);
		light += T * S * (1.0 - stepT);
		T *= stepT;
	}
	float rest = dist - marchEnd;
	if (rest > 0.0) {
		float restT = exp(-sigma * rest);
		light += T * a.ambient * tint * mix(0.15, 0.6, dir.y * 0.5 + 0.5) * (1.0 - restT);
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
