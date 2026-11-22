# Line of Command V1: Balance Simulation Plan

Purpose: every balance claim in `spec.md` becomes a numbered check with a pass/fail threshold. Once the Godot resolver exists, these checks are the QA acceptance tests. Current numbers are **prototype estimates** from the throwaway Python sim (`prototype/`). They are a baseline, not proof.

## 1. Harness design (for Lead Dev)

- **Use the real resolver.** The harness calls the production `resolve_battle()` and breeding functions. It never calls a copy. It runs headless: `godot --headless --script res://tools/balance_sim.gd -- --suite all --master-seed 20261122 --out sim_out/`.
- **Data:** it loads `data/*.json` exactly as the game does, and records each file's hash in the output so a result is tied to a table version.
- **Seeds:** master seed 20261122. Each trial seed is `hash32(master_seed, suite_id, trial_index)`. A failing trial can be replayed alone with `--suite B2 --trial 4182`.
- **Sample sizes:** 20,000 battles for headline win rates (95% CI about ±0.7 points), 4,000 per matrix cell (about ±1.5), and 10,000 breedings per parent pair.
- **Random setup** unless a check fixes it:
  - budget 14 (Major)
  - composition: random legal mix (cannon 0-3, cavalry 0-5, at least 2 infantry)
  - terrain and stance uniform
  - base officer: every visible stat = `randint(35, 55) + Normal(0, 5)`, hidden stats `randint(30, 70)`, no traits
  - the edge side is A or B 50/50
  - a draw scores 0.5
- **Output:** `sim_out/<suite>.json` = `{check_id, metric, value, ci95, threshold, pass, data_hashes, n}` plus a summary table. Runs in CI on every change to `data/` or the resolver, and nightly.
- **Policies used by checks:** "smart rally" = standing order `rally when_morale_below 45`. "Blind rally" = `rally send_tick 3`. "Reserves early" = `commit_reserves send_tick 3` with 25% of infantry in reserve.

## 2. Battle checks

| ID | Question | Setup | Pass threshold | Prototype |
|---|---|---|---|---|
| B1 | Is the resolver deterministic? | 10k random battles run twice, plus 1k fixtures on Win/Linux/macOS | 100% identical log hashes | n/a (design) |
| B2 | **D3 (decided):** does a +20 officer win about 64%? | every visible stat +20, 20k battles | 60.0-65.0% (target 64%) | 64.1% |
| B2b | +10 and +30 edges | same | +10: 54-59%. +30: 66-74% | 57.4% / 70.6% |
| B2c | Mirror | identical officers | 49-51% | ~50% |
| B3 | **D3 (decided):** does any single stat dominate? | one stat +20 (12 runs: 5 attributes, Wisdom, 6 skills), 20k each | each ≤ 56.0% | max Leadership 53.3% |
| B3b | **D3 (decided):** is Leadership the strongest skill? | same runs as B3 | Leadership's win rate is the highest of the 6 skills | Leadership 53.3% vs next skill Artillery 51.8% |
| B4 | No formation over 55% overall | formations forced uniformly | each 45-55% | 47.5-51.4% |
| B4b | Same, with the AI picking | AI picks | each 45-55% | 47.2-53.8% |
| B4c | Formation per terrain | forced, per terrain | each 38-62% | 40.8-56.9% |
| B5 | **D2 (decided):** countered side's win rate | formations forced; the 4 cycle pairs in both orientations, 4k per cell; random comps, terrain and stances | mean across pairs 24.0-29.0%; each pair 22.0-31.0% (tolerance band) | mean 28.1%; pairs 24.5-30.5% (400/cell, ±2.5) |
| B6 | Composition balance | 6 archetypes round-robin | each 42-58% overall; per terrain 25-75% | 47-54%; 34-73% |
| B7 | Stance balance | 3×3 matrix | every cell 45-55% | 47.3-53.0% |
| B8 | What is the messenger worth? | smart rally vs none / smart vs blind / reserves early vs none | 54-62% / 51-56% / 52-60% | 59.3% / 53.2% / 55.9% |
| B9 | Officer doesn't overwhelm formation | A gets +20 but is forced into the countered formation | A wins ≤ 50% | 40.5% |
| B10 | Officer doesn't overwhelm terrain/comp | A +20 with gun line on Open Field vs horse | A wins ≤ 55% | 39.2% |
| B11 | Do upsets happen? | weaker side −20 | wins ≥ 35% | 35.9% |
| B12 | Battle length and draws | random | mean 7-12 ticks; timeouts ≤ 5%; draws ≤ 3% | 8.5 ticks; draws 0.9% |
| B13 | Does it hold at every rank? | B2 at budgets 10, 12, 16, 18, 20 | each within ±3 points of the budget-14 value | to measure |
| B14 | Visible trait impact | officer with 1 trait vs none | battle strengths 51-57%; battle weaknesses 43-49%; non-battle traits 49-51% | 51.0-56.5% / 45.8-49.4% |
| B15 | Hidden trait impact | 1 hidden trait vs none | each 45-56%; reveal rate per battle 10-60% (log) | not prototyped |
| B16 | Hidden attribute range | Aggression / Temperament / Inspiration 80 vs 20 | each 44-56% | to measure |
| B17 | Is narration complete? | 10k logs | every event type has ≥ 1 template; no unfilled `{placeholder}` | to measure |
| B18 | Is the replay faithful? | 1k logs | troop counts in `state` equal setup minus the summed casualty events | to measure |
| B19 | **D1:** is a live click seamless? | 10k battles; for each, a random t, re-run with `live_send_tick = t` | ticks 1..t of the re-run byte-identical to the original; 100% | design |
| B20 | **D1:** does the first trigger win? | 10k battles with a standing order + a random live click | exactly 1 `messenger_sent` per side; its send tick = min(standing, live); live wins ties; the other logged as cancelled/ignored | design |
| B21 | **D1:** are re-watches fixed? | 1k stored battles | re-deriving from stored inputs reproduces the log hash; the client exposes no messenger input on re-watch | design |
| B22 | **D1:** do standing-order conditions work? | each of the 4 conditions × min/default/max | send tick = the first tick whose post-tick state meets the condition; none if a side routed that tick | design |
| B23 | **D6 (decided):** is terrain symmetric? | mirrored armies and officers on each terrain, sides swapped 50/50, 20k per terrain; plus a static check that the resolver never reads `terrain.deferred_attacker_defender` | each terrain 49-51% for side A | ~50% (mirror) |

