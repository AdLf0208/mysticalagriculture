# Licence notice — Mystical Agriculture

This port carries the original mod's assets and data, and rewrites its behaviour
in Rust (or, for a data-tier port, declares its blocks from the same data). The
original licence and copyright notices are reproduced verbatim in
[LICENSE](LICENSE).

## Where the licence was read

- The pack jar `MysticalAgriculture-1.21.1-8.0.29.jar` (kept at
  `_shared/carry-work/mysticalagriculture/`) declares `license="MIT"` in
  `META-INF/neoforge.mods.toml` and carries no licence file.
- The MIT text and `Copyright (c) 2018 BlakeBr0` come from the upstream
  repository's `LICENSE`
  (<https://github.com/BlakeBr0/MysticalAgriculture>).

## The port

- Original: Mystical Agriculture 8.0.29 by BlakeBr0 — MIT.
- Licence: **MIT**
- Port to Horizon by AdLf0208: the Rust runtime, the Horizon declarations and the
  build/verification tooling in this repository.
- No Mojang file is included. The carried files are the mod's own assets and
  data; `data/minecraft/tags/…` files only add this mod's ids to vanilla tags.
