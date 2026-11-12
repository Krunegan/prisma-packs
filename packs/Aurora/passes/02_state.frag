// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	state buffer (2 x 1), kept between frames: (0, 0) exposure
	(55_exposure.frag), (1, 0) camera under the water surface.
*/
#prisma target state
#include "common.glsl"

/*
	Under the water surface? In a liquid node the camera floats if a water
	surface is at or just below the eyes (seen this frame, or the last one
	seen); otherwise it is under. r = under, g = last surface height,
	b = a surface was seen.
*/

vec4 cameraSubmerged()
{
	vec4 previous = texelFetch(state, ivec2(1, 0), 0);
	float best = 1e9;
	float surface = 0.0;
	for (int y = 0; y < 12; y++)
		for (int x = 0; x < 16; x++) {
			vec2 uv = (vec2(float(x), float(y)) + 0.5) / vec2(16.0, 12.0);
			if (!waterSurface(uv))
				continue;
			float d = texture(depthTex, uv).r;
			if (isSky(d))
				continue;
			vec3 p = playerPosition(uv, d);
			float h = length(p.xz);
			if (h < 4.0 && h < best) {
				best = h;
				surface = p.y + prisma.cameraPosition.y;
			}
		}
	bool seen = best < 1e8;
	bool known = seen || previous.b > 0.5;
	float level = seen ? surface : previous.g;
	float y = prisma.cameraPosition.y;
	float under = 0.0;
	if (inLiquidNode()) {
		// Floating: a surface at or just below the eyes; anything else is under
		bool atEyes = level <= y + 0.05 && level > y - 1.0;
		bool floating = seen ? (best < 2.5 && atEyes) : (known && atEyes);
		under = floating ? 0.0 : 1.0;
	}
	return vec4(under, level, known ? 1.0 : 0.0, 1.0);
}

void main()
{
	ivec2 texel = ivec2(gl_FragCoord.xy);
	fragColor = texel.x == 1 ? cameraSubmerged() : texelFetch(state, texel, 0);
}
