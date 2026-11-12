// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Fog and light shafts (fog.glsl) at half resolution, jittered and averaged
	with reprojected history (rejected where the distance differs). rgb =
	added light, a = distance and transmittance (packed).
*/
#prisma target fog
#include "fog.glsl"

void main()
{
	float depth = texture(depthTex, texcoord).r;
	bool sky = isSky(depth);
	vec3 dir = eyeDirection(texcoord);
	float dist = sky ? SKY_FOG_DIST : length(viewPosition(texcoord, depth));
	Atmos a = atmosState();
	bool inWater = underwater();
	if (inWater) {
		dist = min(dist, 200.0);
		sky = false;
	}
	float fogDist = dist;
	// Atmosphere off, or a hidden sky without a shadow map: no march, only
	// the fade of land past Luanti's fog (and lamp haze underground)
	bool hidden = prisma.skyHidden;
	if (!inWater && (!options.atmosphere || (hidden && !prisma.shadowAvailable))) {
		float clarity = sky ? 1.0 : prismaLuantiFogClarity(dist);
		vec3 behind = clarity < 0.999 ? background(a, dir) * (1.0 - clarity) : vec3(0.0);
		if (prisma.skyHidden && !sky)
			behind += lampHaze(texcoord, dist);
		fragColor = vec4(behind, packFog(fogDist, clarity));
		return;
	}
	float jitter = ignAnim(gl_FragCoord.xy);
	vec4 now;
	if (inWater)
		now = underwaterAlong(a, dir, dist, jitter);
	else if (sky)
		// Below the horizon: the horizon row's haze
		now = fogAlong(a, farDirection(dir), SKY_FOG_DIST, true, jitter);
	else {
		now = fogAlong(a, dir, dist, false, jitter);
		// Land fading out of Luanti's fog fades into the background haze
		float clarity = prismaLuantiFogClarity(dist);
		if (clarity < 0.999)
			now = mix(hidden ? vec4(background(a, dir), 0.0) : fogAlong(a, farDirection(dir), SKY_FOG_DIST, true, jitter),
				now, clarity);
		if (hidden)
			now.rgb += lampHaze(texcoord, dist);
	}

	vec3 before = sky ? prismaOnPreviousScreen(dir) : prismaPreviousScreenPosition(dir * dist);
	if (before.z > 0.0 && onScreenUv(before.xy)) {
		vec4 history = texelFetch(fog, ivec2(before.xy * targetSize), 0);
		vec2 h = unpackFog(history.a);
		float moved = length(dir * dist + prisma.cameraPosition - prisma.prevCameraPosition);
		float expected = sky ? SKY_FOG_DIST : (inWater ? min(moved, 200.0) : moved);
		if (history.a > 0.0 && abs(h.x - expected) < 0.05 * expected + 0.3) {
			vec4 past = vec4(clampHistory(vec4(history.rgb, 1.0), vec4(now.rgb, 1.0)).rgb, h.y);
			now = mix(now, past, HISTORY_KEEP);
		}
	}
	fragColor = vec4(now.rgb, packFog(fogDist, now.a));
}
