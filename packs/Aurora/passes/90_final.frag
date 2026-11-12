// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Exposure, bloom, ACES with the vivid look (grade.glsl), vignette, grain,
	dithering, cinema bars.
*/
#include "grade.glsl"

void main()
{
	vec2 uv = texcoord;
	vec3 color = toLinear(texture(colorTex, uv).rgb);

	// ACES is darker in the mid-tones than Luanti's curve: +0.5 EV
	float ev = options.exposure + 0.5;
	if (options.auto_exposure)
		ev += texelFetch(state, ivec2(0, 0), 0).r;
	float k = exp2(ev);
	color *= k;
	// bloom1 holds the sum of five levels
	if (options.bloom > 0.0)
		color = mix(color, texture(bloom1, uv).rgb * k / 5.0, options.bloom);

	color = grade(color);
	color *= vignette(uv, options.vignette);
	color = filmGrain(color, gl_FragCoord.xy, options.grain);
	color += (ign(gl_FragCoord.xy) - 0.5) / 255.0;

	if (options.letterbox) {
		float bar = 0.5 - 0.5 * (prisma.viewSize.x / prisma.viewSize.y) / 2.39;
		if (bar > 0.0 && (uv.y < bar || uv.y > 1.0 - bar))
			color = vec3(0.0);
	}
	fragColor = vec4(max(color, vec3(0.0)), 1.0);
}
