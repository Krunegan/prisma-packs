// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Sun, moon, sky and air colours by time of day (linear; a sunlit white
	surface is about 1). Every pass starts from atmosState(), so sky, clouds,
	fog and light agree. Heavy cloud cover pales the sky and dims the sun.
*/
#ifndef AURORA_ATMOSPHERE
#define AURORA_ATMOSPHERE

#include "common.glsl"

// ---- Palette ------------------------------------------------------------------

const vec3 CLEAR_ZENITH = vec3(0.045, 0.140, 0.600);
const vec3 CLEAR_HORIZON = vec3(0.420, 0.620, 0.980);
const vec3 GREY_ZENITH = vec3(0.230, 0.275, 0.350);
const vec3 GREY_HORIZON = vec3(0.520, 0.560, 0.610);
const vec3 GOLD_ZENITH = vec3(0.090, 0.120, 0.270);
const vec3 GOLD_HORIZON = vec3(1.300, 0.480, 0.220);
const vec3 GOLD_AWAY = vec3(0.620, 0.380, 0.560);   // the horizon opposite the low sun: rose and lilac
const vec3 DUSK_ZENITH = vec3(0.018, 0.024, 0.062);
const vec3 DUSK_HORIZON = vec3(0.230, 0.110, 0.110);
const vec3 NIGHT_ZENITH = vec3(0.0012, 0.0026, 0.0085);
const vec3 NIGHT_HORIZON = vec3(0.0035, 0.0060, 0.0150);

const vec3 SUN_NOON = vec3(1.00, 0.95, 0.87);
const vec3 SUN_LOW = vec3(1.00, 0.42, 0.13);
const vec3 MOON_BLUE = vec3(0.50, 0.62, 1.00);
const vec3 MOON_GREY = vec3(0.82, 0.84, 0.88);

struct Atmos {
	vec3 sunDir;
	vec3 moonDir;
	vec3 lightDir;     // the body casting Prisma's shadows
	float sunUp;       // 1 with the sun above the horizon
	float day;         // 1 by day, 0 by night
	float golden;      // 1 with the sun near the horizon
	float night;       // 1 in full night
	float overcast;    // 0..1, from the cloud cover
	vec3 sunTop;       // the sun's light above the clouds
	vec3 sunLight;     // the sun's direct light on the ground
	vec3 moonLight;
	vec3 directLight;  // light of lightDir on the ground
	vec3 zenith;
	vec3 horizon;      // the horizon on the sun's side
	vec3 horizonAway;  // and opposite it
	vec3 ambient;      // average light of the sky dome
	float directShare; // direct sun's share of daylight on open ground
};

/*
	Under a hidden sky (prisma.skyHidden) there is no sun, moon, star or
	cloud: the place takes Luanti's fog colour, and the light comes from its
	lamps and from a glow low on the horizon ([shadows] hidden_sky_light).
*/

// The glow's colour (linear) and how much it lights what faces it
const vec3 HORIZON_GLOW = vec3(1.40, 0.42, 0.13);
const float HIDDEN_GLOW_LIGHT = 0.45;
// Its direction when there is no shadow map (as in pack.toml)
const vec3 HIDDEN_GLOW_DIR = vec3(1.0, 0.18, 0.0); // in the east, 10 degrees up
// How much of the place's colour lights the shade under a hidden sky
const float HIDDEN_SKY_GLOW = 0.06;

vec3 placeColour()
{
	return toLinear(clamp(prisma.fogColor, 0.0, 1.0));
}

// Towards the sun; without it, Luanti's day light still tells day from night
vec3 sunDirection()
{
	if (prisma.sunAvailable)
		return prisma.sunDirection;
	float day = smoothstep(0.08, 0.7, maxOf(prisma.dayLight));
	return normalize(vec3(0.35, mix(-0.6, 0.9, day), 0.0));
}

vec3 moonDirection()
{
	if (prisma.sunAvailable)
		return prisma.moonDirection;
	return -sunDirection();
}

