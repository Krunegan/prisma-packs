// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Camera motion blur (0 = off, the default): each pixel blurred towards
	where it was last frame, so it grows when the game runs slowly. The hand
	doesn't blur; a teleport gives none.
*/
#include "common.glsl"

// Closer than this (nodes): the hand
const float HAND_DIST = 0.6;

bool isHand(vec2 uv)
{
	float d = texture(depthTex, uv).r;
	return !isSky(d) && length(viewPosition(uv, d)) < HAND_DIST;
}

void main()
{
	vec3 color = texture(colorTex, texcoord).rgb;
	float depth = texture(depthTex, texcoord).r;
	// Potato has no motion blur (BLUR_SAMPLES 0)
	if (BLUR_SAMPLES == 0 || options.motion_blur <= 0.0 ||
		length(prisma.cameraPosition - prisma.prevCameraPosition) > 8.0) {
		fragColor = vec4(color, 1.0);
		return;
	}
	vec3 before;
	if (isSky(depth)) {
		before = prismaOnPreviousScreen(eyeDirection(texcoord));
	} else {
		vec3 player = playerPosition(texcoord, depth);
		if (length(player) < HAND_DIST) {
			fragColor = vec4(color, 1.0);
			return;
		}
		before = prismaPreviousScreenPosition(player);
	}
	if (before.z <= 0.0) {
		fragColor = vec4(color, 1.0);
		return;
	}
	// Half a frame's motion at 1 (180 degree shutter), at most 8 % of the screen
	vec2 motion = (texcoord - before.xy) * options.motion_blur * 0.5;
	float len = length(motion);
	if (len > 0.08)
		motion *= 0.08 / len;
	if (len * max(targetSize.x, targetSize.y) < 0.5) {
		fragColor = vec4(color, 1.0);
		return;
	}

	float jitter = ignAnim(gl_FragCoord.xy);
	vec3 sum = vec3(0.0);
	float weight = 0.0;
	for (int i = 0; i < BLUR_SAMPLES; i++) {
		float f = (float(i) + jitter) / float(BLUR_SAMPLES) - 0.5;
		vec2 uv = clamp(texcoord + motion * f, vec2(0.001), vec2(0.999));
		if (isHand(uv))
			continue;
		sum += toLinear(texture(colorTex, uv).rgb);
		weight += 1.0;
	}
	fragColor = vec4(weight > 0.0 ? toSrgb(sum / weight) : color, 1.0);
}
