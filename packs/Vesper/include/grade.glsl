// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	The film look (90_final.frag): AgX tone mapping (Sobotka; bwrensch's
	fit); the sepia look in AgX space, mostly on mid-tones and highlights so
	nights stay blue; contrast, faded blacks, saturation; vignette, colour
	fringe, film grain and cinema bars.
*/
#ifndef VESPER_GRADE
#define VESPER_GRADE

#include "common.glsl"

vec3 agxContrast(vec3 x)
{
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

// Linear scene -> AgX display space (0..1, gamma-encoded)
vec3 agxTone(vec3 val)
{
	const mat3 agxMat = mat3(
		0.842479062253094, 0.0423282422610123, 0.0423756549057051,
		0.0784335999999992, 0.878468636469772, 0.0784336,
		0.0792237451477643, 0.0791661274605434, 0.879142973793104);
	const float minEv = -12.47393;
	const float maxEv = 4.026069;
	val = agxMat * max(val, vec3(1e-10));
	val = clamp(log2(val), minEv, maxEv);
	val = (val - minEv) / (maxEv - minEv);
	return agxContrast(val);
}

// AgX display space -> display (gamma-encoded sRGB-ish)
vec3 agxDisplay(vec3 val)
{
	const mat3 agxMatInv = mat3(
		1.19687900512017, -0.0528968517574562, -0.0529716355144438,
		-0.0980208811401368, 1.15190312990417, -0.0980434501171241,
		-0.0990297440797205, -0.0989611768448433, 1.15107367264116);
	return agxMatInv * val;
}

// The sepia look on AgX values; `nightBlue` keeps more of the shadows' hue
vec3 sepiaLook(vec3 val, float amount)
{
	float luma = dot(val, vec3(0.2126, 0.7152, 0.0722));
	// Shadows keep their hue; mid-tones and highlights take the tone
	float w = amount * smoothstep(0.04, 0.38, luma);
	vec3 slope = mix(vec3(1.0), vec3(1.02, 0.93, 0.70), w);
	vec3 power = mix(vec3(1.0), vec3(0.92, 0.96, 1.06), w);
	val = pow(max(val * slope, vec3(0.0)), power);
	float l2 = dot(val, vec3(0.2126, 0.7152, 0.0722));
	return l2 + mix(1.0, 0.6, w) * (val - l2);
}

vec3 grade(vec3 linear)
{
	vec3 c = agxTone(linear);
	c = sepiaLook(c, options.sepia);
	// Contrast around mid-grey (in display space), then saturation
	c = (c - 0.42) * options.contrast + 0.42;
	c = agxDisplay(max(c, vec3(0.0)));
	float l = luminance(c);
	c = mix(vec3(l), c, options.saturation);
	// Faded blacks, a touch warm
	c = c * (1.0 - options.black_lift) + options.black_lift * vec3(1.0, 0.94, 0.86);
	return clamp(c, 0.0, 1.0);
}

float vignette(vec2 uv, float amount)
{
	vec2 d = (uv - 0.5) * vec2(prisma.viewSize.x / prisma.viewSize.y, 1.0);
	float r = dot(d, d);
	return mix(1.0, smoothstep(1.1, 0.1, r), amount);
}

vec3 filmGrain(vec3 c, vec2 pixel, float amount)
{
	if (amount <= 0.0)
		return c;
	float t = float(prisma.frameCounter % 1024);
	float n = hash12(pixel + t * vec2(17.3, 41.1)) + hash12(pixel * 1.31 + t * vec2(-7.1, 13.7)) - 1.0;
	float l = luminance(c);
	// Strongest in the mid-tones and shadows, like film
	float k = amount * 0.07 * (1.0 - smoothstep(0.2, 0.9, l)) * smoothstep(0.0, 0.08, l + 0.02);
	return c + n * k;
}

#endif
