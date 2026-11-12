// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Rainbow (0 = off, the default): a ring 42 degrees around the anti-solar
	point, red outside; a fainter reversed bow at 51 degrees; brighter inside,
	darker between (Alexander's band). Shown while the sun is low and not
	behind a cloud, in stretches that come and go, far away only.
*/
#ifndef AURORA_RAINBOW
#define AURORA_RAINBOW

#include "clouds.glsl"

// The colours across a bow, from 0 (violet, inside) to 1 (red, outside)
vec3 rainbowSpectrum(float x)
{
	vec3 d = (vec3(x) - vec3(0.80, 0.50, 0.20)) / vec3(0.17, 0.17, 0.16);
	vec3 c = exp(-d * d);
	// Violet: blue with a little red
	float v = (x - 0.04) / 0.08;
	c.r += 0.3 * exp(-v * v);
	return c;
}

/*
	The rainbow along `dir` at `dist`: add rgb, multiply what is behind by a.
*/
vec4 rainbow(Atmos a, vec3 dir, float dist)
{
	float strength = options.rainbows * a.sunUp * (1.0 - a.overcast) * smoothstep(40.0, 160.0, dist);
	if (strength < 0.005)
		return vec4(0.0, 0.0, 0.0, 1.0);
	// The sun hidden by a cloud: no bow
	strength *= cloudShadow(prisma.cameraPosition, a.sunDir, 1);

	vec3 anti = -a.sunDir;
	float deg = degrees(acos(clamp(dot(dir, anti), -1.0, 1.0)));
	// Primary 40.4-42.6 degrees, secondary 50.2-53.8 (reversed), softened by the sun's size
	vec3 bows = rainbowSpectrum((deg - 40.4) / 2.2) + rainbowSpectrum((53.8 - deg) / 3.6) * 0.38;
	float inside = smoothstep(18.0, 40.6, deg) * (1.0 - smoothstep(40.6, 41.4, deg));
	float alexander = smoothstep(41.8, 43.0, deg) * (1.0 - smoothstep(49.6, 50.6, deg));

	// Stronger and weaker stretches along the arc
	vec3 up = abs(anti.y) > 0.999 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, anti));
	vec3 top = cross(anti, right);
	vec2 around = normalize(vec2(dot(dir, right), dot(dir, top)) + vec2(1e-5));
	float t = prisma.frameTimeCounter;
	float showers = smoothstep(0.2, 0.7, vnoise2(around * 1.3 + vec2(t * 0.004, 5.0 - t * 0.003)));
	strength *= mix(0.55, 1.0, showers);

	vec3 sun = normalizeLum(a.sunLight + vec3(1e-5)) * min(luminance(a.sunLight), 1.2);
	vec3 add = sun * (bows * 0.26 + inside * 0.045) * strength;
	return vec4(add, 1.0 - alexander * 0.2 * strength);
}

#endif
