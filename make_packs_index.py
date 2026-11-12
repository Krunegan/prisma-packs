# SPDX-FileCopyrightText: 2026 Flay Krunegan
# SPDX-License-Identifier: GPL-3.0-or-later
"""Checks every pack of the prisma-packs repository and writes index.toml and
the thumbnails, which Prisma's launcher reads ("Download packs"; the format
is described in src/launcher/downloads.hpp of prisma-shaders):

    python make_packs_index.py [folder] [--prisma-check PATH]

<folder> (by default the current one) holds packs/<Pack>/, each pack as it
is installed. It runs before a pull request is merged, and what it writes
is committed with it; it also shows an author what would be refused.

A pack is refused, and the script stops, when:
  - its folder name has anything but letters, digits, '_' and '-';
  - pack.toml has no version, or no license (an SPDX identifier such as
    CC0-1.0 or GPL-3.0-or-later), or the licence's text is not in the pack
    as LICENSE.txt or LICENSE.md;
  - it has a hidden file, or a file a pack does not have (pack.toml, GLSL,
    OGG, WAV, text: .toml .frag .comp .glsl .ogg .wav .txt .md);
  - an image is not a PNG directly in screenshots/, there are more than 5,
    or one is over 4 MB, smaller than 1280 x 720, bigger than 3840 x 2160,
    or outside 4:3 to 21:9 in shape;
  - with --prisma-check, Prisma's prisma_check finds passes that do not
    compile (it needs a graphics card: run it on a desktop).

For each screenshot it writes a thumbnail, 480 x 270 cut from its middle, to
<folder>/thumbnails/<Pack>/ (rebuilt every time): the launcher shows those
and downloads a whole screenshot only when the player opens it. Nothing is
written unless every pack passes.

Needs Pillow (pip install pillow). The folder also serves as a local
source for Prisma's launcher ([debug] packs_source in prisma.ini).
"""
import argparse
import hashlib
import io
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("make_packs_index.py needs Pillow: pip install pillow")

ALLOWED = {".toml", ".frag", ".comp", ".glsl", ".ogg", ".wav", ".txt", ".md"}
LICENSE_FILES = ("LICENSE.txt", "LICENSE.md")
MAX_SCREENSHOTS = 5
MAX_SCREENSHOT_BYTES = 4 << 20
MIN_SIZE = (1280, 720)
MAX_SIZE = (3840, 2160)
MIN_ASPECT, MAX_ASPECT = 4 / 3, 21 / 9
THUMB_SIZE = (480, 270)
MAX_THUMB_BYTES = 512 << 10


def refuse(why):
    sys.exit("refused: " + why)


def is_screenshot(rel):
    parts = rel.split("/")
    return len(parts) == 2 and parts[0] == "screenshots" and parts[1].lower().endswith(".png")


def quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def entry(data, name):
    return f'    "{hashlib.sha256(data).hexdigest()} {len(data)} {name}",'


