// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Coloured light: the scene's light sources (bright, self-lit pixels,
	weighted by saturation) at quarter resolution; its mipmaps spread it.
	rgb = light, a = brightness times distance, so blurred levels still say
	how far the light is (glowAt() in common.glsl).
*/
#prisma target glow
#include "atmosphere.glsl"

vec3 emission(vec2 uv, float daylight, out float dist)
{
	float depth = texture(depthTex, uv).r;
	dist = 0.0;
	if (isSky(depth))
		return vec3(0.0);
	dist = length(viewPosition(uv, depth));
	vec3 c = texture(colorTex, uv).rgb;
	float m = maxOf(c);
	float bright = smoothstep(0.45, 0.95, m);
	float own = smoothstep(0.55, 0.95, gbufferBlockLight(uv));
	float sun = gbufferSunlight(uv) * daylight;
	float saturation = (m - min(c.r, min(c.g, c.b))) / max(m, 1e-3);
	float lava = glowingLiquid(uv) ? 1.0 : 0.0;
	float k = max(bright * own * (1.0 - sun), lava * 0.8);
	return toLinear(c) * k * (0.6 + 1.6 * saturation);
}

void main()
{
	Atmos a = atmosState();
	vec2 px = prisma.texelSize;
	vec3 sum = vec3(0.0);
	float far = 0.0;
	for (int x = 0; x < 4; x++)
		for (int y = 0; y < 4; y++) {
			float dist;
			vec3 e = emission(texcoord + (vec2(float(x), float(y)) - 1.5) * px, a.day, dist);
			sum += e;
			far += luminance(e) * dist;
		}
	fragColor = vec4(sum / 16.0, far / 16.0);
}
