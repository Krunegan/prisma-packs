// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Waves and reflections. Reflections are traced on screen (SSR); misses go
	on through the overhead map (land off screen), then farReflection() (what
	the camera sees in that direction), then the sky map. Reflections get the
	haze of the way back.
*/
#ifndef AURORA_WATER
#define AURORA_WATER

#include "fog.glsl"

// ---- Waves ---------------------------------------------------------------------------

// Moving value noise octaves: long swells with faster ripples
float waveHeight(vec2 p, float t)
{
	float h = vnoise2(p * 0.3 + WIND_DIR * t * 0.3) * 0.5;
	h += vnoise2(mat2(0.8, 0.6, -0.6, 0.8) * p * 0.85 - WIND_DIR.yx * t * 0.55) * 0.28;
	h += vnoise2(p * 2.1 + vec2(t * 0.8, -t * 0.45)) * 0.14;
	h += vnoise2(mat2(0.6, -0.8, 0.8, 0.6) * p * 4.7 + vec2(-t * 1.3, t * 0.9)) * 0.08;
	return h;
}

// World normal of the water at `world`, softened with distance
vec3 waterNormal(vec3 world, float dist)
{
	float t = prisma.frameTimeCounter;
	vec2 p = world.xz;
	float amp = options.water_waves * (1.0 - smoothstep(16.0, 120.0, dist) * 0.8);
	float e = 0.06;
	float h0 = waveHeight(p, t);
	float hx = waveHeight(p + vec2(e, 0.0), t);
	float hz = waveHeight(p + vec2(0.0, e), t);
	vec2 slope = vec2(hx - h0, hz - h0) / e * amp * 0.11;
	return normalize(vec3(-slope.x, 1.0, -slope.y));
}

/*
	The water's face at `uv`, towards the camera (depthFaceNormal()).
*/
vec3 waterFace(vec2 uv)
{
	return depthFaceNormal(uv);
}

// The surface normal: its face, with waves only on faces that look up
vec3 waterSurfaceNormal(vec2 uv, vec3 world, float dist)
{
	vec3 face = waterFace(uv);
	// Waves on faces that look up, seen from above
	float level = smoothstep(0.7, 0.95, face.y);
	return normalize(face + (waterNormal(world, dist) - vec3(0.0, 1.0, 0.0)) * level);
}

// ---- Reflections -----------------------------------------------------------------------

// Sky and clouds in direction `dir` (world), from the sky map
vec3 skyReflection(vec3 dir)
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
#if SSR_STEPS == 0
	return vec4(0.0);
#else
	float dist = length(view);
	float stepLen = 0.15 + dist * 0.02;
	vec3 p = view + r * stepLen * jitter;
	vec3 prev = view;
	for (int i = 0; i < SSR_STEPS; i++) {
		prev = p;
		p += r * stepLen;
		stepLen *= 1.22;
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
		// Only beyond the reflecting point (not a trunk between camera and water)
		if (diff > 0.0 && diff < stepLen * 1.5 + 0.3 && sceneZ > view.z + 0.5) {
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
	vec3 S = a.directLight * PI * hazePhase(dot(dirWorld, a.lightDir)) * 0.6 + a.ambient * 0.9;
	return color * T + S * (1.0 - T);
}

/*
	Land off screen along the reflected ray, marched through the overhead
	map. Returns the distance where it went under the land, or -1.
*/
float overheadReflection(vec3 player, vec3 dir, float jitter)
{
	if (!prisma.overheadAvailable || dir.y <= -0.05)
		return -1.0;
	float t = 0.4 + 0.4 * jitter;
	float stepLen = 0.5;
	float before = 0.0;
	for (int i = 0; i < WATER_LAND_STEPS; i++) {
		vec3 p = player + dir * t;
		if (max(abs(p.x), abs(p.z)) > prisma.overheadDistance)
			return -1.0;
		if (p.y < overheadHeight(p)) {
			// One halving step towards the crossing
			float mid = (before + t) * 0.5;
			vec3 q = player + dir * mid;
			return q.y < overheadHeight(q) ? mid : t;
		}
		before = t;
		t += stepLen;
		stepLen *= WATER_LAND_GROWTH;
	}
	return -1.0;
}

// Colour of off-screen land at `p`: the scene if on screen, else lit grass
vec3 landColour(Atmos a, vec3 p)
{
	vec4 clip = prisma.projectionMatrix * (prisma.viewMatrix * vec4(p, 1.0));
	if (clip.w > 0.0) {
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (onScreenUv(uv)) {
			float d = texture(depthTex, uv).r;
			float dist = length(p);
			if (!isSky(d) && abs(length(viewPosition(uv, d)) - dist) < 1.5 + 0.05 * dist)
				return toLinear(texture(colorTex, uv).rgb);
		}
	}
	vec3 albedo = vec3(0.085, 0.125, 0.055);
	return albedo * (a.ambient * 1.3 + a.directLight * hardShadow(p) * 0.5);
}

/*
	What is far along `dirWorld`, as the camera sees it (a far hill is in
	almost the same direction from the water). Off screen the edge is
	stretched, then `sky`. Only what is farther than `from` is mirrored.
*/
vec3 farReflection(Atmos a, vec3 world, vec3 dirWorld, vec3 sky, float from)
{
	vec3 s = prismaOnScreen(dirWorld);
	if (s.z <= 0.0)
		return sky;
	vec2 uv = clamp(s.xy, vec2(0.002), vec2(0.998));
	vec2 off = abs(s.xy - uv);
	float outside = max(off.x, off.y);
	if (outside > 0.15)
		return sky;
	float d = texture(depthTex, uv).r;
	if (isSky(d))
		return sky;
	float dist = length(viewPosition(uv, d));
	if (dist < from + 2.0)
		return sky;
	vec3 c = toLinear(texture(colorTex, uv).rgb);
	return mix(hazeOnReflection(a, c, world, dirWorld, dist), sky, smoothstep(0.08, 0.15, outside));
}

#endif
