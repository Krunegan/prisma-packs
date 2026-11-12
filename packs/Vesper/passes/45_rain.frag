// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Rain drops in 3D: a sheared, falling grid of cells around the camera,
	each with at most one streak. Each eye ray walks the cells (DDA) and
	measures its distance to the streaks, so drops have true perspective.
	Two grids (near and far); no drops indoors (overhead map). Lit by sky,
	sun, torches and lightning.
*/
#include "fog.glsl"

struct RainGrid {
	vec3 cell;     // cell size (nodes) in the sheared space
	float len;     // streak length (nodes)
	float radius;  // drop radius (nodes)
	int steps;
};

// Brightness of one grid's drops along the ray, tStart to tEnd
float rainGrid(RainGrid g, vec3 dir, float tStart, float tEnd, vec2 shear, float fall, float pixel, float density, float seed)
{
	// Into the falling, sheared space where the drops are still and vertical
	vec3 o = prisma.cameraPosition + dir * tStart;
	vec3 os = vec3(o.x - shear.x * o.y, o.y + fall, o.z - shear.y * o.y) / g.cell;
	vec3 ds = vec3(dir.x - shear.x * dir.y, dir.y, dir.z - shear.y * dir.y) / g.cell;
	float span = tEnd - tStart;

	vec3 cell = floor(os);
	vec3 stepDir = sign(ds) + vec3(equal(ds, vec3(0.0)));
	vec3 invD = 1.0 / max(abs(ds), vec3(1e-6));
	vec3 tNext = (stepDir * (cell - os) + max(stepDir, vec3(0.0))) * invD;
	float tEnter = 0.0;
	float sum = 0.0;
	vec3 segment = vec3(0.0, g.len / g.cell.y, 0.0);
	float segLen2 = dot(segment, segment);
	for (int i = 0; i < g.steps; i++) {
		if (tEnter >= span)
			break;
		float tExit = min(min(tNext.x, tNext.y), min(tNext.z, span));
		vec3 h = hash33(cell + seed);
		if (h.x < density) {
			// The streak, in cell units: from A upwards
			vec3 A = cell + vec3(0.15 + 0.7 * h.y, 0.1 + 0.5 * h.z, 0.15 + 0.7 * fract(h.y * 7.13 + h.z));
			// Closest approach between the ray and the streak
			vec3 w0 = os - A;
			float b = dot(ds, segment);
			float a = dot(ds, ds);
			float den = a * segLen2 - b * b;
			float u = den > 1e-8 ? (a * dot(segment, w0) - b * dot(ds, w0)) / den : 0.0;
			u = clamp(u, 0.0, 1.0);
			float t = clamp(dot(A + segment * u - os, ds) / a, tEnter, tExit);
			u = clamp(dot(os + ds * t - A, segment) / segLen2, 0.0, 1.0);
			vec3 diff = (os + ds * t - A - segment * u) * g.cell;
			float across = length(diff);
			float dist = tStart + t;
			float width = max(g.radius, pixel * dist * 0.75);
			if (across < width && dist > 0.3) {
				vec3 player = dir * dist;
				float exposed = prisma.overheadAvailable ? overheadExposure(player, 0.3) : 1.0;
				float shape = (1.0 - smoothstep(0.3 * width, width, across)) * sin(u * 3.14159);
				sum += shape * (g.radius / width) * exposed * (0.6 + 0.4 * h.z) * smoothstep(0.3, 1.0, dist);
			}
		}
		tEnter = tExit;
		if (tNext.x < tNext.y && tNext.x < tNext.z) {
			cell.x += stepDir.x;
			tNext.x += invD.x;
		} else if (tNext.y < tNext.z) {
			cell.y += stepDir.y;
			tNext.y += invD.y;
		} else {
			cell.z += stepDir.z;
			tNext.z += invD.z;
		}
	}
	return sum;
}

void main()
{
	vec3 color = texture(colorTex, texcoord).rgb;
	Atmos a = atmosState();
	float rain = a.w.rain;
	if (rain <= 0.01 || options.rain_streaks <= 0.0 || underwater()) {
		fragColor = vec4(color, 1.0);
		return;
	}
	float depth = texture(depthTex, texcoord).r;
	float sceneDist = isSky(depth) ? 1e5 : length(viewPosition(texcoord, depth));
	vec3 dir = eyeDirection(texcoord);
	float t = prisma.frameTimeCounter;
	vec2 windDir = normalize(vec2(1.0, 0.35));
	vec2 shear = windDir * (options.wind * 0.45 + a.w.storm * 0.3);
	// Nodes per pixel at a distance of 1 node
	float pixel = 2.0 / (prisma.projectionMatrix[1][1] * prisma.viewSize.y);
	float density = saturate(rain) * 0.55;

	RainGrid nearGrid = RainGrid(vec3(0.45, 1.4, 0.45), 0.42, 0.0045, 40);
	RainGrid farGrid = RainGrid(vec3(1.1, 2.6, 1.1), 0.6, 0.008, 32);
	float split = 7.0;
	float far = 26.0;
	float sum = rainGrid(nearGrid, dir, 0.0, min(sceneDist, split), shear, t * 9.0, pixel, density, 0.0);
	if (sceneDist > split)
		sum += rainGrid(farGrid, dir, split, min(sceneDist, far), shear, t * 10.0, pixel, density, 31.0) *
			(1.0 - smoothstep(14.0, far, min(sceneDist, far)) * 0.5);

	if (sum <= 0.0) {
		fragColor = vec4(color, 1.0);
		return;
	}
	vec3 light = a.ambient * 0.9 + a.directLight * 0.25 + textureLod(glow, texcoord, 3.0).rgb * options.colored_light * 3.0;
	light += FLASH * a.w.flash * 1.5;
	sum *= options.rain_streaks * smoothstep(0.0, 0.5, rain) * 0.6;
	vec3 lin = toLinear(color);
	lin = mix(lin, light, saturate(sum * 0.5)) + light * sum * 0.5;
	fragColor = vec4(toSrgb(lin), 1.0);
}
