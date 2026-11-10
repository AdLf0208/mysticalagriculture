#!/usr/bin/env bash
# In-game check for Mystical Agriculture slice 1: the inferium crop/essence
# loop, Minecraft 26.3 on the campaign pin 1d63e0a5.
#
# Default run (offscreen renderer, The End, our built game with the native
# bundle + `--dev-mod content`):
#   1. the content mod loads and the crop binds age 0..7;
#   2. inferium seeds plant an age-0 crop on farmland (the item's
#      `place_block`); a stick on farmland places nothing;
#   3. growth is the pin's random tick: with `random_tick_speed 0` the same
#      crops do not change, then with the speed up they advance stages;
#   4. bone meal is refused on our crop (age stays, one meal spent) while the
#      vanilla wheat control grows (the differential);
#   5. a survival break of an age-7 crop drops 1 essence + 1 seed, an age-0
#      crop drops a seed and no essence, and vanilla wheat drops its own items;
#   6. the shaped seeds recipe and the shapeless ingot recipe craft in a real
#      table, with wrong-ingredient controls staying empty;
#   7. unknown ids are refused.
#
# NEGATIVE=1 keeps the scenario but expects the age-0 crop to drop essence:
# the run MUST fail, proving the drop assertion is not vacuous.
#
# Default run (EMBEDDED=0): the game loads `content/` as a dev mod.
# EMBEDDED=1: the game is launched with **only the native bundle** (no
# `--dev-mod`) and the content comes from the bundle's embedded copy
# (`mixins/<id>/data/…`, the AE2 pattern). The run also checks the file the
# helper wrote, byte for byte, against `content/mysticalagriculture.hmod`.
# CONTROL=1 (default with EMBEDDED) first launches the same binary with
# `.horizon-cache` unusable, where the crop and seed ids must be unknown.
# SELFTEST=1 flips the ripe-crop drop assertion (it must FAIL), proving the
# scenario can fail.
set -Eeuo pipefail

EMBEDDED=${EMBEDDED:-0}
CONTROL=${CONTROL:-$EMBEDDED}
SELFTEST=${SELFTEST:-0}

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/mysticalagriculture
SHARED=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
RES=${RES:-${HORIZON_RES:-${HORIZON_RES:-$HOME/.local/horizon-client/26.3}}}
SOCK=${SOCK:-/tmp/opencode/mysticalagriculture-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
MOD=mysticalagriculture
CROP=$MOD:inferium_crop
ESSENCE=$MOD:inferium_essence
SEEDS=$MOD:inferium_seeds
WORLD=MysticalAgricultureE2E
CONTROL_WORLD=MysticalAgricultureControl

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }

SCRATCH=$(mktemp -d "${E2E_TMP:-/tmp/opencode}"/mysticalagriculture-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
prop() { echo "$1" | grep -o "$2=[A-Za-z0-9_]*" | head -1 | cut -d= -f2 || true; }
assert_prop() {
    local state=$1 key=$2 want=$3 got
    got=$(prop "$state" "$key")
    [ "$got" = "$want" ] || fail "$state: $key is '$got', expected '$want'"
}
settle() {
    local last=-1 cur pend i
    for i in $(seq 1 60); do
        cur=$(ctl state | jq -r '.chunks // 0')
        pend=$(ctl state | jq -r '.streaming.queued // 0')
        [ "$cur" = "$last" ] && [ "$pend" = 0 ] && return 0
        last=$cur
        ctl wait 10 >/dev/null
    done
}
readback() { # x y z expected-block-id
    local x=$1 y=$2 z=$3 want=$4 st i
    for i in 1 2 3 4 5 6 7 8; do
        st=$(block_state "$x" "$y" "$z")
        case "$st" in "$want"*) echo "$st"; return 0 ;; esac
        ctl wait 5 >/dev/null
    done
    echo "$st"
}
age_at() { prop "$(block_state "$1" "$2" "$3")" age; }

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "${KEEP:-0}" = 1 ]; then
        echo "kept scratch: $SCRATCH" >&2
    else
        rm -rf "$SCRATCH" || true
    fi
    # Last line of every run: `check-e2e-logs.py` reads it as the verdict.
    echo "EXIT:$status"
}
trap cleanup EXIT

