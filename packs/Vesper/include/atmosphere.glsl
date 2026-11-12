// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Sun, moon, sky and air colours by time of day and weather (linear; a
	sunlit white surface is about 1). Every pass starts from atmosState().
	Warm and dusty by day, amber at dusk, grey-brown in storms, blue nights.
*/
#ifndef VESPER_ATMOSPHERE
#define VESPER_ATMOSPHERE

#include "weather.glsl"

// ---- Palette ------------------------------------------------------------------

const vec3 CLEAR_ZENITH = vec3(0.150, 0.215, 0.330);
const vec3 CLEAR_HORIZON = vec3(0.560, 0.560, 0.530);
const vec3 GREY_ZENITH = vec3(0.180, 0.170, 0.158);
const vec3 GREY_HORIZON = vec3(0.400, 0.370, 0.330);
const vec3 GOLD_ZENITH = vec3(0.110, 0.105, 0.125);
const vec3 GOLD_HORIZON = vec3(0.920, 0.520, 0.240);
const vec3 DUSK_ZENITH = vec3(0.022, 0.026, 0.050);
const vec3 DUSK_HORIZON = vec3(0.200, 0.105, 0.065);
const vec3 NIGHT_ZENITH = vec3(0.0016, 0.0030, 0.0085);
const vec3 NIGHT_HORIZON = vec3(0.0040, 0.0065, 0.0150);

const vec3 SUN_NOON = vec3(1.00, 0.93, 0.82);
const vec3 SUN_LOW = vec3(1.00, 0.56, 0.24);
const vec3 MOON_BLUE = vec3(0.42, 0.56, 1.00);
const vec3 MOON_GREY = vec3(0.80, 0.82, 0.86);
const vec3 FLASH = vec3(0.80, 0.85, 1.00);

struct Atmos {
	vec3 sunDir;
	vec3 moonDir;
	vec3 lightDir;     // the body casting Prisma's shadows
	float sunUp;       // 1 with the sun above the horizon
	float day;         // 1 by day, 0 by night
	float golden;      // 1 with the sun near the horizon
	float night;       // 1 in full night
	float overcast;
	Weather w;
	vec3 sunLight;     // the sun's direct light on the ground
	vec3 moonLight;
	vec3 directLight;  // light of lightDir on the ground
	vec3 zenith;
	vec3 horizon;
	vec3 ambient;      // average light of the sky dome
	float directShare; // direct sun's share of daylight on open ground
};

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
	a.w = weatherState();
	a.sunDir = sunDirection();
	a.moonDir = moonDirection();
	float h = a.sunDir.y;
	a.sunUp = smoothstep(-0.04, 0.06, h);
	a.day = smoothstep(-0.12, 0.18, h);
	a.golden = (1.0 - smoothstep(0.02, 0.38, abs(h - 0.04))) * smoothstep(-0.12, 0.0, h);
	float dusk = (1.0 - smoothstep(0.0, 0.2, abs(h + 0.06)));
	a.night = 1.0 - smoothstep(-0.32, -0.04, h);
	a.overcast = saturate(a.w.overcast);

	// Sky colours: clear/overcast blend, then the golden hour, dusk and night
	vec3 zenith = mix(CLEAR_ZENITH, GREY_ZENITH, a.overcast);
	vec3 horizon = mix(CLEAR_HORIZON, GREY_HORIZON, a.overcast);
	zenith = mix(zenith, GOLD_ZENITH, a.golden * 0.75);
	horizon = mix(horizon, mix(GOLD_HORIZON, GREY_HORIZON * 1.1, a.overcast * 0.6), a.golden * 0.85);
	zenith = mix(zenith, DUSK_ZENITH, dusk * (1.0 - a.day * 0.5));
	horizon = mix(horizon, DUSK_HORIZON, dusk * (1.0 - a.day * 0.5));
	float nightLevel = mix(2.2, 0.35, options.night_darkness);
	vec3 nightTint = mix(vec3(1.0), normalizeLum(MOON_BLUE) * 0.8, options.moon_blue);
	vec3 nZenith = mix(NIGHT_ZENITH, vec3(luminance(NIGHT_ZENITH)), 1.0 - options.moon_blue) * nightLevel;
	vec3 nHorizon = mix(NIGHT_HORIZON, vec3(luminance(NIGHT_HORIZON)), 1.0 - options.moon_blue) * nightLevel;
	a.zenith = mix(nZenith, zenith, a.day);
	a.horizon = mix(nHorizon, horizon, a.day);
	// Storm clouds darken the whole sky
	float storm = a.w.storm;
	a.zenith *= mix(1.0, 0.55, storm);
	a.horizon *= mix(1.0, 0.65, storm);

	// The sun, reddened low, veiled by the overcast
	vec3 sunColor = mix(SUN_NOON, SUN_LOW, pow(1.0 - smoothstep(0.0, 0.45, h), 1.6));
	sunColor *= prismaLuantiScatteringAtGround(a.sunDir) * 0.35 + 0.65;
	a.sunLight = normalizeLum(sunColor) * a.sunUp * options.sun_intensity * 1.15 *
		mix(1.0, 0.18, a.overcast) * mix(1.0, 0.5, storm);
	// The moon: a cold, faint light
	float moonUp = smoothstep(-0.04, 0.08, a.moonDir.y);
	vec3 moonColor = mix(MOON_GREY, MOON_BLUE, options.moon_blue);
	a.moonLight = normalizeLum(moonColor) * 0.09 * nightLevel * moonUp * mix(1.0, 0.25, a.overcast);

	bool moon = h < -0.04 && a.moonDir.y > 0.0;
	a.lightDir = prisma.sunAvailable ? prisma.lightDirection : (moon ? a.moonDir : a.sunDir);
	// Whichever body Prisma's shadows come from
	if (prisma.sunAvailable)
		moon = dot(a.lightDir, a.moonDir) > dot(a.lightDir, a.sunDir);
	a.directLight = moon ? a.moonLight : a.sunLight;

	a.ambient = mix(a.horizon, a.zenith, 0.45) * options.sky_light + vec3(0.0003);
	// Lightning lights the whole sky for an instant
	a.ambient += FLASH * a.w.flash * 0.35;

	float clear = 1.0 - a.overcast;
	a.directShare = moon ? mix(0.15, 0.55, clear) : mix(0.15, 0.68, clear * clear) * a.sunUp;
	a.directShare *= mix(1.0, 0.5, storm);
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
vec3 skyDome(Atmos a, vec3 dir)
{
	float up = max(dir.y, 0.0);
	// A wide, soft horizon band: thick air
	vec3 col = mix(a.horizon, a.zenith, pow(smoothstep(0.0, 1.0, up), 0.55));
	// Brighter low around the sun (forward scattering)
	float c = dot(dir, a.sunDir);
	float sunSide = pow(max(c * 0.5 + 0.5, 0.0), 3.0) * (1.0 - smoothstep(0.0, 0.6, up));
	col += normalizeLum(a.sunLight + vec3(1e-5)) * a.horizon * sunSide * (0.6 + 1.6 * a.golden) * a.day;
	// The Mie glow: wide halo and tight aureole
	float glow = hgPhase(c, 0.72) * 0.9 + hgPhase(c, 0.93) * 0.07;
	col += a.sunLight * glow * mix(0.25, 0.10, a.overcast) * (1.0 + a.golden);
	// The moon's glow
	float mc = dot(dir, a.moonDir);
	col += a.moonLight * hgPhase(mc, 0.85) * 0.5;
	// Below the horizon: darker, as if seen over dark land
	col *= mix(1.0, 0.45, smoothstep(0.0, -0.35, dir.y));
	// Lightning brightens its side of the sky
	if (a.w.flash > 0.0)
		col += FLASH * a.w.flash * (0.08 + 0.6 * pow(max(dot(dir, a.w.flashDir), 0.0), 6.0));
	return col;
}