## 3. Breeding checks

| ID | Question | Setup | Pass threshold | Prototype |
|---|---|---|---|---|
| R1 | Is breeding predictable? | 10k breedings for midparents 30, 40, 50, 60, 70, 80 | ≥ 85% within ±6 of midparent; sd 3.5-4.5 (≤ 3.5 above 80) | 89-95%; sd 2.9-4.0 |
| R2 | Progress exists | 20-officer roster, best × best, 12 generations | newest child gains ≥ +4 mean over gen 1 | +5.8 |
| R3 | No runaway | the same for 60 generations, plus 80 × 80 elite lines | roster mean ≤ 75; elite p90 ≤ 95 after 10 generations; never > 99 | elite mean 89.4, p90 93 |
| R4 | Do recessives skip generations? | carrier × carrier | 22-28% express | 24.2% |
| R4b | Same, homozygous founder × random mates | 5 generations | child 20-35%; "skip then return" 15-25% | 28.5%; 20.1% |
| R5 | Dominant heterozygote × random | | 40-50% | 43.0% |
| R6 | Founder trait spread | 100k founders | each dominant 10-15%; each recessive 3-6%; hidden "none" 45-60% | 12.3-12.7%; 4.0-4.3%; 53.1% |
| R7 | Inbreeding | sibling / half / cousin pairs | mean shift −3 / −2 / −1 (±0.3); sd ×1.5 / ×1.25 / ×1 | to measure |
| R8 | Is the preview honest? | 1k pairs × 1k children | empirical p10/p50/p90 within ±1 of the displayed preview | to measure |
| R9 | Hidden attribute inheritance | 10k | mean = mid + 0.15 × (50 − mid) ± 0.5 | to measure |
| R10 | **D14:** is the starter roster right? | 10k new accounts | exactly 3 officers, all Lieutenant, 0 battles, no parents, every attribute 20-60, each with 1 visible strength and 1 visible weakness, pairwise different strengths and weaknesses, deterministic per account id; at least 1 legal breeding pair (unrelated) exists on day 1, and a scripted player can make the first breed on day 2 | 0 violations; at most 9 genotype draws; 3 of 3 pairs legal (`starter.py`) |

## 4. Progression checks

