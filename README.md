# Line of Command

Single-player Godot 4 battle kernel for Milestone 1. Balance numbers live only in `data/*.json` (spec v1.3, data version 1.3). Code keys on ids (`tight_wedge`, `cannon`), never on display names.

## Engine

Godot **4.7.2 stable** (`4.7.2.stable.official`).

```bash
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite ac1 --master-seed 20261122
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite ac2 --master-seed 20261122
godot --headless --path . --quit-after 1 --script res://tools/balance_sim.gd -- --suite CLK --master-seed 20261122
```

Output is `sim_out/<suite>.json`. Each check carries `fixture_id` = `<check id>@20261122@<git SHA>`, plus the measured value, the band, `pass`, and the sha256 of every file in `data/`.

`--suite` also accepts a single check id (`B2`, `S6`, `E7`, `LITERALS`) or `all`. `--trial N` is accepted by the flag parser for later replay. `--scope-id`, `--clock`, `--local-clock`, and `--net-state` are parsed in `scripts/launch_flags.gd`. M1 does not gate them on a QA build flag; that gate belongs in the same parser later. Public builds must ignore those four flags unless the QA build flag is set.

## What is in the tree

- `scripts/battle_resolver.gd` — pure `resolve_battle(armyA, armyB, terrain_id, seed, scenario=null)`. No clock, file IO, scene tree, or global RNG. One `RandomNumberGenerator` is created from `seed`.
- `scripts/balance_data.gd` — loads every `data/*.json`, sha256 per file, and fails the process if `economy.daily_limits.ranked_battles_per_officer_per_day` differs from `campaign.picking.max_assignments_per_officer_per_day`.
- `scripts/narration.gd` — fills `narration.json` templates. `{formation_name}` is `formations.<id>.name`. `{unit_plural}` is `units.<id>.narration_plural`. No plural is built by appending a letter.
- `scripts/game_clock.gd` — injectable UTC day clock. Boundary is 00:00 UTC. Synced time is the injected server clock. Offline time is local time plus the last server−local offset (0 until the first sync). `day_index` (days since 2026-01-01 00:00 UTC) never moves backwards. No Steam calls.
- `scripts/records.gd` — save, officer, army, and battle-log records carry `v`. Officer and army records do not carry `side` or `faction_id` (Addendum E).
- Formations, terrain, stances, and units are whatever the JSON tables contain. `counter_reasons`, rank `command_size`, and scenario `historical_odds_note` are loaded and not shown (no UI in M1). Matchup multipliers are read from `formations.json` only.

There is no networking code. A future Steamworks addon, if added, belongs under `addons/godotsteam/` and nowhere else. That directory is not created in M1.

## Checks

`ac1`: B1, B17, B18, S6, E6, E7, and `LITERALS` (no balance literal in `scripts/`).

`ac2`: B2, B2b, B2c, B3, B3b, B4, B4b, B4c, B5, B6, B7, B9, B10, B11, B12, B13, B14, B15, B16, B23.

`CLK`: day boundary, local clock ignored while synced, offline offset kept, day index never rewinds, never-synced offset 0, and the flag parser. Fixture `CLK@20261122@<SHA>`.

Headline win rates use 20,000 trials. Matrix cells use 4,000. B14 uses 20,000 because the non-battle band is one point wide. Seeds are `hash32(master, check id, trial)` with FNV-1a over `master|check|trial`.

## Resolver notes

Where the spec is silent, the Python prototype in the spec folder (not copied into this repo) was the guide. Choices that are easy to get wrong:

- Formation noise is always drawn, four uniforms per side in JSON key order (Line, Column, Pincer, Screen), even when a formation is forced. The prototype skipped those draws. The spec lists them first in the draw order.
- Each tick always draws damage variance and temperament noise for A then B. Noise is applied only when that side took casualties.
- Gumbel `u` is clamped away from 0 and 1. The prototype used `1e-12`. This build uses `2^-20`.
- Round-half-away-from-zero for positive numbers is `floor(x + 0.5)`, with the half built as `1/(1+1)` so it is not a copied balance number.
- The neutral point 50 is parsed from JSON key suffixes `_over_50` / `_under_50`.
- The leading 100 in the morale-loss formula and the insight divisor are `battle.morale.cap`.
- Timeout weights are parsed from `battle.timeout.score`. The ratio uses strength, not headcount, because spec §15.3 and `units.json` both say timeout uses strength.
- Morale-shaken thresholds are `messenger.auto_reserves.morale_below` (45) and the `panic_prone` trigger (35). Hidden-bravery reveal and the temperament 25% loss are parsed from the trigger strings in `attributes.json`.
- Cannon canister and “melee only at distance 0” come from `units.cannon` reach plus `units.canister`. Cavalry fire is logged as `volley` with that unit’s `narration_plural`. Cannon melee is logged as `melee`.
- Pursuit uses the cavalry melee package times `battle.pursuit.winner_cavalry_melee_mult`, with no extra RNG draw, and only against a side that routed. The prototype did not implement pursuit.
- Hidden traits follow spec §6.3 and do not consume RNG. The prototype did not simulate them.
- Scenario modifiers (hold, fire, damage taken, morale loss, formation bias, objective) run only when the `scenario` argument is set. S6 checks that `scenario = null` is byte-identical whether or not `scenarios.json` is loaded, and that passing Hold the Fort changes the log.
- A visible trait is “non-battle” for B14 when every effect key is one of `training_mult`, `wisdom_gain_mult`, `messenger_delay_add`, `auto_reserve_delay_add`, `auto_reserve_tick_override`. Hesitant is non-battle in the no-messenger, no-reserve setup. Glory Seeker is a battle weakness because it also moves the rout threshold.
- Archetype armies use `battle.ai_general` shares: floor the point share, floor-divide by cost, leftover points to `infantry`.
- Officer generation for the harness follows the prototype reading of sim-plan §1: one `randint(35, 55)` plus an independent normal per visible stat, hidden stats `randint(30, 70)`, no traits unless the check adds one.
- Setup RNG and battle RNG are separate generators seeded with the same trial seed.
- `hash32` is FNV-1a 32-bit. The spec names the function and does not define the mix.
