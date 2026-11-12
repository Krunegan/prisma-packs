// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Volumetric cumulus: a drifting 2D coverage map sets where clouds are and
	how tall; flat bottoms, round tops, 3D noise billows. Light: Beer's law
	with multiple-scattering octaves, a two-lobed phase (silver lining) and
	a powder term. cloudShadow() reads the same map, so ground shadows and
	shaft gaps match the sky.
*/
#ifndef AURORA_CLOUDS
#define AURORA_CLOUDS

#include "atmosphere.glsl"

const float CLOUD_FAR = 14000.0;

struct CloudLayer {
	float bottom;
	float top;
	float thickness;
	float cover;
	float scale;
	vec2 wind;        // offset of the coverage map (nodes)
	vec3 drift;       // offset of the 3D detail
	float sigma;      // extinction per node at full density
};

CloudLayer cloudLayer()
{
	CloudLayer c;
	c.bottom = options.cloud_height;
	c.thickness = options.cloud_thickness;
	c.top = c.bottom + c.thickness;
	c.cover = options.cloud_cover;
	c.scale = options.cloud_size;
	float t = prisma.frameTimeCounter;
	float speed = options.cloud_speed;
	c.wind = WIND_DIR * t * speed;
	c.drift = vec3(WIND_DIR.x, 0.0, WIND_DIR.y) * t * speed * 1.25 + vec3(0.0, -t * 0.3, 0.0);
	c.sigma = 0.08;
	return c;
}

// Cloud cover (0..1) at `xz`; fewer `octaves` for shadows
float cloudMap(CloudLayer c, vec2 xz, int octaves)
{
	vec2 p = (xz + c.wind) / (1150.0 * c.scale);
	float big = fbm2(p, 3);
	float mid = fbm2(p * 4.1 + 11.0, octaves);
	float n = big * 0.58 + mid * 0.42;
	float threshold = mix(0.70, 0.28, c.cover);
	return smoothstep(threshold, threshold + 0.16, n);
}

// Density (0..1) at world position `p`
float cloudDensity(CloudLayer c, vec3 p, int detail)
{
	float h = (p.y - c.bottom) / c.thickness;
	if (h <= 0.0 || h >= 1.0)
		return 0.0;
	float m = cloudMap(c, p.xz, detail > 1 ? 2 : 1);
	if (m <= 0.001)
		return 0.0;
	// Taller where cover is higher; flat bottoms, round tops
	float top = mix(0.3, 1.0, m);
	float profile = smoothstep(0.0, 0.05, h) * (1.0 - smoothstep(top * 0.4, top, h));
	float d = m * profile;
	if (d <= 0.001)
		return 0.0;
	// Billows: round on top, wispy at the base
	vec3 q = (p + c.drift) / (75.0 * c.scale);
	float n = fbm3(q, detail);
	float billow = 1.0 - abs(n * 2.0 - 1.0);
	float erosion = mix(n, billow, 0.5) * mix(0.75, 0.55, h);
	d = saturate((d - erosion) / max(1.0 - erosion, 0.05));
	return d * smoothstep(0.0, 0.12, d + 0.04);
}

// Where a ray from `origin` enters and leaves the layer
vec2 cloudSpan(CloudLayer c, vec3 origin, vec3 dir)
{
	float y = origin.y;
	if (abs(dir.y) < 1e-4)
		return (y > c.bottom && y < c.top) ? vec2(0.0, CLOUD_FAR) : vec2(-1.0);
	float tb = (c.bottom - y) / dir.y;
	float tt = (c.top - y) / dir.y;
	float t0 = max(min(tb, tt), 0.0);
	float t1 = min(max(tb, tt), CLOUD_FAR);
	return t1 > t0 ? vec2(t0, t1) : vec2(-1.0);
}

// Optical depth from `p` towards the light
float cloudLightDepth(CloudLayer c, vec3 p, vec3 L, float jitter)
{
	float od = 0.0;
	float stepLen = c.thickness * 0.06;
	float t = stepLen * (0.5 + 0.5 * jitter);
	for (int i = 0; i < CLOUD_LIGHT_STEPS; i++) {
		vec3 q = p + L * t;
		od += cloudDensity(c, q, CLOUD_DETAIL > 2 ? 2 : 1) * stepLen;
		stepLen *= 1.7;
		t += stepLen;
	}
	return od * c.sigma;
}

