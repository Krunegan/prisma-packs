// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Water and puddles: waves, rain ripples, reflections traced on screen
	(SSR), with the sky map where the trace misses. Reflections get the haze
	of the way back.
*/
#ifndef VESPER_WATER
#define VESPER_WATER

#include "fog.glsl"

#if REFLECTION_QUALITY == REFLECTION_QUALITY_LOW
const int SSR_STEPS = 14;
const int SSR_REFINE = 3;
#elif REFLECTION_QUALITY == REFLECTION_QUALITY_MEDIUM
const int SSR_STEPS = 22;
const int SSR_REFINE = 4;
#else
const int SSR_STEPS = 36;
const int SSR_REFINE = 6;
#endif

// ---- Waves ---------------------------------------------------------------------------

float waveHeight(vec2 p, float t, float storm)
{
	vec2 wind = normalize(vec2(1.0, 0.35));
	float h = vnoise2(p * 0.35 + wind * t * 0.35) * 0.55;
	h += vnoise2(mat2(0.8, 0.6, -0.6, 0.8) * p * 0.9 - wind.yx * t * 0.6) * 0.3;
	h += vnoise2(p * 2.3 + vec2(t * 0.9, -t * 0.5)) * 0.15;
	return h * (1.0 + storm * 1.5);
}

// Rain ripples: rings from random points; returns their slope (x, z)
vec2 rainRipples(vec2 p, float t, float rain)
{
	if (rain <= 0.01)
		return vec2(0.0);
	p *= 2.2;
	vec2 cell0 = floor(p);
	vec2 slope = vec2(0.0);
	for (int y = -1; y <= 1; y++)
		for (int x = -1; x <= 1; x++) {
			vec2 cell = cell0 + vec2(float(x), float(y));
			vec2 h = hash22(cell);
			if (h.x > rain * 0.9 + 0.1)
				continue;
			float age = fract(t * 1.1 + h.y);
			vec2 centre = cell + 0.2 + 0.6 * hash22(cell + 7.7);
			vec2 d = p - centre;
			float r = length(d);
			float front = r - age * 1.2;
			float ring = cos(front * 28.0) * exp(-front * front * 60.0) * (1.0 - age) * (1.0 - age);
			slope += d / max(r, 1e-3) * ring;
		}
	return slope * 0.6;
}

// World normal of the water at `world`, softened with distance
vec3 waterNormal(Atmos a, vec3 world, float dist)
{
	float t = prisma.frameTimeCounter;
	vec2 p = world.xz;
	float amp = options.water_waves * (0.6 + options.wind) * (1.0 - smoothstep(16.0, 120.0, dist) * 0.8);
	float e = 0.08;
	float h0 = waveHeight(p, t, a.w.storm);
	float hx = waveHeight(p + vec2(e, 0.0), t, a.w.storm);
	float hz = waveHeight(p + vec2(0.0, e), t, a.w.storm);
	vec2 slope = vec2(hx - h0, hz - h0) / e * amp * 0.12;
	slope += rainRipples(p, t, a.w.rain) * (1.0 - smoothstep(8.0, 40.0, dist));
	return normalize(vec3(-slope.x, 1.0, -slope.y));
}

// ---- Reflections -----------------------------------------------------------------------

// The sky and the clouds in direction `dir` (world), from the sky map
vec3 skyReflection(Atmos a, vec3 dir)
{
	vec3 d = normalize(vec3(dir.x, max(dir.y, 0.02), dir.z));
	return texture(skymap, skymapUv(d)).rgb;
}

/*
	Traces the reflection of `view` along `r` (view space). rgb = colour
	found (no fog), a = confidence (0 = use the sky); also returns the distance.
*/
vec4 traceReflection(vec3 view, vec3 r, float jitter, out float hitDist)
{
	hitDist = 0.0;
#if REFLECTION_QUALITY == REFLECTION_QUALITY_SKY_ONLY
	return vec4(0.0);
#else
	float dist = length(view);
	float stepLen = 0.15 + dist * 0.02;
	vec3 p = view + r * stepLen * jitter;
	vec3 prev = view;
	for (int i = 0; i < SSR_STEPS; i++) {
		prev = p;
		p += r * stepLen;
		stepLen *= 1.18;
		if (p.z < prisma.nearPlane)
			return vec4(0.0);
		vec2 uv = viewToUv(p);
		if (!onScreenUv(uv))
			return vec4(0.0);
		float d = texture(depthTex, uv).r;
		if (isSky(d))
			continue;
		float sceneZ = viewPosition(uv, d).z;
		float diff = p.z - sceneZ;
		if (diff > 0.0 && diff < stepLen * 1.5 + 0.3) {
			// Halve the last step to find the surface
			vec3 lo = prev, hi = p;
			for (int k = 0; k < SSR_REFINE; k++) {
				vec3 mid = (lo + hi) * 0.5;
				vec2 muv = viewToUv(mid);
				float md = texture(depthTex, muv).r;
				if (!isSky(md) && mid.z > viewPosition(muv, md).z)
					hi = mid;
				else
					lo = mid;
			}
			vec2 huv = viewToUv(hi);
			// Fade at the screen edges and for rays coming back at the camera
			vec2 edge = smoothstep(0.0, 0.08, huv) * smoothstep(1.0, 0.92, huv);
			float conf = edge.x * edge.y * smoothstep(-0.1, 0.2, r.z + 0.25);
			// Water reflecting water: unreliable
			if (waterSurface(huv))
				conf *= 0.5;
			hitDist = length(hi - view);
			return vec4(toLinear(texture(colorTex, huv).rgb), conf);
		}
	}
	return vec4(0.0);
#endif
}

// The haze between a reflecting surface and what it reflects
vec3 hazeOnReflection(Atmos a, vec3 color, vec3 world, vec3 dirWorld, float dist)
{
	FogParams f = fogParams(a);
	float od = fogDepth(f, world, dirWorld, dist);
	float T = exp(-od);
	vec3 S = a.directLight * PI * hazePhase(dot(dirWorld, a.lightDir)) * 0.6 + a.ambient * 0.85;
	return color * T + S * (1.0 - T);
}

#endif