Atmos atmosState()
{
	Atmos a;
	a.sunDir = sunDirection();
	a.moonDir = moonDirection();
	float h = a.sunDir.y;
	a.sunUp = smoothstep(-0.04, 0.06, h);
	a.day = smoothstep(-0.12, 0.18, h);
	a.golden = (1.0 - smoothstep(0.02, 0.36, abs(h - 0.04))) * smoothstep(-0.12, 0.0, h);
	float dusk = 1.0 - smoothstep(0.0, 0.2, abs(h + 0.06));
	a.night = 1.0 - smoothstep(-0.32, -0.04, h);
	a.overcast = options.clouds ? smoothstep(0.6, 1.0, options.cloud_cover) * 0.85 : 0.0;

	// Sky colours: clear/overcast blend, then the golden hour, dusk and night
	vec3 zenith = mix(CLEAR_ZENITH, GREY_ZENITH, a.overcast);
	vec3 horizon = mix(CLEAR_HORIZON, GREY_HORIZON, a.overcast);
	zenith = mix(zenith, GOLD_ZENITH, a.golden * 0.7);
	vec3 away = mix(horizon * 0.94, mix(GOLD_AWAY, GREY_HORIZON, a.overcast * 0.6), a.golden * 0.85);
	horizon = mix(horizon * 1.06, mix(GOLD_HORIZON, GREY_HORIZON * 1.1, a.overcast * 0.6), a.golden * 0.85);
	zenith = mix(zenith, DUSK_ZENITH, dusk * (1.0 - a.day * 0.5));
	horizon = mix(horizon, DUSK_HORIZON, dusk * (1.0 - a.day * 0.5));
	away = mix(away, DUSK_ZENITH * 1.6, dusk * (1.0 - a.day * 0.5));
	float nightLevel = mix(2.2, 0.35, options.night_darkness);
	a.zenith = mix(NIGHT_ZENITH * nightLevel, zenith, a.day);
	a.horizon = mix(NIGHT_HORIZON * nightLevel, horizon, a.day);
	a.horizonAway = mix(NIGHT_HORIZON * nightLevel, away, a.day);

	// The sun, reddened low in the sky
	vec3 sunColor = mix(SUN_NOON, SUN_LOW, pow(1.0 - smoothstep(0.0, 0.45, h), 1.3));
	sunColor *= prismaLuantiScatteringAtGround(a.sunDir) * 0.3 + 0.7;
	a.sunTop = normalizeLum(sunColor) * a.sunUp * options.sun_intensity * 1.2;
	a.sunLight = a.sunTop * mix(1.0, 0.25, a.overcast);
	// The moon: a cold, faint light
	float moonUp = smoothstep(-0.04, 0.08, a.moonDir.y);
	a.moonLight = normalizeLum(MOON_BLUE) * 0.08 * nightLevel * moonUp * mix(1.0, 0.3, a.overcast);

	bool moon = h < -0.04 && a.moonDir.y > 0.0;
	a.lightDir = prisma.sunAvailable ? prisma.lightDirection : (moon ? a.moonDir : a.sunDir);
	// Whichever body Prisma's shadows come from
	if (prisma.sunAvailable)
		moon = dot(a.lightDir, a.moonDir) > dot(a.lightDir, a.sunDir);
	a.directLight = moon ? a.moonLight : a.sunLight;

	a.ambient = mix((a.horizon + a.horizonAway) * 0.5, a.zenith, 0.45) * options.sky_light + vec3(0.0003);

	float clear = 1.0 - a.overcast;
	a.directShare = moon ? mix(0.2, 0.55, clear) : mix(0.2, 0.74, clear * clear) * a.sunUp;

	if (prisma.skyHidden) {
		// No sky: the dome takes the place's colour, the glow is the only outside light
		vec3 place = placeColour();
		float glow = options.horizon_glow;
		a.sunDir = prisma.shadowAvailable ? prisma.lightDirection : normalize(HIDDEN_GLOW_DIR);
		a.moonDir = -a.sunDir;
		a.lightDir = a.sunDir;
		a.sunUp = 0.0;
		a.day = 0.0;
		a.golden = 0.0;
		a.night = 0.0;
		a.overcast = 0.0;
		a.sunTop = a.sunLight = normalizeLum(HORIZON_GLOW) * HIDDEN_GLOW_LIGHT * glow;
		a.moonLight = vec3(0.0);
		a.directLight = a.sunLight;
		a.zenith = place * 0.55;
		a.horizon = place + HORIZON_GLOW * 0.5 * glow;
		a.horizonAway = place + HORIZON_GLOW * 0.12 * glow;
		a.ambient = place * 0.35 * options.sky_light + vec3(0.0003);
		a.directShare = prisma.shadowAvailable ? 0.55 * saturate(glow) : 0.0;
	}
	return a;
}

// ---- Sky ----------------------------------------------------------------------

// `dir` on the plane facing `body`, in units of `size`; z < 0 behind
vec3 bodyPlane(vec3 dir, vec3 body, float size)
{
	vec3 up = abs(body.y) > 0.999 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, body));
	vec3 top = cross(body, right);
	float d = dot(dir, body);
	if (d <= 0.0)
		return vec3(0.0, 0.0, -1.0);
	return vec3(vec2(dot(dir, right), dot(dir, top)) / (d * size), 1.0);
}

