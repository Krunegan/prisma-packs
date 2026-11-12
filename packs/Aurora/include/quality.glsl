// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
/*
	Samples of the expensive effects, set by "Quality > Profile"
	(AURORA.md has the table). Look options don't depend on it.
*/
#ifndef AURORA_QUALITY
#define AURORA_QUALITY

#if PROFILE == PROFILE_POTATO
// Low with the costliest passes cut further
#define FOG_STEPS 4
#define FOG_UPSAMPLE 0
#define FOG_CLOUD_PER_STEP 0
#define MIST_BANKS 0
#define CLOUD_SHADOW_OCTAVES 1
#define WATER_LAND_STEPS 10
#define WATER_LAND_GROWTH 1.6
#define CLOUD_STEPS 10
#define CLOUD_LIGHT_STEPS 2
#define CLOUD_DETAIL 1
#define AURORA_STEPS 8
#define BLUR_SAMPLES 0
#define SHADOW_SEARCH 0
#define SHADOW_TAPS 4
#define AO_SLICES 0
#define AO_STEPS 0
#define SSR_STEPS 0
#define SSR_REFINE 0
#define CONTACT_SHADOWS 0
#elif PROFILE == PROFILE_LOW
#define FOG_STEPS 8
#define CLOUD_STEPS 16
#define CLOUD_LIGHT_STEPS 3
#define CLOUD_DETAIL 2
#define AURORA_STEPS 10
#define BLUR_SAMPLES 6
#define SHADOW_SEARCH 0
#define SHADOW_TAPS 8
#define AO_SLICES 0
#define AO_STEPS 0
#define SSR_STEPS 0
#define SSR_REFINE 0
#define CONTACT_SHADOWS 0
#elif PROFILE == PROFILE_MEDIUM
#define FOG_STEPS 12
#define CLOUD_STEPS 24
#define CLOUD_LIGHT_STEPS 4
#define CLOUD_DETAIL 3
#define AURORA_STEPS 14
#define BLUR_SAMPLES 8
#define SHADOW_SEARCH 8
#define SHADOW_TAPS 12
#define AO_SLICES 1
#define AO_STEPS 5
#define SSR_STEPS 16
#define SSR_REFINE 3
#define CONTACT_SHADOWS 0
#elif PROFILE == PROFILE_HIGH
#define FOG_STEPS 20
#define CLOUD_STEPS 36
#define CLOUD_LIGHT_STEPS 5
#define CLOUD_DETAIL 3
#define AURORA_STEPS 20
#define BLUR_SAMPLES 12
#define SHADOW_SEARCH 12
#define SHADOW_TAPS 20
#define AO_SLICES 2
#define AO_STEPS 6
#define SSR_STEPS 24
#define SSR_REFINE 4
#define CONTACT_SHADOWS 1
#else
#define FOG_STEPS 32
#define CLOUD_STEPS 56
#define CLOUD_LIGHT_STEPS 7
#define CLOUD_DETAIL 4
#define AURORA_STEPS 28
#define BLUR_SAMPLES 16
#define SHADOW_SEARCH 16
#define SHADOW_TAPS 32
#define AO_SLICES 2
#define AO_STEPS 8
#define SSR_STEPS 36
#define SSR_REFINE 6
#define CONTACT_SHADOWS 1
#endif

// Fog upsampling: 4 x 4 nearest texels (1) or 2 x 2 (0)
#ifndef FOG_UPSAMPLE
#define FOG_UPSAMPLE 1
#endif

// The clouds' shade in the shafts: every step (1) or once per ray (0)
#ifndef FOG_CLOUD_PER_STEP
#define FOG_CLOUD_PER_STEP 1
#endif

// Morning mist in noise banks (1) or even (0)
#ifndef MIST_BANKS
#define MIST_BANKS 1
#endif

// Octaves of the clouds' shade on the ground
#ifndef CLOUD_SHADOW_OCTAVES
#define CLOUD_SHADOW_OCTAVES 3
#endif

// Off-screen shore in reflections: overhead-map steps and their growth (~180 nodes)
#ifndef WATER_LAND_STEPS
#define WATER_LAND_STEPS 22
#endif
#ifndef WATER_LAND_GROWTH
#define WATER_LAND_GROWTH 1.22
#endif

// History kept by the temporal passes (clouds, fog, occlusion)
#if PROFILE == PROFILE_ULTRA
#define HISTORY_KEEP 0.9
#else
#define HISTORY_KEEP 0.86
#endif

#endif
