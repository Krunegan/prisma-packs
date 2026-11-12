// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Weather, kept eased in the state buffer by 02_state.frag:
	  overcast  grey veil (0..1)
	  rain      rain now (0..1)
	  storm     lightning and wind (0..1)
	  wet       wetness, lagging the rain
	  flash     lightning now (> 1 at the strike)
	"Weather" picks a fixed weather or a slow random walk ("dynamic").
*/
#ifndef VESPER_WEATHER
#define VESPER_WEATHER

#include "common.glsl"

struct Weather {
	float overcast;
	float rain;
	float storm;
	float wet;
	float flash;
	float flashPrev; // the flash a frame ago
	vec3 flashDir;   // where the lightning is (world direction)
};

// Smooth random walk 0..1 over `t`
float slowWalk(float t, float seed)
{
	float i = floor(t);
	float f = fract(t);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i * 1.73 + seed), hash11((i + 1.0) * 1.73 + seed), f);
}

// What the options ask for: x = overcast, y = rain (before easing)
vec2 targetWeather()
{
#if WEATHER == WEATHER_CLEAR
	return vec2(0.0, 0.0);
#elif WEATHER == WEATHER_OVERCAST
	return vec2(0.75, 0.0);
#elif WEATHER == WEATHER_RAIN
	return vec2(0.9, 0.65);
#elif WEATHER == WEATHER_STORM
	return vec2(1.0, 1.0);
#else
	// Two walks at different speeds: long spells with some wobble
	float t = prisma.frameTimeCounter / (max(options.weather_cycle, 0.5) * 60.0) + 3.7;
	float w = 0.72 * slowWalk(t, 0.0) + 0.28 * slowWalk(t * 2.9, 5.0);
	// Skewed towards clear and cloudy weather
	w = pow(w, 1.15);
	float overcast = smoothstep(0.30, 0.62, w);
	float rain = smoothstep(0.56, 0.86, w);
	return vec2(overcast, rain);
#endif
}

// ---- Lightning -----------------------------------------------------------------
/*
	The same on every pixel and pass: time slots of a few seconds, some with
	a strike (random moment, distance, direction) in a storm. 02_state.frag
	plays its thunder as late as sound takes from that far.
*/
const float LIGHTNING_SLOT = 6.0;

bool lightningIn(float slot, float storm)
{
	return options.lightning && storm > 0.25 && hash11(slot * 1.37 + 0.5) <= (storm - 0.25) * 1.1;
}

float lightningStart(float slot)
{
	return slot * LIGHTNING_SLOT + hash11(slot + 7.1) * (LIGHTNING_SLOT - 1.5);
}

// Nodes (metres) away
float lightningDistance(float slot)
{
	return mix(120.0, 3500.0, pow(hash11(slot + 5.7), 1.4));
}

vec3 lightningDirectionOf(float slot)
{
	float a = hash11(slot + 11.7) * TAU;
	return normalize(vec3(cos(a), 0.2 + 0.35 * hash11(slot + 2.9), sin(a)));
}

float lightningFlash(float t, float storm)
{
	float slot = floor(t / LIGHTNING_SLOT);
	if (!lightningIn(slot, storm))
		return 0.0;
	float dt = t - lightningStart(slot);
	if (dt < 0.0 || dt > 1.6)
		return 0.0;
	float f = exp(-dt * 11.0);
	f += 0.9 * step(0.14, dt) * exp(-(dt - 0.14) * 16.0);
	f += 0.6 * step(0.36, dt) * exp(-(dt - 0.36) * 8.0);
	float near = 1.0 - smoothstep(120.0, 3500.0, lightningDistance(slot));
	return f * mix(0.35, 1.6, near) * smoothstep(0.25, 0.6, storm);
}

// ---- State ---------------------------------------------------------------------

Weather weatherState()
{
	vec4 w = texelFetch(state, ivec2(0, 0), 0);
	vec2 target = targetWeather();
	Weather s;
	// Before the state pass has run: what the options say
	bool ready = w.a > 0.0;
	s.overcast = ready ? w.b : target.x;
	float rain = ready ? w.r : target.y;
	s.storm = smoothstep(0.75, 1.0, rain);
	s.rain = rain * options.rain_amount;
	s.wet = ready ? w.g : (target.y > 0.0 ? 1.0 : 0.0);
	float t = prisma.frameTimeCounter;
	s.flash = lightningFlash(t, s.storm);
	s.flashPrev = lightningFlash(t - max(prisma.frameTime, 0.0) * 1.5, s.storm);
	s.flashDir = lightningDirectionOf(floor(t / LIGHTNING_SLOT));
	return s;
}

/*
	History the temporal passes may keep: none while lightning flickers, or
	the flash would smear across the screen.
*/
float historyTrust(Weather w)
{
	return 1.0 - saturate(max(w.flash, w.flashPrev) * 25.0);
}

// History clamped around this frame's value, so flashes and moved things don't linger
vec4 clampHistory(vec4 history, vec4 now)
{
	vec4 lo = now * 0.4 - 0.002;
	vec4 hi = now * 2.5 + 0.002;
	return clamp(history, min(lo, hi), max(lo, hi));
}

#endif
