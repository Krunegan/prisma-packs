// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	noiseTex (common.glsl): 257 x 257, the last row and column repeat the
	first. r: lattice value; g: r at (+37, +17), the next z-slice; b: 2D noise.
*/
#prisma target noiseTex
#define AURORA_NO_NOISE_TEX 1
#include "common.glsl"

float lattice(ivec2 p, float seed)
{
	p = p & 255;
	return hash12(vec2(p) + vec2(0.37, 0.71) + seed * 157.0);
}

void main()
{
	ivec2 p = ivec2(gl_FragCoord.xy);
	float r = lattice(p, 0.0);
	float g = lattice(p + ivec2(NOISE_SLICE), 0.0);
	float b = lattice(p, 1.0);
	fragColor = vec4(r, g, b, 1.0);
}