// The sky dome without the sun, moon, stars or clouds
// Under a hidden sky: dark, with a band of fire along the horizon
vec3 hiddenDome(Atmos a, vec3 dir)
{
	float glow = options.horizon_glow;
	vec2 flatDir = dir.xz / max(length(dir.xz), 1e-4);
	vec2 glowFlat = a.sunDir.xz / max(length(a.sunDir.xz), 1e-4);
	float towards = dot(flatDir, glowFlat) * 0.5 + 0.5;
	float h = abs(dir.y - a.sunDir.y * 0.5);
	float band = exp(-h * mix(11.0, 4.5, towards * towards)) * mix(0.18, 1.0, pow(towards, 3.0));
	float heart = exp(-h * 26.0) * pow(towards, 10.0);
	float halo = pow(max(dot(dir, a.sunDir), 0.0), 40.0);
	vec3 col = placeColour() * mix(0.5, 1.0, exp(-abs(dir.y) * 3.0));
	col += HORIZON_GLOW * (band + heart * 2.5) * glow;
	col += vec3(1.6, 1.15, 0.8) * halo * 1.5 * glow;
	return col;
}

vec3 skyDome(Atmos a, vec3 dir)
{
	if (prisma.skyHidden)
		return hiddenDome(a, dir);
	float up = max(dir.y, 0.0);
	// The horizon towards the sun or away from it
	vec2 flatDir = dir.xz / max(length(dir.xz), 1e-4);
	vec2 sunFlat = a.sunDir.xz / max(length(a.sunDir.xz), 1e-4);
	vec3 horizon = mix(a.horizonAway, a.horizon, smoothstep(-0.7, 0.9, dot(flatDir, sunFlat)));
	// Deep blue overhead, a bright band low in the sky
	vec3 col = mix(horizon, a.zenith, pow(smoothstep(0.0, 1.0, up), 0.45));
	// Brighter low around the sun (forward scattering)
	float c = dot(dir, a.sunDir);
	float sunSide = pow(max(c * 0.5 + 0.5, 0.0), 3.0) * (1.0 - smoothstep(0.0, 0.55, up));
	col += normalizeLum(a.sunTop + vec3(1e-5)) * horizon * sunSide * (0.35 + 1.8 * a.golden) * a.day;
	// The Mie glow: wide halo and tight aureole
	float glow = hgPhase(c, 0.75) * 0.7 + hgPhase(c, 0.95) * 0.06;
	col += a.sunLight * glow * mix(0.14, 0.07, a.overcast) * (1.0 + 0.4 * a.golden);
	// The moon's glow
	float mc = dot(dir, a.moonDir);
	col += a.moonLight * hgPhase(mc, 0.85) * 0.5;
	// Below the horizon: darker, as if seen over the land
	col *= mix(1.0, 0.5, smoothstep(0.0, -0.35, dir.y));
	return col;
}

float starField(vec3 dir)
{
	vec3 p = dir * 300.0;
	vec3 cell = floor(p);
	vec3 h = hash33(cell);
	if (h.x < 0.996)
		return 0.0;
	vec3 centre = cell + 0.25 + 0.5 * h;
	float d = length(p - centre);
	float twinkle = 0.7 + 0.3 * sin(prisma.frameTimeCounter * (1.5 + 3.0 * h.y) + h.z * 40.0);
	return smoothstep(0.55, 0.0, d) * (0.3 + 1.7 * h.z * h.z) * twinkle;
}

/*
	Northern lights (0 = off, the default): curtains of bent ribbons on a
	plane, crossed by each ray at a stack of heights, so bright spots become
	vertical streaks. Mostly towards the north (+z), fixed in the sky. They
	light nothing (no coloured light in Aurora).
*/

// The curtains at `p` (on the plane, in units of its height)
float auroraCurtains(vec2 p, float t)
{
	vec2 warp = vec2(vnoise2(p * 0.18 + vec2(t * 0.02, 1.7)), vnoise2(p * 0.18 + vec2(4.3, -t * 0.015)));
	// Across the ribbons (v) and along them (u): roughly east to west
	float v = p.y * 0.12 + p.x * 0.04 + (warp.x - 0.5) * 3.0 + (vnoise2(p * 0.7 + t * 0.05) - 0.5) * 0.4;
	float u = p.x * 0.12 - p.y * 0.04 + (warp.y - 0.5) * 2.0;
	float ribbon = pow(1.0 - abs(fract(v) - 0.5) * 2.0, 14.0);
	// Fine rays along each ribbon, flickering slowly
	float rays = 0.35 + 0.65 * vnoise2(vec2(u * 30.0, t * 0.35));
	// Only in parts of the sky, more towards the north
	float north = mix(0.35, 1.0, smoothstep(-20.0, 20.0, p.y));
	float region = smoothstep(0.3, 0.7, vnoise2(p * 0.04 + vec2(t * 0.004, 9.1)) * north + 0.15 * north);
	return ribbon * rays * region;
}

