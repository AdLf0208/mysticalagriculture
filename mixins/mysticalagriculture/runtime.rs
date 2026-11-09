// The pure inferium crop/essence rules, read from Mystical Agriculture 8.0.29
// (`MysticalCropBlock.getDrops`, `InferiumCropBlock.getDrops`,
// `Crop.getSecondaryChance`, `CropTier`). This file is both the standalone
// Cargo library and the injected `game::mysticalagriculture` module; the game
// side glue lives in `support.rs`.

/// The inferium crop block this slice ships.
pub const CROP: &str = "mysticalagriculture:inferium_crop";
/// The essence the crop drops when ripe.
pub const ESSENCE: &str = "mysticalagriculture:inferium_essence";
/// The seed the crop drops at every age.
pub const SEEDS: &str = "mysticalagriculture:inferium_seeds";
/// Vanilla `CropBlock.MAX_AGE` for the wheat template (8 ages, 0 through 7).
pub const MAX_AGE: u8 = 7;
/// Mystical Agriculture's `secondarySeedDrops` common-config default.
pub const SECONDARY_SEED_DROPS: bool = true;
/// `CropTier`'s base secondary-seed chance (`api/crop/CropTier.java:51`).
const SECONDARY_BASE_CHANCE: f64 = 0.1;
/// The extra chance a tier's own effective farmland adds (`Crop.getSecondaryChance`).
const EFFECTIVE_FARMLAND_BONUS: f64 = 0.1;
/// `InferiumCropBlock`'s extra-essence chance on an even tier above 1.
const EVEN_TIER_EXTRA_CHANCE: f64 = 0.5;

/// What stands under the crop, as the drop rules read it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ground {
    /// Vanilla farmland, dirt, anything without an essence tier.
    Plain,
    /// An essence farmland of the given tier (1 inferium through 5 supremium).
    Essence { tier: u8 },
}

impl Ground {
    /// The ground an essence farmland block id names; every other block is plain.
    #[must_use]
    pub fn from_block(block: &str) -> Self {
        let tier = match block {
            "mysticalagriculture:inferium_farmland" => 1,
            "mysticalagriculture:prudentium_farmland" => 2,
            "mysticalagriculture:tertium_farmland" => 3,
            "mysticalagriculture:imperium_farmland" => 4,
            "mysticalagriculture:supremium_farmland" => 5,
            _ => return Self::Plain,
        };
        Self::Essence { tier }
    }

    /// `Crop.getSecondaryChance`: the tier's 0.1 base on an essence farmland,
    /// plus 0.1 when it is that tier's own effective farmland. Tier 1's
    /// effective farmland is inferium farmland, so inferium reaches 0.2.
    fn secondary_chance(self) -> f64 {
        match self {
            Self::Plain => 0.0,
            Self::Essence { tier: 1 } => SECONDARY_BASE_CHANCE + EFFECTIVE_FARMLAND_BONUS,
            Self::Essence { .. } => SECONDARY_BASE_CHANCE,
        }
    }
}

/// The stacks a broken crop leaves.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Harvest {
    /// Inferium essence, 0 below age 7.
    pub essence: u32,
    /// Inferium seeds, 1 or 2.
    pub seeds: u32,
}

/// Whether `age` is the ripe stage.
#[must_use]
pub fn is_ripe(age: u8) -> bool {
    age >= MAX_AGE
}

