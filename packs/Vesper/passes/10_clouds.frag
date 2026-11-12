// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Clouds at half resolution, jittered and averaged with reprojected
	history. Texels that see only terrain are skipped (a = -1), so they are
	never used as history.
*/
#prisma target clouds
#include "clouds.glsl"

bool seesSky()
{
	vec2 px = prisma.texelSize * 2.0;
	for (int x = -1; x <= 1; x++)
		for (int y = -1; y <= 1; y++) {
			if (isSky(texture(depthTex, texcoord + vec2(float(x), float(y)) * px).r))
				return true;
		}
	return false;
}

void main()
{
	if (!seesSky()) {
		fragColor = vec4(0.0, 0.0, 0.0, -1.0);
		return;
	}
	Atmos a = atmosState();
	vec3 dir = eyeDirection(texcoord);
	vec4 now = marchClouds(a, dir, ignAnim(gl_FragCoord.xy), CLOUD_STEPS, CLOUD_DETAIL);
	vec3 before = prismaOnPreviousScreen(dir);
	if (before.z > 0.0 && onScreenUv(before.xy)) {
		vec4 history = texture(clouds, before.xy);
		// History is valid only if every blended texel was sky
		if (history.a >= 0.0) {
#if CLOUD_QUALITY == CLOUD_QUALITY_ULTRA
			float keep = 0.9;
#else
			float keep = 0.85;
#endif
			now = mix(now, clampHistory(history, now), keep * historyTrust(a.w));
		}
	}
	fragColor = now;
}
