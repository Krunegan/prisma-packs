// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Sky pixels: the pack's sky with 10_clouds.frag upsampled on top, plus what
	Luanti drew over the sky (skyOverlay()). World pixels: lightWorld().
	From under water, the surface above shows the sky bent by the waves.
*/
#include "light.glsl"
#include "water.glsl"

vec3 surfaceFromBelow(Atmos a, vec2 uv, float depth)
{
	vec3 view = viewPosition(uv, depth);
	vec3 player = (prisma.viewMatrixInverse * vec4(view, 1.0)).xyz;
	float dist = length(player);
	vec3 v = player / max(dist, 1e-4);
	vec3 n = waterNormal(a, player + prisma.cameraPosition, dist);
	// The sky we look at, bent by the waves
	vec3 t = normalize(vec3(v.x, max(v.y, 0.05), v.z) - (n - vec3(0.0, 1.0, 0.0)) * 0.6);
	// With the haze seen from above
	vec3 sky = hazeOnReflection(a, skyReflection(a, t), player + prisma.cameraPosition, t,
		SKY_FOG_DIST * options.sky_haze * 0.3);
	sky += normalizeLum(a.sunLight + vec3(1e-5)) * pow(max(dot(t, a.sunDir), 0.0), 400.0) * 12.0 * a.sunUp;
	// Solid things above the water show against that sky, shaded and washed out
	if (dot(gbufferNormal(uv), gbufferNormal(uv)) > 0.04) {
		vec3 above = toLinear(texture(colorTex, uv).rgb);
		above = mix(vec3(dot(above, vec3(0.2126, 0.7152, 0.0722))), above, 0.45);
		sky = mix(sky * 0.25, above * 0.6, 0.4);
	}
	// At grazing angles the surface mirrors the depths
	vec3 deep = a.ambient * waterTint() * 0.15;
	float grazing = 1.0 - saturate(v.y * 2.5);
	return mix(sky * 0.85, deep, grazing * grazing * 0.55);
}

// Clouds at `uv`, from the half-resolution texels that saw sky
vec4 cloudsAt(vec2 uv)
{
	vec2 size = vec2(textureSize(clouds, 0));
	vec2 p = uv * size - 0.5;
	vec2 f = fract(p);
	ivec2 i = ivec2(floor(p));
	ivec2 hi = ivec2(size) - 1;
	vec4 sum = vec4(0.0);
	float weight = 0.0;
	for (int y = 0; y <= 1; y++)
		for (int x = 0; x <= 1; x++) {
			vec4 c = texelFetch(clouds, clamp(i + ivec2(x, y), ivec2(0), hi), 0);
			float w = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
			if (c.a >= 0.0) {
				sum += c * w;
				weight += w;
			}
		}
	return weight > 1e-4 ? sum / weight : vec4(0.0);
}

void main()
{
	vec3 color = texture(colorTex, texcoord).rgb;
	float depth = texture(depthTex, texcoord).r;
	Atmos a = atmosState();
	vec3 lin;
	if (isSky(depth)) {
		if (underwater()) {
			fragColor = vec4(color, 1.0);
			return;
		}
		vec3 dir = eyeDirection(texcoord);
		vec4 c = cloudsAt(texcoord);
		lin = skyColor(a, dir) * (1.0 - c.a) + c.rgb;
		lin += toLinear(max(skyOverlay(texcoord), vec3(0.0)));
	} else if (underwater() && waterSurface(texcoord) && eyeDirection(texcoord).y > 0.0) {
		lin = surfaceFromBelow(a, texcoord, depth);
	} else {
		lin = lightWorld(color, texcoord, depth, a);
	}
	fragColor = vec4(toSrgb(lin), 1.0);
}
