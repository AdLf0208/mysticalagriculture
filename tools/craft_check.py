#!/usr/bin/env python3
"""Craft the two inferium recipes in a real crafting table.

Called by tools/e2e.sh with the open game's control socket. The harness's
crafting grid is slots 100-108 row-major, result 200 (`ctl screen`). Cases:

  1. shaped `inferium_seeds`: eight essence around one wheat seed ->
     `mysticalagriculture:inferium_seeds` x1, and the stack reaches the
     inventory (the jar's `EEE/ESE/EEE` recipe);
  2. its control: a stick in the centre -> empty result;
  3. shapeless `inferium_ingot`: prosperity ingot + two essence ->
     `mysticalagriculture:inferium_ingot` x1;
  4. its control: wheat seeds instead of the essence -> empty result.

Exits 1 on the first mismatch.
"""
import json
import subprocess
import sys


def main():
    sock, ctl, x, y, z = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

    def run(*args):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True,
                             capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks=4):
        run("wait", str(ticks))

    def slots():
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]

    def find(item):
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"missing ingredient {item} in the inventory")

    def setup(items):
        try:
            run("close")
        except SystemExit:
            pass
        wait(5)
        run("setblock", x, y, z, "minecraft:air")
        run("setblock", x, y, z, "minecraft:crafting_table")
        wait(2)
        run("command", f"tp @s {float(x) - 0.5} {y} {float(z) + 0.5}")
        wait(3)
        run("command", "clear @s")
        for item, count in items:
            run("give", item, str(count))
        wait(3)
        run("interact", x, y, z)
        wait(5)

    def result():
        stack = [s for s in slots() if s["slot"] == 200]
        if not stack or not stack[0].get("item"):
            return None
        return stack[0]

    def place(item, targets):
        slot = find(item)
        run("click-slot", str(slot))
        wait(1)
        for target in targets:
            run("click-slot", str(target), "right")
            wait(1)
        run("click-slot", str(slot))
        wait(2)

    failures = []

    def check(label, items, placements, want_item, want_count, take=False):
        setup(items)
        for item, targets in placements:
            place(item, targets)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if not got or got.get("item") != want_item or got.get("count") != want_count:
            failures.append(f"{label}: expected {want_count} {want_item}, got {got}")
            return
        if take:
            run("click-slot", "200")
            wait(5)
            run("click-slot", "9")
            wait(3)
            made = run("inventory")["counts"].get(want_item, 0)
            if made < want_count:
                failures.append(
                    f"{label}: the crafted stack reached the inventory as {made}")

    def empty_control(label, items, placements):
        setup(items)
        for item, targets in placements:
            place(item, targets)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if got is not None:
            failures.append(f"{label}: control crafted {got['item']}")

    ring = [str(n) for n in (100, 101, 102, 103, 105, 106, 107, 108)]
    check(
        "8 essence + 1 wheat seed -> inferium_seeds",
        [("mysticalagriculture:inferium_essence", 8), ("minecraft:wheat_seeds", 1)],
        [
            ("mysticalagriculture:inferium_essence", ring),
            ("minecraft:wheat_seeds", ["104"]),
        ],
        "mysticalagriculture:inferium_seeds",
        1,
        take=True,
    )
    empty_control(
        "8 essence + 1 stick -> nothing",
        [("mysticalagriculture:inferium_essence", 8), ("minecraft:stick", 1)],
        [
            ("mysticalagriculture:inferium_essence", ring),
            ("minecraft:stick", ["104"]),
        ],
    )
    check(
        "1 prosperity ingot + 2 essence -> inferium_ingot",
        [("mysticalagriculture:prosperity_ingot", 1),
         ("mysticalagriculture:inferium_essence", 2)],
        [
            ("mysticalagriculture:prosperity_ingot", ["100"]),
            ("mysticalagriculture:inferium_essence", ["101", "102"]),
        ],
        "mysticalagriculture:inferium_ingot",
        1,
        take=True,
    )
    empty_control(
        "1 prosperity ingot + 2 wheat seeds -> nothing",
        [("mysticalagriculture:prosperity_ingot", 1), ("minecraft:wheat_seeds", 2)],
        [
            ("mysticalagriculture:prosperity_ingot", ["100"]),
            ("minecraft:wheat_seeds", ["101", "102"]),
        ],
    )

    run("close")
    wait(3)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
    print("recipe PASS: inferium_seeds (shaped) and inferium_ingot (shapeless); "
          "wrong-ingredient controls stay empty")


if __name__ == "__main__":
    main()
