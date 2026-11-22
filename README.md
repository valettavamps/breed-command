# Line of Command

Single-player Godot 4 battle kernel for Milestone 1. Balance numbers live only in `data/*.json` (spec v1.4, data version 1.4). Code keys on ids (`tight_wedge`, `cannon`), never on display names.

## Engine

Godot **4.7.2 stable** (`4.7.2.stable.official`).

```bash
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite ac1 --master-seed 20261122
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite ac2 --master-seed 20261122
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite CLK --master-seed 20261122
```

Output is `sim_out/<suite>.json`. Each check carries `fixture_id` = `<check id>@20261122@<git SHA>`, plus the measured value, the band, `pass`, and the sha256 of every file in `data/`.

`--suite` accepts `ac1`, `ac2`, `ac6`, `CLK`, `all`, or any implemented check id (`B5`, `B14`, `B15`, `S6`, `E7`, `LITERALS`, and the rest of the battle checks in this tree). `--trial N` runs that trial index only. `--out` writes the suite file (a directory ending in `/` gets `<suite>.json` inside it).

`--scope-id`, `--clock`, `--local-clock`, and `--net-state` are parsed in `scripts/launch_flags.gd` and applied to `GameClock`. AC-8-PUBLIC-FLAGS-IGNORED (a public build ignores those four unless a QA-build flag is set) stays deferred to M4. M1 does not gate them.

## What is in the tree

- `scripts/battle_resolver.gd` — pure `resolve_battle(armyA, armyB, terrain_id, seed, scenario=null)`. No clock, file IO, scene tree, or global RNG. One `RandomNumberGenerator` is created from `seed`.
- `scripts/balance_data.gd` — loads every `data/*.json`, sha256 per file, and fails the process if `economy.daily_limits.ranked_battles_per_officer_per_day` differs from `campaign.picking.max_assignments_per_officer_per_day`.
- `scripts/narration.gd` — fills `narration.json` templates. `{formation_name}` is `formations.<id>.name`. `{unit_plural}` is `units.<id>.narration_plural`. No plural is built by appending a letter.
- `scripts/game_clock.gd` — injectable UTC day clock. Boundary is 00:00 UTC. Synced time is the injected server clock. Offline time is local time plus the last server−local offset (0 until the first sync). `day_index` (days since 2026-01-01 00:00 UTC) never moves backwards. No Steam calls.
- `scripts/records.gd` — save, officer, army, and battle-log records carry `v`. Officer and army records do not carry `side` or `faction_id` (Addendum E).
- Formations, terrain, stances, and units are whatever the JSON tables contain. `counter_reasons`, rank `command_size`, and scenario `historical_odds_note` are loaded and not shown (no UI in M1). Matchup multipliers are read from `formations.json` only.

There is no networking code. A future Steamworks addon, if added, belongs under `addons/godotsteam/` and nowhere else. That directory is not created in M1.

## Checks

`ac1`: B1, B17, B18, S6, E6, E7, and `LITERALS` (no balance literal in `scripts/` or `tools/`). Officer draws and QA bands are read from sim-plan and the JSON tables.

`ac2`: B2, B2b, B2c, B3, B3b, B4, B4b, B4c, B5, B6, B7, B9, B10, B11, B12, B13, B14, B15, B16, B23.

`CLK`: day boundary, local clock ignored while synced, offline offset kept, day index never rewinds, never-synced offset 0, and the flag parser. Fixture `CLK@20261122@<SHA>`.

`ac6`: scored E7 only. Fixture `E7@20261122@<SHA>`. The loader also asserts the same equality at startup.

```bash
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite ac6 --master-seed 20261122
```

Headline win rates use 20,000 trials. Matrix cells use 4,000. B14 uses 20,000 because the non-battle band is one point wide. Seeds are `hash32(master, check id, trial)` with FNV-1a over `master|check|trial`.

## Resolver notes

Where the spec is silent, the Python prototype in the spec folder (not copied into this repo) was the guide. Choices that are easy to get wrong:

- Formation noise is always drawn, four uniforms per side in JSON key order (Line, Column, Pincer, Screen), even when a formation is forced. The prototype skipped those draws. The spec lists them first in the draw order.
- Each tick always draws damage variance and temperament noise for A then B. Noise is applied only when that side took casualties.
- Round-half-away-from-zero for positive numbers is `floor(x + 0.5)`, with the half built as `1/(1+1)` so it is not a copied balance number.
- The neutral point 50 is parsed from JSON key suffixes `_over_50` / `_under_50`. There is no dedicated neutral key in the spec, so one was not invented.
- The leading 100 in the morale-loss formula, the insight divisor, `strength_below_pct`, and hidden-trigger percents all use `battle.morale.cap`. A separate scale key was not added.
- Gumbel `u` is kept off 0 and 1 by `2^-20`. The spec does not name that epsilon, so it is not a new JSON key.
- Timeout weights are parsed from `battle.timeout.score`. The ratio uses strength, not headcount, because spec §15.3 and `units.json` both say timeout uses strength.
- Morale-shaken thresholds are `messenger.auto_reserves.morale_below` and the `panic_prone` trigger. Hidden-bravery reveal and the temperament loss percent are parsed from the trigger strings in `attributes.json`.
- Cannon canister and “melee only at distance 0” come from `units.cannon` reach plus `units.canister`. Cavalry fire is logged as `volley` with that unit’s `narration_plural`. Cannon melee is logged as `melee`.
- Pursuit uses the cavalry melee package times `battle.pursuit.winner_cavalry_melee_mult`, with no extra RNG draw, and only against a side that routed. The prototype did not implement pursuit.
- Hidden traits follow `traits.json` and `hidden_trigger_rules` (spec §6.3 and §15.3). Casualty triggers with an optional `value` need that percent of starting strength. Duration effects start on the following ticks. The cannon share of morale loss is `1 − s × (1 − m)`.
- Scenario modifiers (hold, fire, damage taken, morale loss, formation bias, objective) run only when the `scenario` argument is set. S6 checks that `scenario = null` is byte-identical whether or not `scenarios.json` is loaded, and that passing Hold the Fort changes the log.
- A visible trait is non-battle for B14 when every effect key is `training_mult` or `wisdom_gain_mult` (Quick Study, Slow Learner, Vain). Hesitant is measured with the infantry reserve fraction named in the B14 row of sim-plan.
- Archetype armies use `battle.ai_general` shares: floor the point share, floor-divide by cost, leftover points to `infantry`.
- Officer generation for the harness is the sim-plan §1 sentence: one `randint` plus an independent normal per visible stat, hidden `randint`, no traits unless the check adds one. The numbers are read from that sentence.
- Setup RNG and battle RNG are separate generators seeded with the same trial seed.
- `hash32` is FNV-1a 32-bit. The spec names the function and does not define the mix.
- `ln`, `exp`, and `cos` go through `scripts/portable_math.gd`. The series is only arithmetic.
- Log hashes and `inputs_hash` use `JSON.stringify` with full precision (Grisu2). The default printer calls `log10` and `snprintf`. On the previous SHA that printer, not the battle math, was what made 73 of 1,000 Windows B1 logs differ from Linux and macOS.

## v1.4

The data files are the Systems Designer's v1.4 tables, copied verbatim. Spec §6.3 and §15.3 describe the hidden-trigger rules the resolver follows. B5, B14, and B15 were retuned in those tables. This tree does not simulate breeding (R), progression (P), the campaign board (C), or the scenario campaign checks other than S6.