// Their light along `dir` (linear, added to the sky)
vec3 northernLights(Atmos a, vec3 dir, float jitter, int steps)
{
	float amount = options.northern_lights * a.night * (1.0 - a.overcast);
	if (amount <= 0.001 || dir.y <= 0.0)
		return vec3(0.0);
	float t = prisma.frameTimeCounter;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < steps; i++) {
		// 0 = the lower edge of the curtains, 1 = their top
		float f = (float(i) + jitter) / float(steps);
		float height = 1.0 + f * 1.6;
		vec2 p = dir.xz / (dir.y + 0.06) * height * 3.0;
		float glow = exp(-f * 1.8) * smoothstep(0.0, 0.06, f);
		vec3 tint = mix(vec3(0.05, 1.0, 0.45), vec3(0.05, 0.75, 1.0), smoothstep(0.05, 0.3, f));
		tint = mix(tint, vec3(0.55, 0.15, 1.0), smoothstep(0.3, 0.75, f));
		sum += tint * auroraCurtains(p, t) * glow;
	}
	return sum / float(steps) * smoothstep(0.0, 0.15, dir.y) * amount * 1.4;
}

// The sun's disc, the moon and the stars
vec3 skyBodies(Atmos a, vec3 dir)
{
	vec3 col = vec3(0.0);
	if (prisma.skyHidden)
		return col;
	// The sun: a round disc, soft at the limb
	float c = dot(dir, a.sunDir);
	float sunR = 0.99955;
	float disc = smoothstep(sunR - 0.00022, sunR + 0.0001, c);
	float limb = 0.6 + 0.4 * sqrt(saturate((c - sunR) / (1.0 - sunR)));
	col += normalizeLum(a.sunTop + vec3(1e-5)) * disc * limb * 80.0 * a.sunUp * options.sun_intensity *
		mix(1.0, 0.1, a.overcast);

	// The moon: a pale disc with darker seas
	vec3 m = bodyPlane(dir, a.moonDir, 0.028);
	if (m.z > 0.0) {
		float r = length(m.xy);
		float moonUp = smoothstep(-0.05, 0.05, a.moonDir.y);
		if (r < 1.05) {
			float seas = 0.72 + 0.28 * fbm2(m.xy * 2.2 + 7.0, 3);
			float shade = sqrt(max(1.0 - r * r, 0.0)) * 0.4 + 0.6;
			col += mix(MOON_GREY, MOON_BLUE, 0.2) * 1.3 * seas * shade * smoothstep(1.0, 0.96, r) * moonUp *
				mix(1.0, 0.15, a.overcast);
		}
	}

	if (a.night > 0.01 && dir.y > 0.0)
		col += vec3(0.85, 0.88, 1.0) * starField(dir) * 0.07 * a.night * smoothstep(0.0, 0.25, dir.y) *
			(1.0 - a.overcast);
	return col;
}

vec3 skyColor(Atmos a, vec3 dir)
{
	return skyDome(a, dir) + skyBodies(a, dir);
}

// ---- The horizon: what lies past Luanti's view range ---------------------------------

const float SKY_FOG_DIST = 3500.0;

/*
	Above the horizon: the sky with its far haze, lit by the sun. Below it,
	past Luanti's view range: the horizon row in that direction, so the
	horizon has no seam.
*/
vec3 horizonClamp(vec3 dir)
{
	vec3 d = vec3(dir.x, max(dir.y, 0.0), dir.z);
	float len = length(d);
	return len > 1e-4 ? d / len : vec3(0.0, 1.0, 0.0);
}

// Where to look past the view: the horizon row, or `dir` under a hidden sky
vec3 farDirection(vec3 dir)
{
	return prisma.skyHidden ? dir : horizonClamp(dir);
}

// The background along `dir`, without the sun, moon, stars or clouds
vec3 background(Atmos a, vec3 dir)
{
	// Under a hidden sky what fades into Luanti's fog fades into the dark of
	// the place, not into the glow (it would show through walls)
	if (prisma.skyHidden)
		return placeColour() * 0.8;
	return skyDome(a, farDirection(dir));
}

// Stereographic map of the upper hemisphere (skymap buffer)
vec2 skymapUv(vec3 dir)
{
	vec3 d = normalize(vec3(dir.x, max(dir.y, 0.0), dir.z));
	return d.xz / (1.0 + d.y) * 0.5 + 0.5;
}

vec3 skymapDir(vec2 uv)
{
	vec2 q = uv * 2.0 - 1.0;
	float r2 = dot(q, q);
	return normalize(vec3(2.0 * q.x, 1.0 - r2, 2.0 * q.y) / (1.0 + r2));
}

#endif
