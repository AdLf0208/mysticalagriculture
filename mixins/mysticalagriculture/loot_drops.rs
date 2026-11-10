// Runs at the head of `Game::native_loot_drops` (API 75): a broken inferium
// crop drops the jar's essence and seeds, read from the farmland under it.
fn observe_loot_drops(
    game: &mut crate::game::Game<'_>,
    context: &crate::game::native_hooks::NativeLootDrops<'_>,
    drops: &mut Vec<horizon_client::items::ItemStack>,
) {
    crate::game::mysticalagriculture_state::on_loot_drops(game, context, drops);
}
