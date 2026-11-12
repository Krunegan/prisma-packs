// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Shared helpers: colour, noise, phase functions, screen.

	The scene is in approximate sRGB between passes (may exceed 1); light is
	worked out in linear. Pack buffers hold linear colour. noiseTex
	(00_noise.frag) gives one-fetch 3D (r, g) and 2D (b) value noise.
*/
#ifndef VESPER_COMMON
#define VESPER_COMMON

#include <prisma/color.glsl>
#include <prisma/noise.glsl>
#include <prisma/screen.glsl>
#include <prisma/luanti.glsl>

const float PI = 3.14159265;
const float TAU = 6.28318531;

vec3 toLinear(vec3 c) { return prismaToLinear(c); }
vec3 toSrgb(vec3 c) { return prismaToSrgb(c); }
float luminance(vec3 c) { return prismaLuminance(c); }
float maxOf(vec3 c) { return prismaMaxOf(c); }
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }

vec3 normalizeLum(vec3 c)
{
	return c / max(luminance(c), 1e-5);
}

float remap(float x, float a, float b, float c, float d)
{
	return c + (x - a) / (b - a) * (d - c);
}

float remap01(float x, float a, float b)
{
	return clamp((x - a) / (b - a), 0.0, 1.0);
}

float ign(vec2 p) { return prismaIGN(p); }
float ignAnim(vec2 p) { return prismaIGNAnimated(p); }
float hash11(float p) { return prismaHash11(p); }
float hash12(vec2 p) { return prismaHash12(p); }
float hash13(vec3 p) { return prismaHash13(p); }
vec2 hash22(vec2 p) { return prismaHash22(p); }

vec3 hash33(vec3 p)
{
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// ---- Noise from the noise buffer ---------------------------------------------------

const float NOISE_SIZE = 256.0;        // lattice cells; the buffer is one texel bigger
const vec2 NOISE_SLICE = vec2(37.0, 17.0);

#ifndef VESPER_NO_NOISE_TEX
// Smooth 3D value noise, 0..1: one fetch
float vnoise3(vec3 x)
{
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 cell = mod(p.xy + NOISE_SLICE * p.z, NOISE_SIZE);
	vec2 rg = texture(noiseTex, (cell + f.xy + 0.5) / (NOISE_SIZE + 1.0)).rg;
	return mix(rg.x, rg.y, f.z);
}

// Smooth 2D value noise, 0..1: one fetch
float vnoise2(vec2 x)
{
	vec2 p = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 cell = mod(p, NOISE_SIZE);
	return texture(noiseTex, (cell + f + 0.5) / (NOISE_SIZE + 1.0)).b;
}

float fbm2(vec2 p, int octaves)
{
	const mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
	float f = 0.0, w = 0.5, total = 0.0;
	for (int i = 0; i < octaves; i++) {
		f += w * vnoise2(p);
		total += w;
		p = rot * p * 2.07 + 13.7;
		w *= 0.5;
	}
	return f / total;
}

float fbm3(vec3 p, int octaves)
{
	float f = 0.0, w = 0.5, total = 0.0;
	for (int i = 0; i < octaves; i++) {
		f += w * vnoise3(p);
		total += w;
		p = p * 2.13 + vec3(17.1, 31.7, 7.3);
		w *= 0.5;
	}
	return f / total;
}

// Caustics: the moving net of light focused by the waves
float caustics(vec2 p, float t)
{
	vec2 q = p * 0.9;
	float n1 = vnoise2(q + vec2(t * 0.31, t * 0.19));
	float n2 = vnoise2(q * 1.37 - vec2(t * 0.23, -t * 0.29) + 5.3);
	float c = 1.0 - saturate(abs(n1 - n2) * 5.0);
	return c * c * c * c;
}
#endif

// ---- Phase functions ------------------------------------------------------------------

// Henyey-Greenstein, normalised (1 / 4pi when g = 0)
float hgPhase(float cosT, float g)
{
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cosT, 1e-4), 1.5));
}

// Strong forward lobe plus a weak back lobe
float hazePhase(float cosT)
{
	return mix(hgPhase(cosT, -0.25), hgPhase(cosT, 0.78), 0.72);
}

// ---- Screen ---------------------------------------------------------------------------

bool onScreenUv(vec2 uv)
{
	return all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)));
}

// View-space position -> screen uv
vec2 viewToUv(vec3 view)
{
	vec4 clip = prisma.projectionMatrix * vec4(view, 1.0);
	return clip.xy / clip.w * 0.5 + 0.5;
}

/*
	Light of glowing blocks (14_glow.frag, mip `lod`) reaching something
	`dist` nodes away: only what is about as far as the light receives it.
*/
vec3 glowAt(vec2 uv, float lod, float dist)
{
	vec4 g = textureLod(glow, uv, lod);
	float l = luminance(g.rgb);
	if (l < 1e-5)
		return vec3(0.0);
	float from = g.a / l;
	return g.rgb * exp(-abs(dist - from) / (1.5 + 0.12 * from));
}

/*
	Opaque liquids (PRISMA_MAT_LIQUID_OPAQUE) are lava, which glows and is
	orange or red, and water when translucent_liquids is off.
*/
bool glowingLiquid(vec2 uv)
{
	if (gbufferMaterial(uv) != PRISMA_MAT_LIQUID_OPAQUE)
		return false;
	vec3 c = texture(colorTex, uv).rgb;
	return gbufferBlockLight(uv) > 0.5 && c.r > c.b * 1.3;
}

// The surface of water, translucent or drawn opaque
bool waterSurface(vec2 uv)
{
	return gbufferLiquid(uv) || (gbufferMaterial(uv) == PRISMA_MAT_LIQUID_OPAQUE && !glowingLiquid(uv));
}

// Luanti says the camera is inside a liquid node
bool inLiquidNode()
{
	return prisma.liquidColor.a > 0.0;
}

// Underwater: in a liquid node AND below its surface (floating, the eyes
// are often in the node but above the surface; see 02_state.frag)
bool underwater()
{
	return inLiquidNode() && texelFetch(state, ivec2(1, 1), 0).r > 0.5;
}

#endif
