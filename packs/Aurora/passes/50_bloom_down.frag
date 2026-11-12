// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
// Bloom: halve the scene into bloom1, bloom1 into bloom2... (<prisma/bloom.glsl>)
#prisma chain colorTex bloom1 bloom2 bloom3 bloom4 bloom5
#include <prisma/bloom.glsl>

void main()
{
	// The first step reads the scene (sRGB)
	fragColor = vec4(prismaBloomDown(PRISMA_CHAIN_SOURCE, texcoord, PRISMA_CHAIN_STEP == 0), 1.0);
}