/// `MysticalCropBlock.getDrops` / `InferiumCropBlock.getDrops`, in the jar's
/// draw order: below age 7 one seed and no essence; at age 7 the essence from
/// the ground, then the secondary-seed roll when the config allows it.
pub fn harvest(
    age: u8,
    ground: Ground,
    secondary_seed_drops: bool,
    mut roll: impl FnMut() -> f64,
) -> Harvest {
    if !is_ripe(age) {
        return Harvest {
            essence: 0,
            seeds: 1,
        };
    }

    let essence = match ground {
        Ground::Plain => 1,
        Ground::Essence { tier } => {
            // `(int)(0.5 * tier + 0.5)`: the base yield, rounded up at the half.
            let mut essence = (0.5 * f64::from(tier) + 0.5) as u32;
            // InferiumCropBlock: a half chance of one more above tier 1 on an even tier.
            if tier > 1 && tier % 2 == 0 && roll() < EVEN_TIER_EXTRA_CHANCE {
                essence += 1;
            }
            essence
        }
    };

    let mut seeds = 1;
    if secondary_seed_drops && roll() < ground.secondary_chance() {
        seeds = 2;
    }

    Harvest { essence, seeds }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn harvest_with(age: u8, ground: Ground, seed_drops: bool, values: &[f64]) -> Harvest {
        let queue = std::cell::RefCell::new(std::collections::VecDeque::from(values.to_vec()));
        harvest(age, ground, seed_drops, || {
            queue.borrow_mut().pop_front().unwrap_or(0.0)
        })
    }

    #[test]
    fn a_young_crop_drops_one_seed_and_no_essence() {
        for (age, ground) in [
            (0, Ground::Plain),
            (6, Ground::Plain),
            (6, Ground::Essence { tier: 5 }),
        ] {
            let mut draws = 0;
            let got = harvest(age, ground, SECONDARY_SEED_DROPS, || {
                draws += 1;
                0.0
            });
            assert_eq!(
                got,
                Harvest {
                    essence: 0,
                    seeds: 1
                },
                "age {age}"
            );
            assert_eq!(draws, 0, "age {age} must not draw");
        }
    }

    #[test]
    fn a_ripe_crop_on_plain_farmland_drops_one_essence_and_one_seed() {
        // Plain ground has no secondary chance, so even a 0.0 roll is not
        // below it and the seed count stays 1.
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Plain, SECONDARY_SEED_DROPS, &[0.0, 0.0]),
            Harvest {
                essence: 1,
                seeds: 1
            }
        );
    }

    #[test]
    fn inferium_farmland_gives_a_fifth_chance_of_a_second_seed() {
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Essence { tier: 1 }, true, &[0.19]),
            Harvest {
                essence: 1,
                seeds: 2
            }
        );
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Essence { tier: 1 }, true, &[0.2]),
            Harvest {
                essence: 1,
                seeds: 1
            }
        );
    }

    #[test]
    fn the_secondary_seed_config_off_keeps_one_seed() {
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Essence { tier: 1 }, false, &[0.0]),
            Harvest {
                essence: 1,
                seeds: 1
            }
        );
    }

    #[test]
    fn a_higher_essence_tier_raises_the_essence_yield() {
        // A 0.9 roll fails the even tier's extra-essence chance, so this is
        // the base yield: floor(0.5 * tier + 0.5).
        for (tier, want) in [(1, 1), (2, 1), (3, 2), (4, 2), (5, 3)] {
            assert_eq!(
                harvest_with(MAX_AGE, Ground::Essence { tier }, false, &[0.9]),
                Harvest {
                    essence: want,
                    seeds: 1
                },
                "tier {tier}"
            );
        }
    }

    #[test]
    fn an_even_tier_above_one_has_a_half_chance_of_one_more_essence() {
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Essence { tier: 4 }, false, &[0.49]),
            Harvest {
                essence: 3,
                seeds: 1
            }
        );
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Essence { tier: 4 }, false, &[0.5]),
            Harvest {
                essence: 2,
                seeds: 1
            }
        );
    }

    #[test]
    fn the_extra_essence_roll_precedes_the_seed_roll() {
        // Tier 4 on tier-4 farmland draws for the extra essence first, then
        // for the 0.1 secondary seed. With 0.9 then 0.05: no extra essence,
        // but a second seed. The reverse order would give 3 essence and 1 seed.
        assert_eq!(
            harvest_with(MAX_AGE, Ground::Essence { tier: 4 }, true, &[0.9, 0.05]),
            Harvest {
                essence: 2,
                seeds: 2
            }
        );
    }

    #[test]
    fn every_essence_farmland_id_maps_to_its_tier() {
        for (block, tier) in [
            ("mysticalagriculture:inferium_farmland", 1),
            ("mysticalagriculture:prudentium_farmland", 2),
            ("mysticalagriculture:tertium_farmland", 3),
            ("mysticalagriculture:imperium_farmland", 4),
            ("mysticalagriculture:supremium_farmland", 5),
        ] {
            assert_eq!(
                Ground::from_block(block),
                Ground::Essence { tier },
                "{block}"
            );
        }
        assert_eq!(Ground::from_block("minecraft:farmland"), Ground::Plain);
        assert_eq!(
            Ground::from_block("mysticalagriculture:inferium_block"),
            Ground::Plain
        );
    }

    #[test]
    fn only_age_seven_is_ripe() {
        assert!(!is_ripe(0));
        assert!(!is_ripe(6));
        assert!(is_ripe(7));
    }
}
