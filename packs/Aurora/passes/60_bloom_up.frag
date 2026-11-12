// SPDX-FileCopyrightText: 2026 Flay Krunegan
// SPDX-License-Identifier: GPL-3.0-or-later
// Bloom: enlarge bloom5 onto bloom4... down to bloom1, which ends with all of it
#prisma chain bloom5 bloom4 bloom3 bloom2 bloom1
#include <prisma/bloom.glsl>

void main()
{
	fragColor = vec4(prismaBloomUp(PRISMA_CHAIN_TARGET, PRISMA_CHAIN_SOURCE, texcoord), 1.0);
}
