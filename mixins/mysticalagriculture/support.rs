// Game-side glue for the inferium crop slice: the jar's `getDrops` formula and
// its bone-meal refusal. The pure rules live in `runtime.rs`.

use horizon_client::game::native_hooks::NativeLootDrops;
use horizon_client::items::ItemStack;
use horizon_core::random::RandomSource;
use horizon_world::registry::BlockStateId;

/// A broken block's drops are rolled (API 75): an inferium crop's stack comes
/// from the jar's `InferiumCropBlock.getDrops`, which reads the farmland under
/// it, not from the rolled table (the table is the content-only fallback).
pub(super) fn on_loot_drops(
    game: &mut crate::game::Game<'_>,
    context: &NativeLootDrops<'_>,
    drops: &mut Vec<ItemStack>,
) {
    let Some((pos, state)) = context.block else {
        return;
    };
    let Some(age) = crop_age(game, state) else {
        return;
    };
    let ground = ground_below(game, pos);
    let Some(random) = game.native_level_random(context.dimension) else {
        return;
    };
    let harvest = crate::game::mysticalagriculture::harvest(
        age,
        ground,
        crate::game::mysticalagriculture::SECONDARY_SEED_DROPS,
        || random.next_double(),
    );

    drops.clear();
    if harvest.essence > 0 {
        drops.push(ItemStack::new(
            crate::game::mysticalagriculture::ESSENCE,
            harvest.essence,
        ));
    }
    if harvest.seeds > 0 {
        drops.push(ItemStack::new(
            crate::game::mysticalagriculture::SEEDS,
            harvest.seeds,
        ));
    }
}

/// `MysticalCropBlock.isValidBonemealTarget`: a young crop is a target (the
/// meal is spent), a ripe one is not, as vanilla's `CropBlock` answers.
pub(super) fn on_bonemeal_target(
    level: &crate::game::GameLevel<'_>,
    state: BlockStateId,
    valid: &mut Option<bool>,
) {
    let Some(state) = level.registry.state(state) else {
        return;
    };
    if &*state.name != crate::game::mysticalagriculture::CROP {
        return;
    }
    let age = state
        .properties
        .get("age")
        .and_then(|age| age.parse::<u8>().ok())
        .unwrap_or(crate::game::mysticalagriculture::MAX_AGE);
    *valid = Some(!crate::game::mysticalagriculture::is_ripe(age));
}

/// `MysticalCropBlock.isBonemealSuccess` is always false (API 72): a meal on
/// an inferium crop never grows it, as in the jar.
pub(super) fn on_bonemeal_success(
    level: &crate::game::GameLevel<'_>,
    state: BlockStateId,
    success: &mut bool,
) {
    if level
        .registry
        .state(state)
        .is_some_and(|state| &*state.name == crate::game::mysticalagriculture::CROP)
    {
        *success = false;
    }
}

/// The crop's `age` when `state` is the inferium crop, else `None`.
fn crop_age(game: &crate::game::Game<'_>, state: BlockStateId) -> Option<u8> {
    let state = game.pack.assets.registry.state(state)?;
    if &*state.name != crate::game::mysticalagriculture::CROP {
        return None;
    }
    state.properties.get("age")?.parse().ok()
}

/// The block under the crop, as the drop rules read it. An unloaded cell or one
/// outside the world is plain ground.
fn ground_below(
    game: &crate::game::Game<'_>,
    [x, y, z]: [i32; 3],
) -> crate::game::mysticalagriculture::Ground {
    use crate::game::mysticalagriculture::Ground;

    let below = y - 1;
    let world = &game.world;
    if !(world.shape.min_y..world.shape.max_y()).contains(&below) || !world.loaded(x, z) {
        return Ground::Plain;
    }
    let Some(state) = game.pack.assets.registry.state(world.block(x, below, z)) else {
        return Ground::Plain;
    };
    Ground::from_block(&state.name)
}
