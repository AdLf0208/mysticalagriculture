# Mystical Agriculture — Horizon port

A port of [Mystical Agriculture](https://github.com/BlakeBr0/MysticalAgriculture)
by BlakeBr0 for Horizon. This first slice is the inferium crop/essence loop:

- Craft inferium seeds (8 essence plus 1 wheat seed) and plant them on farmland;
  the crop grows through vanilla wheat's eight ages on random ticks and needs
  light 9 to survive.
- Harvest a mature crop for essence and seeds; the drop depends on whether the
  farmland is still there, as upstream. Bone meal is refused.
- Craft an inferium ingot from a prosperity ingot and 2 essence.

The machines, the other crops, the armour and the essences above inferium are
later slices. MIT — original copyright and licence notices are kept in the port
repository; see LICENSE and LICENSE-NOTICE.md there.

**Original:** [Mystical Agriculture](https://github.com/BlakeBr0/MysticalAgriculture) 8.0.29 by
BlakeBr0, **MIT**. The original
copyright and licence notices are kept in [LICENSE](LICENSE), and
[LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each was read from.

**Horizon:** a port for [Horizon](https://github.com/horizon-rust/horizon), Minecraft:
Java Edition 26.3 rewritten in Rust. The exact Horizon and horizon-mixins
revisions this port builds against are pinned in `compatibility.json`.

## Install

1. Take `mysticalagriculture.hnmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-native-mods` folder — the game folder is the one
   holding `options.txt`.
3. Native mods are always on once installed; the first install shows a
   trust notice, and the launcher builds the mod for your game.

To try it without installing, start the game with
`--dev-mod mysticalagriculture.hnmod`.

## Build

The port is a native mod (`.hnmod`): carried content plus a Rust runtime and
source mixins.

```sh
cargo test --locked --offline                        # the pure runtime rules
python3 tools/horizon.py stage   --horizon <horizon-checkout>
python3 tools/horizon.py check   --horizon <horizon-checkout>
python3 tools/horizon.py test    --horizon <horizon-checkout>
python3 tools/horizon.py build   --horizon <horizon-checkout>   # rebuild the .hnmod
```

`tools/e2e.sh` is the in-game harness. It expects a campaign checkout
(`$CAMPAIGN_ROOT`), the shared pins under `ports/_shared/pins/`, and the
prepared 26.3 resources (`$HORIZON_RES`, default `.local/horizon-client/26.3`).

## Layout

`content/` is the shipped content; `mixins/mysticalagriculture/` holds the declarations and the runtime; `tools/` builds and verifies the port.

This is an unofficial port: Horizon is not affiliated with the original author.
The licence above is the original's and travels with every copy; see
[LICENSE](LICENSE) and [LICENSE-NOTICE.md](LICENSE-NOTICE.md).