launch() { # launch [WORLD]
    local world=${1:-$WORLD}
    rm -f "$SOCK"
    local args=(--game "$GAME" --world "$world" --seed 20261108 --creative --offscreen --wait
                --game-dir "$SCRATCH/game" --resources "$RES" --render-distance 4)
    if [ "$EMBEDDED" = 1 ]; then
        echo "  launch: no --dev-mod; the bundle carries its own content" >&2
    else
        args+=(--dev-mod "$PORT/content")
    fi
    "$CTL" --socket "$SOCK" launch "${args[@]}"
    ctl wait-ready 180
    if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
        ctl logs --lines 4000 | grep "content mods not loaded" >&2
        fail "the content mod did not load"
    fi
    echo "content mod loaded (no 'content mods not loaded')"
}

arena() {
    say "The End arena: stone floor at 119, a 7x5 wet-farmland plot at 120, glowstone ceiling"
    end "forceload add 24 0 64 16"
    end "fill 24 119 0 64 119 16 minecraft:stone"
    end "fill 40 120 2 46 120 6 minecraft:farmland[moisture=7]"
    # A stone-ringed water source keeps every plot cell within farmland's 4-block
    # water scan, so a random tick never dries or reverts the farmland.
    end "setblock 43 120 4 minecraft:water"
    end "setblock 42 120 4 minecraft:stone"
    end "setblock 44 120 4 minecraft:stone"
    end "setblock 43 120 3 minecraft:stone"
    end "setblock 43 120 5 minecraft:stone"
    # The End has no skylight; wheat needs light 9, so a glowstone ceiling three
    # blocks up supplies 12 at every crop cell.
    end "fill 38 124 0 48 124 8 minecraft:glowstone"
    end "tp @s 43.5 121 12.5"
    end "difficulty peaceful"
    end "gamerule spawn_mobs false"
    end "gamerule random_tick_speed 0"
    for _ in $(seq 1 30); do
        [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] && break
        ctl wait 10
    done
    [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] \
        || fail "the player is in $(ctl state | jq -r '.dimension'), not The End"
    ctl wait-ready 180 >/dev/null
    ctl wait 20 >/dev/null
    settle
    echo "player in the_end at $(ctl state | jq -c '.player.position'), chunks settled"
}

# EMBEDDED=1: the bundle must have written its content out at startup, byte for
# byte the delivered content mod.
embedded_content_check() {
    local cache=$SCRATCH/.horizon-cache/$MOD-embedded-content.hmod
    [ -f "$cache" ] || fail "the bundle did not write its embedded content to $cache"
    cmp -s "$cache" "$PORT/content/$MOD.hmod" \
        || fail "the embedded content differs from content/$MOD.hmod"
    echo "  embedded content: $(wc -c < "$cache" | tr -d ' ') B at $cache, identical to content/$MOD.hmod"
}

# The control for EMBEDDED=1: the same binary (every hook is in it) with the
# embedded content made unavailable — `.horizon-cache` is a plain file, so the
# helper can neither compare nor write its content file and falls back to
# `Continue`. Both ids must then be unknown; if they resolve, the run proves
# nothing about the embedded file.
control_leg() {
    echo "== control: the same game with no embedded content file =="
    rm -rf "$SCRATCH/.horizon-cache"
    : > "$SCRATCH/.horizon-cache"
    launch "$CONTROL_WORLD"
    arena
    ctl command "item replace entity @s hotbar.0 with $SEEDS 1" >/dev/null || true
    ctl wait 4 >/dev/null
    ctl inventory | jq -e --arg i "$SEEDS" '[.hotbar[], .main[] | select(.item == $i)] | length == 0' >/dev/null \
        || fail "the control game has the seed item, so the content came from somewhere else"
    ctl command "execute in minecraft:the_end run setblock 44 121 2 $CROP" >/dev/null || true
    ctl wait 4 >/dev/null
    local name
    name=$(block_name 44 121 2)
    [ "$name" = "minecraft:air" ] || fail "the control game holds $name, so the crop block id was known"
    [ -f "$SCRATCH/.horizon-cache" ] || fail "the control's .horizon-cache was replaced: the helper wrote its content"
    echo "  without the embedded file: no seed item, the crop block stayed $name"
    ctl quit >/dev/null 2>&1 || true
    sleep 2
    rm -f "$SCRATCH/.horizon-cache"
}

