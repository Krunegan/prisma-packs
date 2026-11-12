// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	The upper sky with clouds in a small stereographic map, for reflections.
	Cheaper than 10_clouds.frag, averaged over frames. No sun disc: the
	water adds its glint.
*/
#prisma target skymap
#include "clouds.glsl"

void main()
{
	Atmos a = atmosState();
	vec3 dir = skymapDir(texcoord);
	vec4 c = marchClouds(a, dir, ignAnim(gl_FragCoord.xy), CLOUD_STEPS / 3 + 4, 2);
	vec3 sky = skyDome(a, dir) * (1.0 - c.a) + c.rgb;
	vec4 history = texelFetch(skymap, ivec2(gl_FragCoord.xy), 0);
	float keep = history.a > 0.0 ? 0.8 * historyTrust(a.w) : 0.0;
	fragColor = vec4(mix(sky, clampHistory(history, vec4(sky, 1.0)).rgb, keep), 1.0);
}