float starField(vec3 dir)
{
	vec3 p = dir * 300.0;
	vec3 cell = floor(p);
	vec3 h = hash33(cell);
	if (h.x < 0.9965)
		return 0.0;
	vec3 centre = cell + 0.25 + 0.5 * h;
	float d = length(p - centre);
	float twinkle = 0.65 + 0.35 * sin(prisma.frameTimeCounter * (1.5 + 3.0 * h.y) + h.z * 40.0);
	return smoothstep(0.55, 0.0, d) * (0.3 + 1.7 * h.z * h.z) * twinkle;
}

// The sun's disc, the moon and the stars
vec3 skyBodies(Atmos a, vec3 dir)
{
	vec3 col = vec3(0.0);
	// The sun: a round disc, softened at the limb
	float c = dot(dir, a.sunDir);
	float sunR = 0.9995;
	float disc = smoothstep(sunR - 0.00025, sunR + 0.0001, c);
	float limb = 0.6 + 0.4 * sqrt(saturate((c - sunR) / (1.0 - sunR)));
	col += normalizeLum(a.sunLight + vec3(1e-5)) * disc * limb * 60.0 * a.sunUp * options.sun_intensity *
		mix(1.0, 0.05, a.overcast);

	// The moon: a pale disc with darker seas
	vec3 m = bodyPlane(dir, a.moonDir, 0.028);
	if (m.z > 0.0) {
		float r = length(m.xy);
		float moonUp = smoothstep(-0.05, 0.05, a.moonDir.y);
		if (r < 1.05) {
			float seas = 0.72 + 0.28 * fbm2(m.xy * 2.2 + 7.0, 3);
			float shade = sqrt(max(1.0 - r * r, 0.0)) * 0.4 + 0.6;
			col += mix(MOON_GREY, MOON_BLUE, 0.25 * options.moon_blue) * 1.2 * seas * shade *
				smoothstep(1.0, 0.96, r) * moonUp * mix(1.0, 0.1, a.overcast);
		}
	}

	if (a.night > 0.01 && dir.y > 0.0)
		col += vec3(0.85, 0.88, 1.0) * starField(dir) * 0.06 * a.night * smoothstep(0.0, 0.25, dir.y) *
			(1.0 - a.overcast);
	return col;
}

vec3 skyColor(Atmos a, vec3 dir)
{
	return skyDome(a, dir) + skyBodies(a, dir);
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