# --------------------------------------------------------------- launch
say "launch (offscreen renderer, The End, $( [ "$EMBEDDED" = 1 ] && echo 'native bundle only (embedded content)' || echo 'native bundle + content --dev-mod' ))"
if [ "$CONTROL" = 1 ]; then control_leg; fi
launch
if [ "$EMBEDDED" = 1 ]; then embedded_content_check; fi
arena

# --------------------------------------------------------------- registry
say "the inferium crop binds every age 0..7"
# A second wet-farmland band for the age read-back (random ticks are off, so it
# only has to be support).
end "fill 28 120 8 35 120 8 minecraft:farmland[moisture=7]"
for age in 0 1 2 3 4 5 6 7; do
    x=$((28 + age))
    ctl setblock "$x" 121 8 "$CROP[age=$age]" >/dev/null || fail "setblock age $age"
done
ctl wait 5
for age in 0 1 2 3 4 5 6 7; do
    x=$((28 + age))
    assert_prop "$(readback "$x" 121 8 "$CROP")" age "$age"
done
echo "crop PASS: ages 0..7 read back"

# --------------------------------------------------------------- planting
say "inferium seeds plant an age-0 crop on farmland; a stick places nothing"
plant() { # x z item expected-block
    ctl command "clear @s" >/dev/null
    ctl give "$3" 4 >/dev/null || fail "cannot give $3"
    ctl wait 3 >/dev/null
    ctl select "$3" >/dev/null || fail "cannot select $3"
    ctl tp "$1.5" 121 "$2.5" >/dev/null
    ctl wait 4 >/dev/null
    ctl look 0 60 >/dev/null
    ctl wait 4 >/dev/null
    ctl interact "$1" 120 "$2" up >/dev/null || fail "cannot click farmland with $3"
    ctl wait 5 >/dev/null
    readback "$1" 121 "$2" "$4"
}
planted=$(plant 40 2 "$SEEDS" "$CROP")
echo "$SEEDS on farmland -> $planted"
case "$planted" in "$CROP"*) ;; *) fail "the seed did not place its crop: $planted" ;; esac
assert_prop "$planted" age 0
planted_stick=$(plant 41 2 minecraft:stick minecraft:air)
[ "$(block_name 41 121 2)" = minecraft:air ] || fail "a stick placed $(block_name 41 121 2)"
echo "seed planting PASS: inferium_crop[age=0] placed; a stick places nothing"

# ---------------------------------------------------------------- growth
say "growth is the random tick: speed 0 keeps the stages, then the crops advance"
ctl setblock 42 121 2 "$CROP[age=3]" >/dev/null || fail "setblock growth crop"
ctl wait 5
a0=$(age_at 40 121 2)
b0=$(age_at 42 121 2)
[ "$a0" = 0 ] && [ "$b0" = 3 ] || fail "growth crops start at $a0/$b0, expected 0/3"
for _ in $(seq 1 10); do ctl wait 20 >/dev/null; done
ctl wait 100 >/dev/null
a1=$(age_at 40 121 2)
b1=$(age_at 42 121 2)
[ "$a1" = 0 ] && [ "$b1" = 3 ] \
    || fail "with random_tick_speed 0 the crops changed: $a0->$a1, $b0->$b1"
