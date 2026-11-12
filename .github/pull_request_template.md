<!-- SPDX-FileCopyrightText: 2026 Flay Krunegan -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

## Pack

- Name and folder:
- Version:
- New pack or new version:
- Licence (SPDX):

## Checklist

- [ ] The pull request adds or replaces one folder under `packs/` and
      changes nothing else (`index.toml` and `thumbnails/` are written when
      it is merged).
- [ ] `pack.toml` sets `api`, `name`, `version`, `author`, `description`
      and `license`.
- [ ] The licence's text is in the pack as `LICENSE.txt` or `LICENSE.md`,
      and it allows the pack to be copied and redistributed unchanged.
- [ ] `python make_packs_index.py` reports no problem.
- [ ] `prisma_check` compiles the pack without errors.
- [ ] The pack was tried in Luanti 5.17.0 with the latest Prisma release.
- [ ] The screenshots, if any, show this pack.