// Phase with a strong silver lining and a soft back-scatter
float cloudPhase(float cosT)
{
	return mix(hgPhase(cosT, -0.2), hgPhase(cosT, 0.85), 0.6) + hgPhase(cosT, 0.3) * 0.5;
}

/*
	Marches the clouds along `dir`: rgb = light (linear), a = coverage.
	`steps` and `detail` allow a cheaper march (sky map).
*/
vec4 marchClouds(Atmos a, vec3 dir, float jitter, int steps, int detail)
{
	CloudLayer c = cloudLayer();
	vec3 origin = prisma.cameraPosition;
	vec2 span = cloudSpan(c, origin, dir);
	if (span.x < 0.0)
		return vec4(0.0);

	bool moon = a.night > 0.5 && a.moonDir.y > 0.0;
	vec3 L = moon ? a.moonDir : a.sunDir;
	// Sun lights them white; the moon only faintly
	vec3 lightCol = moon ? a.moonLight * PI * 0.9 : a.sunTop * mix(1.0, 0.6, a.overcast) * PI * 2.6;
	float cosT = dot(dir, L);
	float phase = cloudPhase(cosT);
	// Sky light: blue-white tops, bases lit by the land
	vec3 ambTop = mix(a.zenith, a.horizon, 0.5) * 3.0;
	vec3 ambBottom = a.horizon * 0.55 + a.sunLight * 0.06;

	float len = span.y - span.x;
	float stepLen = len / float(steps);
	float t = span.x + stepLen * jitter;
	float T = 1.0;
	vec3 light = vec3(0.0);
	for (int i = 0; i < steps; i++) {
		if (T < 0.01)
			break;
		vec3 p = origin + dir * t;
		float d = cloudDensity(c, p, detail);
		if (d > 0.002) {
			float sigma = d * c.sigma;
			float h = saturate((p.y - c.bottom) / c.thickness);
			float od = cloudLightDepth(c, p, L, jitter);
			// Multiple scattering: each octave deeper, dimmer, rounder
			float ms = 0.0;
			float aw = 1.0, bw = 1.0;
			for (int o = 0; o < 3; o++) {
				ms += aw * exp(-od * bw) * mix(1.0 / (4.0 * PI), phase, pow(0.5, float(o)));
				aw *= 0.55;
				bw *= 0.35;
			}
			// Powder: darker crevices on the sunlit side
			float powder = 1.0 - exp(-sigma * 35.0) * 0.55;
			powder = mix(1.0, powder, saturate(1.0 - abs(cosT)) * 0.8 + 0.2);
			vec3 S = lightCol * ms * powder + mix(ambBottom, ambTop, h * h) * (0.3 + 0.7 * h);
			float stepT = exp(-sigma * stepLen);
			light += T * S * (1.0 - stepT);
			T *= stepT;
		}
		t += stepLen;
	}
	float alpha = 1.0 - T;
	// Far clouds melt into the horizon haze
	float fade = 1.0 - smoothstep(CLOUD_FAR * 0.3, CLOUD_FAR, span.x);
	// They fade out and the sky behind shows through
	float keep = 1.0 - smoothstep(600.0, 9000.0, span.x) * 0.6;
	return vec4(light, alpha) * keep * fade;
}

// Light from `L` that reaches `world` through the clouds (1 = clear):
// the coverage map where the ray crosses mid-layer
float cloudShadow(vec3 world, vec3 L, int octaves)
{
	if (!options.clouds || prisma.skyHidden || options.cloud_shadows <= 0.0 || L.y <= 0.02)
		return 1.0;
	CloudLayer c = cloudLayer();
	float mid = c.bottom + c.thickness * 0.3;
	if (world.y > mid)
		return 1.0;
	vec3 p = world + L * ((mid - world.y) / L.y);
	float m = cloudMap(c, p.xz, octaves);
	float shade = 1.0 - exp(-m * c.thickness * c.sigma * 0.12);
	return 1.0 - shade * options.cloud_shadows;
}

#endif