echo "control PASS: random_tick_speed 0 keeps ages $a0 and $b0 for 300 ticks"
end "gamerule random_tick_speed 400"
grown=0
for i in $(seq 1 60); do
    ctl wait 20 >/dev/null
    # keep the plot wet even if the engine's drying differs from vanilla's
    end "fill 40 120 2 46 120 6 minecraft:farmland[moisture=7]" >/dev/null 2>&1 || true
    a2=$(age_at 40 121 2)
    b2=$(age_at 42 121 2)
    if [ -n "$a2" ] && [ -n "$b2" ] && [ "$a2" -gt "$a0" ] && [ "$b2" -gt "$b0" ]; then
        grown=$i; break
    fi
done
a2=$(age_at 40 121 2)
b2=$(age_at 42 121 2)
[ "$grown" -gt 0 ] || fail "the crops did not advance under random ticks ($a0->$a2, $b0->$b2)"
echo "growth PASS after $((grown * 20)) ticks: age 0->$a2 and age 3->$b2"
# Let the planted crop reach 7 so the harvest phase reads a real growth result.
for _ in $(seq 1 40); do
    a3=$(age_at 40 121 2)
    [ "$a3" = 7 ] && break
    ctl wait 20 >/dev/null
    end "fill 40 120 2 46 120 6 minecraft:farmland[moisture=7]" >/dev/null 2>&1 || true
done
a3=$(age_at 40 121 2)
echo "the planted crop reached age $a3 of 7 under random ticks"
end "gamerule random_tick_speed 0"

# --------------------------------------------------------------- bone meal
say "bone meal is refused on our crop; the vanilla wheat control grows"
ctl command "gamemode survival @s" >/dev/null
ctl setblock 40 121 3 "$CROP[age=0]" >/dev/null || fail "setblock meal crop"
ctl setblock 41 121 3 "minecraft:wheat[age=0]" >/dev/null || fail "setblock wheat control"
ctl wait 5
[ "$(block_name 40 121 3)" = "$CROP" ] || fail "the meal crop did not place"
[ "$(block_name 41 121 3)" = "minecraft:wheat" ] || fail "the wheat control did not place"
ctl command "clear @s" >/dev/null
ctl give minecraft:bone_meal 8 >/dev/null || fail "give bone meal"
ctl wait 3
ctl select minecraft:bone_meal >/dev/null || fail "select bone meal"
# A right-click at the crosshair (look-at the low part of the crop, then
# use-item) is how the probe applied the meal reliably to a short crop.
meal() { # x z
    ctl tp "$1.5" 121 "$2.5" >/dev/null
    ctl wait 4
    ctl look-at "$1.5" 121.1 "$2.5" >/dev/null
    ctl wait 3
    ctl use-item >/dev/null || fail "use-item on $1,$2 failed"
    ctl wait 10
}
before=$(ctl state | jq -r '.held.count // 0')
meal 40 3
after=$(ctl state | jq -r '.held.count // 0')
ours=$(age_at 40 121 3)
[ "$ours" = 0 ] || fail "bone meal grew our crop to age $ours"
[ "$after" -lt "$before" ] || fail "bone meal was not spent on our crop ($before -> $after)"
echo "our crop PASS: age 0 after bone meal, meal $before -> $after"
# The control: vanilla wheat on the same plot must grow, so the refusal is ours.
meal 41 3
wheat=$(age_at 41 121 3)
[ -n "$wheat" ] && [ "$wheat" -gt 0 ] || fail "the vanilla wheat control did not grow (age $wheat)"
echo "wheat control PASS: bone meal grew vanilla wheat to age $wheat"