def thumbnail(path, where):
    """The checked screenshot's thumbnail, as PNG bytes"""
    with Image.open(path) as im:
        if im.format != "PNG":
            refuse(f"{where}: not a PNG image")
        w, h = im.size
        if w < MIN_SIZE[0] or h < MIN_SIZE[1]:
            refuse(f"{where}: {w} x {h}, smaller than {MIN_SIZE[0]} x {MIN_SIZE[1]}")
        if w > MAX_SIZE[0] or h > MAX_SIZE[1]:
            refuse(f"{where}: {w} x {h}, bigger than {MAX_SIZE[0]} x {MAX_SIZE[1]}")
        if not MIN_ASPECT - 0.01 <= w / h <= MAX_ASPECT + 0.01:
            refuse(f"{where}: {w} x {h} has a shape outside 4:3 to 21:9")
        # The middle, 16:9, as the launcher shows every thumbnail
        tw = min(w, h * 16 // 9)
        th = min(h, w * 9 // 16)
        left, top = (w - tw) // 2, (h - th) // 2
        small = im.convert("RGB").crop((left, top, left + tw, top + th)).resize(THUMB_SIZE, Image.LANCZOS)
    out = io.BytesIO()
    small.save(out, "PNG", optimize=True)
    data = out.getvalue()
    if len(data) > MAX_THUMB_BYTES:
        refuse(f"{where}: its thumbnail is over {MAX_THUMB_BYTES >> 10} KB")
    return data


def check_compiles(prisma_check, pack):
    result = subprocess.run([str(prisma_check), str(pack)], capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
        refuse(f"{pack.name}: prisma_check found errors (above)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", type=Path, nargs="?", default=Path("."))
    ap.add_argument("--prisma-check", type=Path, metavar="PATH",
                    help="Prisma's prisma_check (prisma_check.exe): compile every pack's passes")
    args = ap.parse_args()
    if args.prisma_check and not args.prisma_check.is_file():
        sys.exit(f"{args.prisma_check} does not exist")

    out = ["# Written by make_packs_index.py: do not edit by hand", "format = 1"]
    packs_root = args.folder / "packs"
    packs = sorted(p for p in packs_root.iterdir() if p.is_dir()) if packs_root.is_dir() else []
    thumbs = {}  # pack -> [(name, bytes)]
    for pack in packs:
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", pack.name):
            refuse(f"{pack.name}: a pack's folder takes letters, digits, '_' and '-' only")
        if not (pack / "pack.toml").is_file():
            refuse(f"{pack.name}: no pack.toml")
        try:
            manifest = tomllib.loads((pack / "pack.toml").read_text(encoding="utf-8"))
        except tomllib.TOMLDecodeError as e:
            refuse(f"{pack.name}/pack.toml: {e}")
        for key, example in (("version", 'version = "1.0"'), ("license", 'license = "CC0-1.0" (an SPDX identifier)')):
            if not str(manifest.get(key, "")).strip():
                refuse(f"{pack.name}/pack.toml: {key} is missing, before any [table], e.g. {example}")
        if not any((pack / f).is_file() for f in LICENSE_FILES):
            refuse(f"{pack.name}: the licence's text is not in the pack ({' or '.join(LICENSE_FILES)})")

        lines = []
        thumbs[pack.name] = []
        for f in sorted(p for p in pack.rglob("*") if p.is_file()):
            rel = f.relative_to(pack).as_posix()
            where = f"{pack.name}/{rel}"
            if any(part.startswith(".") for part in rel.split("/")):
                refuse(f"{where}: a hidden file")
            if f.suffix.lower() == ".png":
                if not is_screenshot(rel):
                    refuse(f"{where}: images go in screenshots/ (PNG, without subfolders)")
                if f.stat().st_size > MAX_SCREENSHOT_BYTES:
                    refuse(f"{where}: a screenshot over {MAX_SCREENSHOT_BYTES >> 20} MB")
                thumbs[pack.name].append((f.name, thumbnail(f, where)))
            elif f.suffix.lower() not in ALLOWED:
                refuse(f"{where}: not pack data")
            lines.append(entry(f.read_bytes(), rel))
        if len(thumbs[pack.name]) > MAX_SCREENSHOTS:
            refuse(f"{pack.name}: {len(thumbs[pack.name])} screenshots, {MAX_SCREENSHOTS} at most")
        if args.prisma_check:
            check_compiles(args.prisma_check, pack)

        out += ["", f"[packs.{pack.name}]"]
        for key, value in (("name", manifest.get("name", pack.name)), ("version", manifest["version"]),
                           ("author", manifest.get("author", "")), ("license", manifest["license"]),
                           ("description", manifest.get("description", ""))):
            out.append(f"{key} = {quote(str(value))}")
        out += ["files = ["] + lines + ["]"]
        if thumbs[pack.name]:
            out += ["thumbnails = ["] + [entry(data, name) for name, data in thumbs[pack.name]] + ["]"]

    # Every pack passed: the thumbnails and the index
    thumbs_root = args.folder / "thumbnails"
    shutil.rmtree(thumbs_root, ignore_errors=True)
    for name, files in thumbs.items():
        for file, data in files:
            (thumbs_root / name).mkdir(parents=True, exist_ok=True)
            (thumbs_root / name / file).write_bytes(data)
    (args.folder / "index.toml").write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{len(packs)} pack(s), {sum(len(v) for v in thumbs.values())} thumbnail(s): index.toml written")


if __name__ == "__main__":
    main()
