// Runs at the head of `GameLevel::native_is_valid_bonemeal_target` (API 72):
// a young Mystical Agriculture crop is a valid target (so the meal is spent),
// but `is_bonemeal_success` below always refuses the growth.
fn observe_bonemeal_target(
    level: &crate::game::GameLevel<'_>,
    state: BlockStateId,
    valid: &mut Option<bool>,
) {
    crate::game::mysticalagriculture_state::on_bonemeal_target(level, state, valid);
}
