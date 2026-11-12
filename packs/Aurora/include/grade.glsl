// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	The image (90_final.frag): ACES tone mapping (Hill's fit) per channel,
	so colours stay saturated; vibrance, a soft S-curve and a warm/cool
	split ("Vividness"); contrast, saturation, vignette, grain, bars.
*/
#ifndef AURORA_GRADE
#define AURORA_GRADE

#include "common.glsl"

vec3 rrtOdtFit(vec3 v)
{
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return a / b;
}

// Linear scene -> linear display (0..1)
vec3 acesTone(vec3 c)
{
	// sRGB -> ACES AP1-ish and back (Hill's matrices, by column)
	const mat3 inputMat = mat3(
		0.59719, 0.07600, 0.02840,
		0.35458, 0.90834, 0.13383,
		0.04823, 0.01566, 0.83777);
	const mat3 outputMat = mat3(
		1.60475, -0.10208, -0.00327,
		-0.53108, 1.10813, -0.07276,
		-0.07367, -0.00605, 1.07602);
	c = inputMat * max(c, vec3(0.0));
	c = rrtOdtFit(c);
	return clamp(outputMat * c, 0.0, 1.0);
}

// More saturation where there is little
vec3 vibrance(vec3 c, float amount)
{
	float chroma = maxOf(c) - min(c.r, min(c.g, c.b));
	float l = luminance(c);
	return mix(vec3(l), c, 1.0 + amount * (1.0 - smoothstep(0.0, 0.6, chroma)));
}

// The vivid look, on display values (sRGB 0..1)
vec3 vividLook(vec3 c, float amount)
{
	c = vibrance(c, 0.45 * amount);
	// Soft S-curve around the middle
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.35 * amount);
	// Warm highlights, cool shadows
	float l = luminance(c);
	c *= mix(vec3(1.0), mix(vec3(0.975, 1.0, 1.04), vec3(1.03, 1.0, 0.965), smoothstep(0.15, 0.85, l)), amount);
	return c;
}

vec3 grade(vec3 linear)
{
	vec3 c = toSrgb(acesTone(linear));
	c = vividLook(c, options.vividness);
	c = (c - 0.45) * options.contrast + 0.45;
	float l = luminance(c);
	c = mix(vec3(l), c, options.saturation);
	return clamp(c, 0.0, 1.0);
}

float vignette(vec2 uv, float amount)
{
	vec2 d = (uv - 0.5) * vec2(prisma.viewSize.x / prisma.viewSize.y, 1.0);
	float r = dot(d, d);
	return mix(1.0, smoothstep(1.2, 0.15, r), amount);
}

vec3 filmGrain(vec3 c, vec2 pixel, float amount)
{
	if (amount <= 0.0)
		return c;
	float t = float(prisma.frameCounter % 1024);
	float n = hash12(pixel + t * vec2(17.3, 41.1)) + hash12(pixel * 1.31 + t * vec2(-7.1, 13.7)) - 1.0;
	float l = luminance(c);
	float k = amount * 0.06 * (1.0 - smoothstep(0.2, 0.9, l)) * smoothstep(0.0, 0.08, l + 0.02);
	return c + n * k;
}

#endif
