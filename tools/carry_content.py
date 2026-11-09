#!/usr/bin/env python3
"""Carry the inferium-tier slice of Mystical Agriculture 8.0.29 into content/.

The jar is the ATM10 one, resolved by SHA-1 from the pack's Crash Assistant
export (see ../SOURCE.md). Asset bytes are copied verbatim; the few data files
that 26.3 spells differently (item definitions, recipes, loot) are written from
the jar's own values, and the block/item declarations name vanilla templates.

Run: python3 tools/carry_content.py [--jar PATH] [--check]
  --check  compare the files on disk with what the carry would write, exit 1
           on a difference (no writes).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JAR = (
    ROOT.parent / "_shared/carry-work/mysticalagriculture"
    / "MysticalAgriculture-1.21.1-8.0.29.jar"
)
JAR_SHA1 = "4a774506f65899683aa40b92fec972ddcc4fdc4f"
MOD = "mysticalagriculture"

# Bytes copied unchanged from the jar.
VERBATIM = [
    "assets/mysticalagriculture/blockstates/inferium_crop.json",
    *(
        f"assets/mysticalagriculture/models/block/mystical_resource_crop_{age}.json"
        for age in range(8)
    ),
    "assets/mysticalagriculture/models/block/inferium_crop.json",
    "assets/mysticalagriculture/models/item/inferium_seeds.json",
    "assets/mysticalagriculture/models/item/inferium_essence.json",
    "assets/mysticalagriculture/models/item/inferium_ingot.json",
    "assets/mysticalagriculture/models/item/prosperity_ingot.json",
    *(
        f"assets/mysticalagriculture/textures/block/mystical_resource_crop_{age}.png"
        for age in range(8)
    ),
    "assets/mysticalagriculture/textures/block/flower/inferium_flower.png",
    "assets/mysticalagriculture/textures/item/inferium_essence.png",
    "assets/mysticalagriculture/textures/item/inferium_ingot.png",
    "assets/mysticalagriculture/textures/item/prosperity_ingot.png",
    "assets/mysticalagriculture/textures/item/seeds/inferium_seeds.png",
]

ITEMS = ["inferium_seeds", "inferium_essence", "inferium_ingot", "prosperity_ingot"]

# Items the jar's own models/lang name, with the template each copies. Seeds use
# a plain item template and place their crop through `place_block`; the two
# materials are plain 64-stack items.
ITEM_DECLS = {
    "inferium_seeds": {
        "template": "minecraft:stick",
        "place_block": "mysticalagriculture:inferium_crop",
    },
    "inferium_essence": {"template": "minecraft:iron_nugget"},
    "inferium_ingot": {"template": "minecraft:iron_ingot"},
    "prosperity_ingot": {"template": "minecraft:iron_ingot"},
}

LANG = {
    "block.mysticalagriculture.inferium_crop": "Inferium Crop",
    "item.mysticalagriculture.inferium_seeds": "Inferium Seeds",
    "item.mysticalagriculture.inferium_essence": "Inferium Essence",
    "item.mysticalagriculture.inferium_ingot": "Inferium Ingot",
    "item.mysticalagriculture.prosperity_ingot": "Prosperity Ingot",
}

MANIFEST = f"""\
# Port-owned content mod for the Mystical Agriculture 1.21.1-8.0.29 slice:
# the inferium crop, its seeds and essence, and the essence-to-ingot recipe.
# Textures, models and blockstate are the upstream mod's own MIT assets, read
# from the exact ATM10 jar (see ../SOURCE.md). Local-only until publishing is
# approved (see ../LICENSE and ../notes.md).
id = "{MOD}"
name = "Mystical Agriculture"
version = "1.21.1-8.0.29"
description = "Slice 1: the inferium crop, essence and ingot"
authors = ["BlakeBr0"]
api = "0.2"
side = "both"
capabilities = ["registries"]
"""

CROP_BLOCK = {
    "template": "minecraft:wheat",
    "item": False,
    "properties": {"hardness": 0.0},
    # MysticalCropBlock.SHAPE: a 4-pixel-high box for every age, no collision
    # (vanilla wheat's outline grows with the age; the jar's does not).
    "shapes": {"default": [[0.0, 0.0, 0.0, 1.0, 0.25, 1.0]]},
    "collision_shapes": {"default": []},
}

INFERIUM_SEEDS_RECIPE = {
    "type": "minecraft:crafting_shaped",
    "pattern": ["EEE", "ESE", "EEE"],
    "key": {
        "E": f"{MOD}:inferium_essence",
        "S": "minecraft:wheat_seeds",
    },
    "result": {"id": f"{MOD}:inferium_seeds", "count": 1},
}

INFERIUM_INGOT_RECIPE = {
    "type": "minecraft:crafting_shapeless",
    "ingredients": [
        f"{MOD}:prosperity_ingot",
        f"{MOD}:inferium_essence",
        f"{MOD}:inferium_essence",
    ],
    "result": {"id": f"{MOD}:inferium_ingot", "count": 1},
}

# The jar's getDrops for a crop on plain farmland: one seed at every age, and
# one essence plus one seed at age 7. The native half replaces this with the
# farmland-aware formula (the table is the content-only fallback).
CROP_LOOT = {
    "type": "minecraft:block",
    "random_sequence": f"{MOD}:blocks/inferium_crop",
    "pools": [
        {
            "rolls": 1.0,
            "bonus_rolls": 0.0,
            "entries": [
                {
                    "type": "minecraft:alternatives",
                    "children": [
                        {
                            "type": "minecraft:item",
                            "name": f"{MOD}:inferium_essence",
                            "conditions": [
                                {
                                    "type": "minecraft:block_state_property",
                                    "block": f"{MOD}:inferium_crop",
                                    "properties": {"age": "7"},
                                }
                            ],
                        },
                        {"type": "minecraft:item", "name": f"{MOD}:inferium_seeds"},
                    ],
                }
            ],
        },
        {
            "rolls": 1.0,
            "bonus_rolls": 0.0,
            "conditions": [
                {
                    "type": "minecraft:block_state_property",
                    "block": f"{MOD}:inferium_crop",
                    "properties": {"age": "7"},
                }
            ],
            "entries": [{"type": "minecraft:item", "name": f"{MOD}:inferium_seeds"}],
        },
    ],
}


def generated() -> dict[str, bytes]:
    """Every file the carry writes beyond the verbatim jar bytes."""
    files: dict[str, bytes] = {}
    files[f"content/horizon-mod.toml"] = MANIFEST.encode()
    for item in ITEMS:
        files[f"content/assets/{MOD}/items/{item}.json"] = _json(
            {"model": {"type": "minecraft:model", "model": f"{MOD}:item/{item}"}}
        )
    files[f"content/assets/{MOD}/lang/en_us.json"] = _json(LANG)
    files[f"content/data/{MOD}/horizon/block/inferium_crop.json"] = _json(CROP_BLOCK)
    for item, decl in ITEM_DECLS.items():
        files[f"content/data/{MOD}/horizon/item/{item}.json"] = _json(decl)
    files[f"content/data/{MOD}/recipe/inferium_seeds.json"] = _json(INFERIUM_SEEDS_RECIPE)
    files[f"content/data/{MOD}/recipe/inferium_ingot.json"] = _json(INFERIUM_INGOT_RECIPE)
    files[f"content/data/{MOD}/loot_table/blocks/inferium_crop.json"] = _json(CROP_LOOT)
    return files


def _json(value: object) -> bytes:
    return (json.dumps(value, indent=2) + "\n").encode()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jar", type=Path, default=DEFAULT_JAR)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    digest = hashlib.sha1(args.jar.read_bytes()).hexdigest()
    if digest != JAR_SHA1:
        print(f"{args.jar}: SHA-1 {digest} is not the ATM10 file {JAR_SHA1}", file=sys.stderr)
        return 1

    wanted = {**generated()}
    with zipfile.ZipFile(args.jar) as jar:
        for name in VERBATIM:
            wanted[f"content/{name}"] = jar.read(name)

    changed = 0
    for name, data in sorted(wanted.items()):
        path = ROOT / name
        current = path.read_bytes() if path.exists() else None
        if current == data:
            continue
        changed += 1
        print(("would write " if args.check else "write ") + name)
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    print(
        f"{len(wanted)} files, {changed} {'pending' if args.check else 'written'}"
        f" (jar sha1 {digest})"
    )
    return 1 if args.check and changed else 0


if __name__ == "__main__":
    raise SystemExit(main())
