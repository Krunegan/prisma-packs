// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Exposure, a wide bloom, AgX with the sepia grade (grade.glsl), lens
	fringing, vignette, grain, dithering, cinema bars.
*/
#include "grade.glsl"

vec3 sceneAt(vec2 uv)
{
	return toLinear(texture(colorTex, uv).rgb);
}

void main()
{
	vec2 uv = texcoord;
	vec3 color;
	// Lens fringing: red and blue apart towards the edges
	if (options.aberration > 0.0) {
		vec2 d = (uv - 0.5);
		vec2 shift = d * dot(d, d) * 0.012 * options.aberration;
		color = vec3(sceneAt(uv - shift).r, sceneAt(uv).g, sceneAt(uv + shift).b);
	} else {
		color = sceneAt(uv);
	}

	float ev = options.exposure;
	if (options.auto_exposure)
		ev += texelFetch(state, ivec2(1, 0), 0).r;
	float k = exp2(ev);
	color *= k;
	if (options.bloom > 0.0)
		color = mix(color, texture(bloom1, uv).rgb * k / 4.0, options.bloom);

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
