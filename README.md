<!-- SPDX-FileCopyrightText: 2026 Flay Krunegan -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Prisma Packs

This repository holds the shader packs for
[Prisma Shaders for Luanti](https://github.com/Krunegan/prisma-shaders).
Each pack is reviewed before it is published. Prisma's launcher lists the
published packs on its "Download packs" page, where they can be installed,
updated and removed.

## Layout

```text
prisma-packs/
├── index.toml              written by make_packs_index.py
├── make_packs_index.py     checks the packs and writes the index
├── packs/
│   └── <Pack>/             a pack, exactly as it is installed
│       ├── pack.toml
│       ├── LICENSE.txt     the pack's licence (or LICENSE.md)
│       ├── passes/ ...
│       └── screenshots/    up to 5 PNG images
└── thumbnails/
    └── <Pack>/             written by make_packs_index.py
```

The launcher reads `index.toml` from the latest commit of the `main` branch,
then the files of that same commit. Every file must match the size and
SHA-256 listed in the index; a pack with any file that does not is refused.
Only `main` is read: open pull requests, other branches and forks are not
published.

`thumbnails/<Pack>/` holds a 480 x 270 image for each screenshot, cut from
its middle. The launcher shows the thumbnails in its lists and downloads a
whole screenshot only when it is opened. Thumbnails are not installed with
the pack.

## Requirements for a pack

A pack is accepted when it meets all of the following.

**Manifest.** `pack.toml` sets `api`, a `name`, a `version`, an `author`, a
`description`, and a `license` given as an
[SPDX identifier](https://spdx.org/licenses/):

```toml
api = 1
name = "My Pack"
version = "1.0"
author = "Someone"
description = "What the pack does, in one or two sentences."
license = "CC-BY-4.0"
```

Prisma itself does not read `license`; this repository and the launcher
do. Each new version of a pack raises `version`: the launcher offers an
update only when the version differs from the installed one.

**Licence.** The licence allows anyone to copy and redistribute the pack
unchanged, since this repository keeps a copy of it. Its full text is in
the pack's folder as `LICENSE.txt` or `LICENSE.md`.

**Folder name.** Letters, digits, `_` and `-`, at most 64 characters. It
becomes the name of the installed folder and the value of `pack=` in the
player's `prisma.ini`, so it does not change between versions.

**Files.** Only pack data:

| Kind | Extensions |
|---|---|
| Manifest | `.toml` |
| Shaders | `.frag`, `.comp`, `.glsl` |
| Audio | `.ogg`, `.wav` |
| Text | `.txt`, `.md` |
| Screenshots | `.png`, in `screenshots/` only |

Hidden files (names that start with `.`) and any other kind of file are
refused. A pack never contains executable code.

**Screenshots.** Optional, and recommended: players see them before they
download the pack. At most five PNG files directly in `screenshots/`, each
at most 4 MB, between 1280 x 720 and 3840 x 2160, and between 4:3 and 21:9
in shape. They are shown in file-name order; the first one represents the
pack in the list.

**Shaders.** The passes compile with `prisma_check`, part of every Prisma
release:

```bash
prisma_check packs/MyPack
```

The pack works with the latest Prisma release and Luanti 5.17.0. Changes
to Luanti's shaders (`game/`) can only be checked inside the game.

## Submitting a pack

1. Fork this repository and add the pack's folder under `packs/`.
2. Run `make_packs_index.py` (see below). It reports what would be refused.
3. Open a pull request with the pack's folder only. `index.toml` and
   `thumbnails/` are written when the pull request is merged.

A new version of a published pack is submitted the same way, replacing the
pack's folder and raising its `version`.

## Review and publication

Every pull request is reviewed before it is merged: the files, the licence,
the look of the pack in the game, and `prisma_check`. A pack is published
once `index.toml` and `thumbnails/` that include it are on `main`.

## make_packs_index.py

Checks every pack under `packs/` against the requirements above and, only
if all of them pass, writes `index.toml` and `thumbnails/`. It needs
Python 3.11 or newer and [Pillow](https://pypi.org/project/pillow/).

```bash
pip install pillow
python make_packs_index.py
python make_packs_index.py --prisma-check path/to/prisma_check
```

`--prisma-check` also compiles each pack's passes; it needs a graphics card.

## Licences

Each pack, and its thumbnails, is under the licence stated in its
`pack.toml` and its `LICENSE` file. `make_packs_index.py` is under
GPL-3.0-or-later; this README and the pull request template are under
CC-BY-4.0; `index.toml` is under CC0-1.0. The texts are in `LICENSES/`.