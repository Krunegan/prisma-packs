// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	state buffer (6 x 2), kept between frames:
	  column 0: weather, eased (r rain, g wetness, b overcast, a started);
	  column 1: row 0 exposure (55_exposure.frag), row 1 camera underwater;
	  columns 2-5: sound controls (pack.toml [sounds.*]): row 0 volume,
	  pitch, trigger, pan; row 1 muffle. 2 rain, 3 wind (loops); 4 near and
	  5 far thunder, delayed by distance (343 m/s) and panned.
*/
#prisma target state
#include "weather.glsl"

vec4 updateWeather()
{
	vec4 previous = texelFetch(state, ivec2(0, 0), 0);
	vec2 target = targetWeather();
	if (previous.a <= 0.0)
		return vec4(target.y, target.y > 0.0 ? 1.0 : 0.0, target.x, 1.0); // first frame: as the options say
	float dt = clamp(prisma.frameTime, 0.0, 0.25);
	float rain = previous.r + clamp(target.y - previous.r, -dt / 15.0, dt / 15.0);
	float overcast = previous.b + clamp(target.x - previous.b, -dt / 50.0, dt / 50.0);
	// It doesn't rain under a clear sky
	rain = min(rain, overcast * 1.6);
	float wet = previous.g;
	if (rain > 0.05)
		wet = min(1.0, wet + dt * (0.008 + 0.03 * rain));
	else
		wet = max(0.0, wet - dt / 150.0);
	return vec4(rain, wet, overcast, 1.0);
}

// How open the sky around the camera is (0 = deep under cover)
float openness()
{
	const vec2 around[8] = vec2[](vec2(3.0, 0.0), vec2(0.0, 3.0), vec2(-3.0, 0.0), vec2(0.0, -3.0),
		vec2(6.0, 6.0), vec2(-6.0, 6.0), vec2(-6.0, -6.0), vec2(6.0, -6.0));
	float open = overheadExposure(vec3(0.0, 1.0, 0.0), 1.0) * 2.0;
	for (int i = 0; i < 8; i++)
		open += overheadExposure(vec3(around[i].x, 1.0, around[i].y), 1.0);
	return prisma.overheadAvailable ? open / 10.0 : 1.0;
}

float panOf(vec3 dir)
{
	vec3 right = vec3(prisma.viewMatrix[0][0], prisma.viewMatrix[1][0], prisma.viewMatrix[2][0]);
	vec2 d = normalize(dir.xz + vec2(1e-5));
	vec2 r = normalize(right.xz + vec2(1e-5));
	return clamp(dot(d, r), -1.0, 1.0) * 0.8;
}

// The latest strike whose thunder arrived, near (< 800 nodes) or far: slot + 1, or 0
float lastThunder(float storm, bool near, out float slotOut)
{
	float t = prisma.frameTimeCounter;
	float now = floor(t / LIGHTNING_SLOT);
	for (float s = now; s >= now - 2.0; s -= 1.0) {
		if (!lightningIn(s, storm))
			continue;
		float dist = lightningDistance(s);
		if ((dist < 800.0) != near)
			continue;
		if (t >= lightningStart(s) + dist / 343.0) {
			slotOut = s;
			return s + 1.0;
		}
	}
	slotOut = -1.0;
	return 0.0;
}

/*
	Under the water surface? In a liquid node: a surface seen around the
	camera decides; otherwise below a source's surface height is under, and
	above it only if the last surface seen is above the eyes. r = under,
	g = last surface height, b = a surface was seen.
*/
const float SOURCE_SURFACE = 0.375; // above the centre of the node

vec4 cameraSubmerged()
{
	vec4 previous = texelFetch(state, ivec2(1, 1), 0);
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
		if (seen && best < 2.5)
			under = level > y ? 1.0 : 0.0;
		else {
			float inNode = y - floor(y + 0.5);
			under = (inNode < SOURCE_SURFACE - 0.005 || (known && level > y + 0.05)) ? 1.0 : 0.0;
		}
	}
	return vec4(under, level, known ? 1.0 : 0.0, 1.0);
}

void main()
{
	ivec2 texel = ivec2(gl_FragCoord.xy);
	vec4 w = updateWeather();
	if (texel.x == 0) {
		fragColor = w;
		return;
	}
	if (texel == ivec2(1, 1)) {
		fragColor = cameraSubmerged();
		return;
	}
	if (texel.x == 1) {
		fragColor = texelFetch(state, texel, 0);
		return;
	}

	float rain = w.r * options.rain_amount;
	float storm = smoothstep(0.75, 1.0, w.r);
	float master = options.sound_volume;
	bool inWater = underwater();
	float open = openness();
	float muffle = inWater ? 0.92 : (1.0 - open) * 0.75;
	float covered = inWater ? 0.45 : mix(0.35, 1.0, open);

	float volume = 0.0, pitch = 0.0, trigger = 0.0, pan = 0.0;
	if (texel.x == 2) {
		volume = smoothstep(0.0, 0.3, rain) * mix(0.55, 1.0, saturate(rain)) * covered;
	} else if (texel.x == 3) {
		float gust = storm * 0.6 + options.wind * 0.25 * smoothstep(0.0, 0.5, w.b);
		volume = gust * gust * mix(0.3, 1.0, open) * (inWater ? 0.3 : 1.0);
	} else {
		bool near = texel.x == 4;
		float slot;
		trigger = lastThunder(storm, near, slot);
		// Only forwards: an older strike never plays again
		float previous = texelFetch(state, ivec2(texel.x, 0), 0).b;
		if (trigger <= previous)
			trigger = previous;
		else {
			float dist = lightningDistance(slot);
			volume = near ? 1.0 : mix(0.9, 0.35, smoothstep(800.0, 3500.0, dist));
			volume *= inWater ? 0.6 : mix(0.6, 1.0, open);
			pitch = mix(0.9, 1.08, hash11(slot + 9.1));
			pan = panOf(lightningDirectionOf(slot));
			muffle *= near ? 0.6 : 0.8;
		}
	}
	volume *= master;
	fragColor = texel.y == 0 ? vec4(volume, pitch, trigger, pan) : vec4(muffle, 0.0, 0.0, 0.0);
}
