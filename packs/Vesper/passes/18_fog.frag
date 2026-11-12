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
	float fogDist = inWater ? dist : fogDistance(dist, sky);
	vec4 now = inWater ? underwaterAlong(a, dir, fogDist, ignAnim(gl_FragCoord.xy))
		: fogAlong(a, dir, fogDist, sky, texcoord, ignAnim(gl_FragCoord.xy));

#if FOG_QUALITY != FOG_QUALITY_OFF
	vec3 before = sky ? prismaOnPreviousScreen(dir) : prismaPreviousScreenPosition(dir * dist);
	if (before.z > 0.0 && onScreenUv(before.xy)) {
		vec4 history = texelFetch(fog, ivec2(before.xy * targetSize), 0);
		vec2 h = unpackFog(history.a);
		float moved = length(dir * dist + prisma.cameraPosition - prisma.prevCameraPosition);
		float expected = sky ? SKY_FOG_DIST : (inWater ? min(moved, 200.0) : fogDistance(moved, false));
		if (history.a > 0.0 && abs(h.x - expected) < 0.05 * expected + 0.3) {
	#if FOG_QUALITY == FOG_QUALITY_ULTRA
			float keep = 0.9;
	#else
			float keep = 0.85;
	#endif
			vec4 past = vec4(clampHistory(vec4(history.rgb, 1.0), vec4(now.rgb, 1.0)).rgb, h.y);
			now = mix(now, past, keep * historyTrust(a.w));
		}
	}
#endif
	fragColor = vec4(now.rgb, packFog(fogDist, now.a));
}
