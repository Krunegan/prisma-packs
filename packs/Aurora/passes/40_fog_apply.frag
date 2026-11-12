// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Lays 18_fog.frag over the scene, upsampled with the depth so edges stay
	sharp. Underwater: blue-green water that loses red with distance. Above
	water, the rainbow is added over the fog.
*/
#include "fog.glsl"
#include "rainbow.glsl"

vec4 fogAt(vec2 uv, float fogDist)
{
	vec2 size = vec2(textureSize(fog, 0));
	vec2 p = uv * size - 0.5;
	vec2 f = fract(p);
	ivec2 i = ivec2(floor(p));
	ivec2 hi = ivec2(size) - 1;
	vec4 sum = vec4(0.0);
	float weight = 0.0;
	vec4 closest = vec4(0.0, 0.0, 0.0, 1.0);
	float best = 1e9;
	// Potato: only the 2 x 2 texels around the pixel
	const int lo = FOG_UPSAMPLE > 0 ? -1 : 0;
	const int hi2 = FOG_UPSAMPLE > 0 ? 2 : 1;
	for (int y = lo; y <= hi2; y++)
		for (int x = lo; x <= hi2; x++) {
			vec4 s = texelFetch(fog, clamp(i + ivec2(x, y), ivec2(0), hi), 0);
			vec2 dt = unpackFog(s.a);
			float diff = abs(dt.x - fogDist);
			vec2 off = vec2(float(x), float(y)) - f;
			float w = exp(-dot(off, off) * 1.2) * exp(-diff / (0.03 * fogDist + 0.25));
			sum += vec4(s.rgb, dt.y) * w;
			weight += w;
			if (diff < best) {
				best = diff;
				closest = vec4(s.rgb, dt.y);
			}
		}
	return weight > 1e-3 ? sum / weight : closest;
}

// Underwater: red is lost first, then underwaterAlong()'s light is added
vec3 underwaterFog(vec3 lin, vec4 f, float dist)
{
	vec3 extinction = options.underwater_fog * (vec3(1.6, 1.0, 1.0) - waterTint());
	return lin * exp(-extinction * dist) + f.rgb;
}

void main()
{
	vec3 color = texture(colorTex, texcoord).rgb;
	float depth = texture(depthTex, texcoord).r;
	bool sky = isSky(depth);
	float dist = sky ? SKY_FOG_DIST : length(viewPosition(texcoord, depth));
	vec3 lin = toLinear(color);
	if (underwater()) {
		float d = min(dist, 200.0);
		lin = underwaterFog(lin, fogAt(texcoord, d), d);
	} else {
		vec4 f = fogAt(texcoord, dist);
		lin = lin * f.a + f.rgb;
		vec4 bow = rainbow(atmosState(), eyeDirection(texcoord), dist);
		// Faint against bright clouds
		float cloud = sky ? max(texture(clouds, texcoord).a, 0.0) : 0.0;
		bow = mix(bow, vec4(0.0, 0.0, 0.0, 1.0), cloud * 0.8);
		lin = lin * bow.a + bow.rgb;
	}
	fragColor = vec4(toSrgb(lin), 1.0);
}
