// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Eye adaptation into state column 1: a centre-weighted log-average of
	bloom3, followed slowly (faster towards bright), only part of the way.
*/
#prisma target state
#include "atmosphere.glsl"

float targetExposure(Atmos a)
{
	float sum = 0.0;
	float weight = 0.0;
	for (int y = 0; y < 9; y++)
		for (int x = 0; x < 16; x++) {
			vec2 uv = (vec2(float(x), float(y)) + 0.5) / vec2(16.0, 9.0);
			vec2 d = (uv - 0.5) * 2.0;
			float w = exp(-dot(d, d) * 1.5);
			float l = luminance(texture(bloom3, uv).rgb);
			sum += log2(l + 1e-4) * w;
			weight += w;
		}
	float average = exp2(sum / weight);
	float ev = log2(0.13 / max(average, 1e-4)) * 0.55;
	return clamp(ev, -1.5, mix(1.6, 1.0, a.night));
}

void main()
{
	ivec2 texel = ivec2(gl_FragCoord.xy);
	vec4 kept = texelFetch(state, texel, 0);
	if (texel != ivec2(1, 0)) {
		fragColor = kept;
		return;
	}
	Atmos a = atmosState();
	float target = targetExposure(a);
	if (kept.a <= 0.0) {
		fragColor = vec4(target, 0.0, 0.0, 1.0);
		return;
	}
	float dt = clamp(prisma.frameTime, 0.0, 0.25);
	float speed = target < kept.r ? 1.8 : 0.5;
	fragColor = vec4(mix(kept.r, target, 1.0 - exp(-dt * speed)), 0.0, 0.0, 1.0);
}