# ---------------------------------------------------------------- harvest
say "a survival break drops the jar's loot: ripe = essence + seed, young = seed only"
ctl command "gamemode survival @s" >/dev/null
break_crop() { # x z
    ctl command "clear @s" >/dev/null
    ctl give minecraft:iron_hoe 1 >/dev/null || fail "give hoe"
    ctl wait 3 >/dev/null
    ctl select minecraft:iron_hoe >/dev/null
    ctl tp "$1.5" 121 "$2.5" >/dev/null
    ctl wait 4 >/dev/null
    ctl break "$1" 121 "$2"
}
ctl setblock 42 121 3 "$CROP[age=7]" >/dev/null || fail "setblock ripe crop"
ctl setblock 44 121 5 "$CROP[age=0]" >/dev/null || fail "setblock young crop"
ctl wait 6
broken=$(break_crop 42 3) || fail "cannot break the ripe crop"
echo "$broken" | jq -c '{scenario:"age=7",block,block_before,drops}'
ripe=$(echo "$broken" | jq -r --arg i "$ESSENCE" '.drops[$i] // 0')
ripe_seeds=$(echo "$broken" | jq -r --arg i "$SEEDS" '.drops[$i] // 0')
if [ "$SELFTEST" = 1 ]; then
    echo "(selftest: asserting the age-7 crop dropped no essence)"
    [ "$ripe" = 0 ] || fail "the age-7 crop dropped $ripe essence (selftest expects 0)"
else
    [ "$ripe" -ge 1 ] || fail "the age-7 crop dropped $ripe essence"
fi
[ "$ripe_seeds" -ge 1 ] || fail "the age-7 crop dropped $ripe_seeds seeds"
broken=$(break_crop 44 5) || fail "cannot break the young crop"
echo "$broken" | jq -c '{scenario:"age=0",block,block_before,drops}'
young=$(echo "$broken" | jq -r --arg i "$ESSENCE" '.drops[$i] // 0')
young_seeds=$(echo "$broken" | jq -r --arg i "$SEEDS" '.drops[$i] // 0')
want_young=0
[ "$NEGATIVE" = 1 ] && want_young=1
[ "$young" = "$want_young" ] || fail "the age-0 crop dropped $young essence, expected $want_young"
[ "$young_seeds" -ge 1 ] || fail "the age-0 crop dropped $young_seeds seeds"
# The differential: vanilla wheat on the same plot drops wheat + seeds.
ctl setblock 45 121 5 "minecraft:wheat[age=7]" >/dev/null || fail "setblock wheat harvest"
ctl wait 6
broken=$(break_crop 45 5) || fail "cannot break the wheat control"
echo "$broken" | jq -c '{scenario:"wheat age=7",block,block_before,drops}'
wheat_item=$(echo "$broken" | jq -r '.drops["minecraft:wheat"] // 0')
[ "$wheat_item" -ge 1 ] || fail "the vanilla wheat control dropped $wheat_item wheat"
ctl command "gamemode creative @s" >/dev/null
echo "loot PASS: age 7 -> $ripe essence + $ripe_seeds seeds; age 0 -> $young essence + $young_seeds seeds; wheat -> $wheat_item"

# ---------------------------------------------------------------- recipes
say "crafting: inferium seeds (shaped) and inferium ingot (shapeless)"
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" 30 120 14 || fail "craft_check.py failed"

# ---------------------------------------------------------------- controls
say "unknown ids are refused"
if ctl give "$MOD:not_an_item" 1 >/dev/null 2>&1; then
    fail "give $MOD:not_an_item succeeded"
fi
ctl setblock 60 121 12 "$MOD:not_a_block" >/dev/null 2>&1 || true
[ "$(block_name 60 121 12)" = minecraft:air ] \
    || fail "$MOD:not_a_block became $(block_name 60 121 12)"
echo "unknown ids refused"

echo "PASS: the inferium crop binds ages 0..7; seeds planted an age-0 crop and a stick did not; random_tick_speed 0 held the stages while random ticks advanced 0->$a2 and 3->$b2 (and the planted crop to age $a3); bone meal was refused on our crop but grew vanilla wheat; a ripe crop dropped $ripe essence + $ripe_seeds seeds and a young one $young essence + $young_seeds seeds while vanilla wheat dropped $wheat_item wheat; the shaped seeds recipe and shapeless ingot recipe crafted with empty wrong-ingredient controls; unknown ids were refused"
exit 0