| ID | Question | Pass threshold | Prototype |
|---|---|---|---|
| P1 | Wisdom curve at a 50% win rate | INT 50 at 30 battles: 55-65; never above `min(99, 60 + 0.4 × INT)` | INT 50: 56.6 |
| P2 | Training pace | all-45 officer reaches skill 80 in 40-70 clicks | 54 |
| P3 | Rank pacing: median days for one officer to reach General at 3 battles/day (the per-officer maximum, §22) and a 50% win rate, new officers per §2 | median 26-32 days; p90 ≤ 36 days | median 28 days (p10 27, p90 33; 20k officers, `prototype/rankpace.py`) |
| P4 | Attribute battle growth | mean +0.30 ± 0.02 per battle when all < 80 | design value |
| P5 | Is the soft cap visible? | 1,000 officers × 300 battles: share of attributes ≥ 90 from growth alone ≤ 1% | to measure |

## 5. Economy checks (buy-to-play, never pay-to-win; D11 DECIDED)

| ID | Question | Pass threshold |
|---|---|---|
| E2 | Do Skirmish and scenario replays write nothing? | 1,000 Skirmishes and 1,000 scenario replays: officer record hash unchanged (Wisdom, skills, attributes, rank, reveals, battle counts) |
| E3 | Are the daily limits enforced the same for everyone? | the 4th ranked battle, 2nd breed, 7th training click and 4th click on one officer are refused, whatever the account owns; all reset at 00:00 UTC |
| E5 | Does any purchasable item change a number? | for every DLC and cosmetic ID (and for "owns everything" vs "owns nothing"): (a) the loaded values of every `data/*.json` file except presentation-only cosmetic lists are byte-identical; (b) 1,000 battles with the same seeds give byte-identical event logs; (c) a 90-day scripted account with the same choices ends with byte-identical officer records. Static check: `resolve_battle` and the progression functions take no ownership/DLC argument and read no account state |
| E6 | Do mirrored limits agree? | `economy.daily_limits` equals `breeding.limits.breeds_per_day_account` and `skills.training`, and `economy.roster_slots` equals `breeding.roster.cap` |
| E7 | Do the per-officer limits agree? | static check reading both JSON files at load (and in CI): `economy.json → daily_limits.ranked_battles_per_officer_per_day` must equal `campaign.json → picking.max_assignments_per_officer_per_day` (both 3 in v1.3); fail the build if they differ | equal (3 = 3) |

*(E1 and E4, the old free-vs-paid checks, were removed with the subscription. E5 replaces both.)*

## 6. Scenario checks (D12 decided; `scenarios.json`)

Setup for S1-S2 follows `scenarios.json` exactly: the garrison (side B) is a random legal 10-point army with a uniform stance and the base officer from §1. The attacker is built by `battle.ai_general` at 14 points, with the officer = garrison officer + uniform(−10, +10) and the stance uniform over `allowed_stances`. Messengers are used as in the spec (the prototype did not simulate them).

| ID | Question | Setup | Pass threshold | Prototype |
|---|---|---|---|---|
| S1 | Is Hold the Fort on target? | 20k seeded scenario battles | defender wins 44.0-50.0% (target 47%) | 47.5% (24k runs; walls ×0.68) |
| S1b | Hold the Fort with a weaker officer | S1 with the garrison officer −10 on every visible stat | 36-45% (reported, so the proving ground is not hopeless) | 40.5% |
| S2 | Is Last Stand on target? | 20k seeded scenario battles | defender wins 32.0-38.0% (target 35%) | 34.6% (24k runs; walls ×0.735) |
| S2b | Last Stand with a weaker officer | S2 with the garrison officer −10 | 25-34% (reported) | 29.2% |
| S2c | Is Last Stand harder than Hold the Fort? | S1 and S2 results | S2 rate ≤ S1 rate − 8 points | 12.9 points apart |
| S3 | Is each Wisdom multiplier right? | static check plus 1k scripted scenario wins and losses | `wisdom_win_mult == round(min(2, 0.5 / target), 2)` for every scenario (1.06 and 1.43); a win's Wisdom gain = the normal gain × the multiplier (±1e-9); a loss uses the normal ×1.25 with no scenario multiplier | 1.06 / 1.43 |
| S3b | Is a scenario a Wisdom farm? | S1 and S2 rates with the S3 rule; expected Wisdom per taken scenario assignment vs a 50% ranked battle at the same officer state (win ×1.0, loss ×1.25) | each scenario ≤ +20% (reported; scenarios give fewer wins toward rank, which offsets it) | +3% / +17% |
| S4 | **AC-5:** is a scenario ranked only when taken from the board? | scripted account, 1 day: (a) take a scenario assignment from the board; (b) play the same scenario again from the scenario menu, 5 times; (c) play the other scenario from the menu without a board option; (d) after the 3 daily battles are used, play any scenario from the menu | PASS only if all hold: (a) uses exactly 1 ranked battle (count 3 → 2) and changes the officer record (Wisdom × `wisdom_win_mult` on a win, battles +1); (b), (c) and (d) leave the ranked-battle count unchanged and the officer record hash byte-identical, and are logged as `replay`; (d) is allowed (replays are never refused). Any deviation fails | n/a (design) |
| S5 | Does the objective resolve correctly? | 10k scenario battles | no scenario battle reaches the timeout; every defender win has reason `objective` or `rout`; a battle where the defender routs is always an attacker win; logs are deterministic (B1 rules) | n/a (design) |
| S6 | Do scenario modifiers leak into normal battles? | B-suite fixtures with `scenario = null` | byte-identical logs with and without `scenarios.json` loaded | identical (prototype +20 edge still 64.1%) |

## 7. Campaign board checks (v1.1, D13; `campaign.json`)

| ID | Question | Setup | Pass threshold | Prototype |
|---|---|---|---|---|
| C1 | Is the board deterministic? | 10k (scope_id, day_index, snapshot ranks) inputs, each generated twice and on Win/Linux/macOS | identical boards (option ids, locations, ranks, types, briefs) | identical (10k days) |
| C9 | Is the board frozen after its first build? | scripted account: open the board at 00:05 UTC, then breed, release an officer on the snapshot and promote another, then reopen; also build the same scope, day and snapshot on a fresh install | the reopened board is byte-identical to the first build; the fresh build with the same snapshot is identical; options for a released officer's rank stay; a pick is accepted or refused by the officer's **current** rank (own or one below); the next day's board uses a new snapshot | snapshot → identical; promoted Lieutenant → Major loses Lieutenant options (`starter.py`) |
| C2 | Do the variety rules hold? | 10k generated days with random rank mixes (1-6 distinct ranks; 30% Lieutenant-only) | every board has 6 options, distinct locations, ≥ 3 distinct terrains, every owned rank covered by a standard option it can take | 0 violations; 3 terrains 44%, 4 terrains 56% |
| C3 | Is there always an option for the lowest rank? | same 10k days | ≥ 1 option eligible for the lowest-rank officer on every board | min 1, mean 4.0; 0 violations |
| C4 | Do scenarios stay within limits? | same 10k days | ≤ 2 per day, ≤ 1 of each, only at fort locations, only if a Lieutenant or Captain is owned; on eligible days the 0/1/2 shares are within ±2 points of 40/45/15 | 0 violations; 40.0/44.8/15.2% |
| C5 | Is the daily cap enforced? | scripted account | per-officer cap 3: one officer can take 3 assignments in a day and a 4th for that officer is refused; account cap 3: a 4th assignment by any officer is refused (also when split across officers); an option can't be taken twice; untaken options expire at 00:00 UTC and nothing carries over | n/a (design) |
| C6 | Does the board change any balance number? | 20k battles routed through boards vs 20k direct ranked battles, with no edge and with a +20 edge; plus a static check that an assignment battle passes exactly the same inputs to `resolve_battle` as a direct battle with the same terrain, budget and seed | player win rates within ±1.0 point; byte-identical logs for identical inputs | +0 edge 56.3% vs 56.9% (−0.6); +20 edge 70.1% vs 70.0% (+0.1) |
| C7 | Are rewards unchanged? | static check plus 1k scripted assignments | standard options have `wisdom_win_mult` 1.0; scenario options carry exactly the `scenarios.json` value; winning or losing a location changes only the personal map flag and narration | n/a (design) |
| C8 | Are shared-war hooks inert in V1? | static check | `war_id` is null; `option.side` is `blues`; nothing reads `locations[].controller` except the map view | n/a (design) |

Note on C6: the prototype's absolute rates (about 57% with no edge) come from a random player army facing the generator's archetype army without simulated messengers. Only the difference between the two routes matters here.

## 8. Reporting
A suite passes when every check passes. If a check fails, the report names the table and the field most likely responsible, and the designer re-tunes **only `data/*.json`** (never code) and re-runs. Prototype baselines are in `prototype/final_*.txt`.
