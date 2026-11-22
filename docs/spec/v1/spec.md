# Line of Command: V1 Systems Design Spec

Status: **v1.3, 2026-11-22.** v1.2 FINAL plus text-only changes from the Military Historian's research (see the changelog). **No balance number changed:** a numeric diff of every v1.2 and v1.3 JSON file finds 0 differences in 558 numeric, true/false and null values. Every captain decision (D1-D14) is locked; there are no open decisions. One proposal is awaiting the captain: Attack Column > Pincer at ×1.10 / ×0.91 (`historian-assessment.md`); until he decides, v1.3 keeps ×1.07 / ×0.94. Data version `1.3` in every JSON file. Author: Systems Designer. Audience: Lead Dev (builds it in Godot) and the captain (John).

## Changelog

**v1.3 (2026-11-22): text only, ids and numbers unchanged.** Lead Dev: pick up these display strings. Ids are stable; key code on ids, never on names (§11.1 id policy).

| What | Id (unchanged) | v1.2 display | v1.3 display | Where |
|---|---|---|---|---|
| Formation | `tight_wedge` | Tight Wedge | **Attack Column** (short "Column"; `legacy_names: ["Tight Wedge"]`) | `formations.json → formations.tight_wedge.name`, `cycle`; spec §5, §6, §11, §12, §13 |
| Unit | `cannon` | Cannon Battery | **Gun Section (2 guns)** (narration "gun section"; `legacy_names: ["Cannon Battery"]`) | `units.json → units.cannon.name`, `narration_name`; spec §9 |

- **New text fields** (strings only): `formations.json`: `id_policy`, `counter_reasons` (4 historical reasons, §11.1), `short_name` and `legacy_names`. `units.json`: `id_policy`, `narration_name` and `narration_plural` for every unit, `legacy_names`, `display_note`. `ranks.json`: `command_size` per rank and `command_size_note` (§8). `scenarios.json`: `historical_odds_note` per scenario and new blurbs (§21).
- **Narration:** `formation_chosen` now says "the {formation_name}" so it reads well for every name. `volley` now uses `{unit_plural}` (new `narration_plural`: companies, squadrons, gun sections), because the v1.2 form `{unit_name}s` would print "Gun Section (2 guns)s". The new `narration.json → placeholders` block defines `{formation_name}` = `formations.<id>.name`, `{unit_name}` = `units.<id>.narration_name` and `{unit_plural}` = `units.<id>.narration_plural`. `briefing_scenario` tells the historical odds. `scenario_held` gains a third variant. There are no new event types, and there is no change to the event log.
- **New §23 Deferred / DLC ideas** (also in `decisions.md`).
- **sim-plan.md:** S3b wording ("per taken scenario assignment"); P3 table cells fixed; new **E7** (the per-officer daily battle limit equals the board's per-officer assignment limit, 3 = 3, read from both JSON files). `decisions.md` D13 now cites QA C1-C9.
- The variant count for `briefing_scenario` is unchanged (2), so board briefs pick the same variant index as in v1.2; only the wording differs.

**v1.2 (2026-11-22):** per-officer cap of 3 (D13), starter roster of 3 Lieutenants (D14), board snapshot rule, S4 rewrite.

## 0. How to read this

- **Single source of truth.** All numbers live in `data/*.json`. This document quotes them and explains them. If this document and a JSON file disagree, the JSON file is right and this document has a bug. Lead Dev should load the JSON at startup (Godot: `FileAccess` + `JSON.parse_string`) and never hard-code a balance number.
- Each formula is followed by **Why** (one line) and **Example** (worked numbers).
- "Tick" means one turn of a battle. "Strength" means troops × toughness (see §9).
- Numbers marked *prototype estimate* come from a throwaway Python sim in `/workspace/sim` on the box (a copy is in `prototype/`). They suggest the design is roughly balanced. They do not prove it. `sim-plan.md` lists the checks that will.
- Scope is only the captain's V1 brief. Chain of command, PvP, the world map and the Foxhole/EU4 layering are out of scope. §15.1 keeps the battle resolver a pure function so those can plug in later.

Data files: `attributes.json`, `skills.json`, `traits.json`, `ranks.json`, `units.json`, `formations.json`, `terrain.json`, `stances.json`, `messenger.json`, `breeding.json`, `economy.json`, `narration.json`, `scenarios.json` (§21), `campaign.json` (§22), plus **`battle.json`**, which holds the resolver constants (tick count, morale constants, RNG order, AI-opponent generator). The brief's list didn't include it, but those constants need a home.

---

## 1. The officer

The player is the general. Officers are bred, trained and promoted, and in battle they fight for themselves. An officer record contains:

| Field | Range | Visible? |
|---|---|---|
| 5 innate attributes: Intelligence (INT), Athleticism (ATH), Adaptability (ADA), Bravery (BRV), Natural Affinity (NAF) | 1-99 | yes |
| Wisdom | 1-99 | yes |
| 6 skills: Horsemanship, Marksmanship, Bayonet Drill, Artillery Command, Battlefield Theory, Leadership | 1-99 | yes |
| 4 hidden attributes: Inspiration, Aggression, Temperament, Hidden Bravery | 1-99 | revealed over time (§5) |
| Trait genotype: 2 alleles each for the strength, weakness and hidden slots | trait ids | expressed strength and weakness visible; hidden slot revealed in battle (§6) |
| Rank, battles, wins, losses, draws | | yes |
| Bloodline (house name), sire id, dam id, generation | | yes |
| Per-day counters (training clicks used), breed cooldown date | | yes |

Parent roles are just "parent A" and "parent B". V1 has no sex mechanic.

**Officer Rating (OR)** is shown on the card: `OR = mean(INT, ATH, ADA, BRV, NAF, Wisdom, 6 skills)`. It is for display only and battle math never reads it.
Why: players want one number to compare officers, but the battle should only see the real parts.
Example: attributes 50/40/45/55/40, Wisdom 30, skills 20/15/20/18/22/25. Sum 380 / 12 = OR 31.7.

---

## 2. Innate attributes  (`attributes.json → innate`)

**Starting officers** (the first roster, and any officer not bred): each attribute is `round(Normal(mean 40, sd 9))`, clamped to 20-60.
Why: most recruits sit in the 30s-40s. A 58 is a rare find worth breeding from.
Example: rolls of 47.3, 28.9, 61.2 become 47, 29, 60 (clamped).

**Caps:** hard cap 99 and minimum 1. The soft cap is 80. Above 80, every growth source slows sharply:
- *Breeding:* see §7. The part of an offspring's roll above `max(80, midparent)` counts at ×0.4.
- *Battle growth:* after every ranked battle the officer makes 1 roll: pick one of the 5 attributes uniformly at random, then gain +1 with probability 0.30 if it is below 80, 0.06 if it is 80-89, 0.02 if it is 90-98, and 0 at 99.

Why: veterans improve a little, but you reach 80+ mostly through bloodlines, not grinding.
Example: an officer with ATH 82 fights. The roll picks ATH, so the chance is 6% instead of 30%. Over 100 battles an all-sub-80 officer gains about 30 points spread over 5 attributes (+6 each).

**What each attribute does**

| Attribute | Effect | Formula |
|---|---|---|
| INT | Wisdom start, growth and cap; officer-AI insight | §3, §11.4 (weight 0.2) |
| ATH | Melee damage | `× (1 + 0.0006 × (ATH − 50))` on all melee |
| ADA | Shrinks terrain penalties | penalty `m < 1` becomes `1 − (1 − m) × (1 − 0.003 × (ADA − 50))` |
| BRV | Half of Effective Bravery | §5 |
| NAF | Training and skill aptitude | §4 (weight 0.25 in aptitude) |

Example (ADA): cavalry melee in Forest is ×0.80. An officer with ADA 80 makes it `1 − 0.20 × 0.91 = 0.818`. With ADA 20 it is `1 − 0.20 × 1.09 = 0.782`.

---

## 3. Wisdom  (`attributes.json → wisdom`)

- **Start:** `Wisdom = INT × 0.5`.
- **Cap:** `WisCap = min(99, 60 + 0.4 × INT)`.
- **Growth after each ranked battle:** `gain = (1.0 + 0.02 × INT) × (1 − Wisdom / WisCap) × outcome`, where outcome is ×1.0 for a win or draw and ×1.25 for a loss. On a scenario win (a taken scenario assignment, §21-§22) the gain is also multiplied by that scenario's `wisdom_win_mult` (×1.06 Hold the Fort, ×1.43 Last Stand). Trait Vain multiplies the gain by 0.85. Wisdom never goes above WisCap.
- **Battle effect:** all damage the army deals × `(1 + 0.001 × (Wisdom − 50))`. Wisdom is also part of AI insight (weight 0.3).

Why: Wisdom is experience. It always grows, slows as it nears the cap, and the cap depends on INT, so clever officers keep their edge long-term. Losses teach a bit more, which softens losing streaks.
Example: INT 50 gives start 25 and cap 80. A first-battle win adds `2.0 × (1 − 25/80) = 1.375` (Wisdom 26.4). A loss would add 1.72. Prototype curve at a 50% win rate: INT 40 reaches 51 after 30 battles and 71 after 90. INT 80 reaches 72 after 30 and 89 after 90.

---

## 4. Skills and training  (`skills.json`)

| Skill | Primary attr | Secondary attr | Battle use |
|---|---|---|---|
| Horsemanship | ATH | BRV | cavalry melee (and its carbine fire) |
| Marksmanship | NAF | ADA | infantry fire |
| Bayonet Drill | ATH | BRV | infantry melee |
| Artillery Command | INT | NAF | cannon fire and melee |
| Battlefield Theory | INT | ADA | officer-AI insight (weight 0.5) |
| Leadership | BRV | INT | starting morale and morale loss |

- **Starting value** (new or bred officer): `round(0.25 × primary + 0.10 × secondary)`, minimum 5. Skills are not inherited.
  Example: ATH 50, BRV 40 gives Horsemanship `round(12.5 + 4) = 17`. (Rounding is standard round-half-up. Lead Dev should use `floor(x + 0.5)` everywhere.)
- **Unit-skill effect:** each unit type's damage × `(1 + 0.001 × (skill − 50))`, using that unit's `fire_skill` or `melee_skill` from `units.json`.
  Example: Marksmanship 70 makes infantry fire ×1.02.
- **Leadership:** starting morale `+ 0.02 × (L − 50)`, and morale loss × `(1 − 0.0006 × (L − 50))`.
- **Aptitude:** `apt = 0.5 + (0.5 × primary + 0.25 × secondary + 0.25 × NAF) / 100`.
- **Band multiplier** (by current skill): below 40 ×1.0, 40-59 ×0.7, 60-79 ×0.4, 80-98 ×0.12, 99 ×0.
- **Train button:** one click adds `2.0 × apt × band × traitMult` to one chosen skill of one chosen officer. Quick Study gives traitMult 1.25 and Slow Learner 0.80. **6 clicks per account per day, max 3 on any one officer, reset at 00:00 UTC, the same for every player.**
- **Battle practice:** after each ranked battle, Leadership and Battlefield Theory, plus the unit skills of every unit type fielded, each gain `0.6 × apt × band`.

Why: the training button gives a quick daily choice ("who do I drill today?") without becoming a grind. Bands make the 80s slow. NAF makes some officers natural learners, which is a reason to breed for it.
Example: primary 50, secondary 40, NAF 40 gives apt 0.95. One click at skill 30 adds +1.9, and one click at skill 65 adds +0.76. Prototype: an officer with all 45s needs 13 clicks to reach skill 40, 28 to reach 60, 54 to reach 80 and 97 to reach 90.

---

## 5. Hidden attributes  (`attributes.json → hidden`)

- **Generation (founders):** each is `round(Normal(50, 15))`, clamped to 1-99.
- **Inheritance:** §7. Midparent with 15% regression toward 50, noise sd 7 clamped to ±15. They blend more loosely than visible attributes, so the surprise stays alive.
- **Reveal:** each hidden attribute has a trigger. The first time it fires, the card shows a band (Low ≤34, Average 35-65, High ≥66). After 5 trigger events the exact number shows. Triggers:

| Hidden | Trigger event | Effect in battle |
|---|---|---|
| Inspiration | messenger Rally arrives, or morale recovers on an untouched tick | Rally strength × `(0.75 + 0.005 × Insp)`. Untouched-tick morale regen `0.5 + 0.02 × (Insp − 50)` |
| Aggression | officer picks Column or Pincer, or the army enters melee | AI bias per point over 50: Column +0.004, Pincer +0.002, Screen −0.004. Melee × `(1 + 0.001 × (Agg − 50))`. Damage taken × `(1 + 0.001 × (Agg − 50))` |
| Temperament | army loses 25% of its starting strength | Morale-loss noise `± 0.30 × (1 − Temp/99)` per tick. AI noise `+0.001 × max(0, 50 − Temp)` |
| Hidden Bravery | morale drops below 40 | Half of Effective Bravery |

**Effective Bravery** `EB = 0.5 × BRV + 0.5 × HiddenBravery`. Morale loss × `(1 − 0.001 × (EB − 50))`. Rout threshold `− 0.03 × (EB − 50)`.
Why: what an officer shows on parade and what he does under fire are different things. Half of courage stays hidden until the guns open.
Example: BRV 60 and Hidden Bravery 40 give EB 50, so no effect. The player sees BRV 60 and may be surprised the first time morale drops below 40, when "Hidden Bravery: Average" appears.

---

## 6. Traits  (`traits.json`)

**V1 rule:** every officer shows exactly 1 strength and 1 weakness and carries 1 hidden-slot trait (possibly "none"). Hidden traits are revealed the first time their trigger fires in a ranked battle (log event `trait_revealed`).

**Genetics (per slot):** an officer has 2 alleles. A child takes one random allele from each parent. A 3% chance per allele replaces it with a random allele from that slot's library (mutation, which brings in new blood). Expression rules:
1. A dominant allele beats a recessive one.
2. Two different alleles of the same dominance: a coin flip at birth (breeding seed) picks one, fixed for life.
3. A recessive allele shows only when paired with a recessive (it can skip generations).
4. In the hidden slot, "none" counts as dominant. Founders draw "none" with weight 4 and each hidden trait with weight 1.

Founder alleles are drawn uniformly from the library (hidden slot weighted as in rule 4).

Why: this is plain Mendelian logic. Players learn it in one sentence ("recessives need two copies"), and it creates the PhotoFinish "it skipped a generation!" moment.
Example: both parents show Iron Nerve (dominant), but both secretly carry Forest Fox (recessive). Each child has a 25% chance to show Forest Fox (prototype: 24.2%).

### 6.1 Strengths (12)

| id | Name | Dom. | Exact effect |
|---|---|---|---|
| iron_nerve | Iron Nerve | D | army morale loss ×0.96 |
| eagle_eye | Eagle Eye | R | infantry and cannon fire ×1.05 |
| born_in_the_saddle | Born in the Saddle | D | cavalry melee ×1.10 |
| forest_fox | Forest Fox | R | Forest penalties ×0.5 (penalty part halved) |
| high_ground | High Ground Instinct | D | on Hill, the bonus part of every Hill multiplier ×1.5 (e.g. cannon 1.15 → 1.225) |
| river_warden | River Warden | R | River Crossing penalties ×0.5 |
| drillmaster | Drillmaster | D | infantry melee ×1.08 |
| gunners_instinct | Gunner's Instinct | R | cannon fire ×1.08 |
| quick_study | Quick Study | D | training and battle-practice gains ×1.25 |
| steady_under_shot | Steady Under Shot | R | morale loss from cannon casualties ×0.75 |
| tactician | Tactician | R | AI insight +0.15 |
| born_leader | Born Leader | D | starting morale +2 |

### 6.2 Weaknesses (12)

| id | Name | Dom. | Exact effect |
|---|---|---|---|
| hothead | Hothead | D | AI bias Column +0.10, Screen −0.10. Damage taken ×1.02 |
| gun_shy | Gun-Shy | R | infantry fire ×0.93 |
| poor_rider | Poor Rider | D | cavalry melee ×0.93 |
| lost_in_the_woods | Lost in the Woods | R | Forest penalties ×1.5 |
| hesitant | Hesitant | D | messenger delay +1 tick. Auto-reserve tick +2 |
| brittle | Brittle | R | morale loss ×1.04 |
| slow_learner | Slow Learner | D | training and battle-practice gains ×0.80 |
| fear_of_water | Fear of Water | R | River Crossing penalties ×1.5 |
| stubborn | Stubborn | D | AI insight −0.15 |
| glory_seeker | Glory Seeker | R | auto-commits reserves at tick 4. Rout threshold +1 |
| vain | Vain | R | Wisdom gain ×0.85 |
| cannon_blind | Cannon-Blind | D | cannon fire ×0.94 |

### 6.3 Hidden slot (7 + none)

| id | Name | Dom. | Trigger | Effect when triggered |
|---|---|---|---|---|
| none | – | D | never | nothing |
| lions_heart | Lion's Heart | R | morale < 30 | once per battle: +15 morale |
| cool_under_fire | Cool Under Fire | D | first tick with casualties | no morale loss that tick |
| second_wind | Second Wind | R | tick 8 reached | restore 10% of morale lost so far |
| panic_prone | Panic-Prone | R | morale < 35 | rout threshold +8 for the rest of the battle |
| rash | Rash | D | distance < 4 | advance +0.5 and damage taken ×1.05 for 3 ticks |
| lucky | Lucky | R | first tick with casualties | casualties taken ×0.85 for 3 ticks |
| shaken_by_guns | Shaken by Guns | R | first cannon casualties | morale loss from cannon casualties ×1.3 for the rest of the battle |

"Penalty part" means a multiplier m < 1 becomes `1 − (1 − m) × scale`. "Bonus part" means m > 1 becomes `1 + (m − 1) × scale`. Trait scales multiply with the Adaptability scale.
Prototype: a single visible battle strength swings win rate to 51-56.5% and a single weakness to 46-49% (non-battle traits stay at 50%). Hidden traits were not prototyped.

---

## 7. Breeding and bloodlines  (`breeding.json`)

**Starter roster (D14 DECIDED 2026-11-22 (captain), `breeding.json → starter_roster`):** a new account starts with **3 Lieutenants**, generated from `hash32("loc-starter-v1", account_id)`.
- Each starter is made like any new officer: innate attributes from the 20-60 new-officer rule (§2), hidden attributes from §5, and founder trait alleles (§6). That always gives 1 visible strength and 1 visible weakness.
- Each starts at 0 battles, Wisdom = INT × 0.5, starting skills and generation 0, with no parents, in the player's house.
- **Variety rule:** the 3 starters have pairwise different visible strengths and pairwise different visible weaknesses. A later starter's genotype is re-drawn from the same RNG until this holds, up to 50 tries (the prototype needed at most 9 over 10,000 accounts).
- **Pairing rule:** V1 has no sex mechanic, so any 2 different officers can breed. The starters are unrelated, so all 3 pairs are legal (no inbreeding penalty) from day 1. Each parent still needs 3 ranked battles first, so the earliest first breed is on day 2.

**Limits:** 1 breed per account per day. Each parent then has a 3-day cooldown and must have fought at least 3 ranked battles. Limits are the same for every player (no purchase changes them; §18). The child starts as a Lieutenant with skills at starting values, Wisdom = INT/2 and 0 battles.

**Visible attribute formula** (per attribute, independently):
1. `mid = (parentA + parentB) / 2`
2. `noise = Normal(0, 4.0)` clamped to ±10 (**D5 DECIDED 2026-11-22 (captain):** wobble sd 4). Inbreeding modifies the sd and adds a penalty (below).
3. `raw = mid + noise + inbreedingAdd`
4. Soft cap: if `raw > 80`, then `base = max(80, mid)`, and if `raw > base`, `raw = base + (raw − base) × 0.4`.
5. `child = clamp(round(raw), 1, 99)`

Why: the child lands within a few points of the parents' average (predictable like PhotoFinish), and breeding the best to the best inches upward. Above 80 progress slows sharply.
Example: parents 62 and 70 give mid 66. 80% of children fall in 61-71 and 90% within ±6 of 66. Parents 82 and 84 give mid 83, and a raw roll of 88 becomes `83 + 5 × 0.4 = 85`.

Prototype estimates (10,000 breedings each):

| Parents | Mean | sd | p10 / p50 / p90 | Within ±6 of mid | Child beats better parent |
|---|---|---|---|---|---|
| 40 / 40 | 40.0 | 3.9 | 35 / 40 / 45 | 90% | 45% |
| 60 / 60 | 60.0 | 3.9 | 55 / 60 / 65 | 90% | 45% |
| 40 / 70 | 55.1 | 4.0 | 50 / 55 / 60 | 90% | 0% |
| 80 / 80 | 79.0 | 2.9 | 75 / 80 / 82 | 95% | 38% |
| 90 / 90 | 89.0 | 2.9 | 85 / 90 / 92 | 95% | 37% |

Selective breeding (roster of 20 founders, always breed the 2 best by attribute sum): the newest child's mean attribute goes 46.4 → 48.5 (gen 5) → 52.2 (gen 12). An elite single-attribute line starting at 80 × 80, keeping the best of 3 children, averages 89 after 10 generations and touches 99 only rarely. Pacing is about +0.5 mean per generation plus battle growth. See decision D5.

**Hidden attributes:** `mid + 0.15 × (50 − mid) + Normal(0, 7)` clamped to ±15, then clamp to 1-99, no soft cap.

**Inbreeding** (checked from recorded pedigree):

| Relation | Attribute add | Noise sd × |
|---|---|---|
| parent-child or full siblings | −3 | 1.5 |
| half siblings | −2 | 1.25 |
| first cousins (shared grandparent) | −1 | 1.0 |

Why: line-breeding is allowed (it concentrates recessives, which is the fun), but it costs something.

**Bloodline:** the child takes either parent's house name (player's choice). The pedigree view shows 3 generations. **Bloodline prestige** = mean OR of the officer plus all recorded ancestors up to 3 generations back. It is display only.

**Breeding preview (free for everyone):** before confirming, show each attribute's p10/p50/p90 (computed analytically from the formula above) and the odds for any trait alleles already revealed in the pedigree. An allele counts as revealed once any relative has shown it.

**Carrier visibility (D7 DECIDED 2026-11-22 (captain)):** an officer's carried allele (the copy that isn't showing) appears on the card and in the breeding preview once **any** relative in the recorded pedigree, ghosts included, has shown that trait. Until then it shows as "unknown allele".
Example: a grandson shows Iron Nerve but really carries Forest Fox. His grandmother showed Forest Fox, so his card says "carries Forest Fox", and pairing him with another known carrier previews a 25% chance. If no relative had ever shown it, his card would say "carries: unknown allele".

**Barracks and pedigree ghosts (D10 DECIDED 2026-11-22 (captain)):** the roster cap is 20 officers, and release is manual only (V1 has no ageing or retirement). A released officer leaves the barracks but stays as a read-only **pedigree ghost** (id, name, house, parents, attributes, expressed traits, revealed alleles). That keeps family trees, inbreeding checks, carrier visibility and bloodline prestige intact. Ghosts can't fight, breed or train, and they use no slots. Table: `breeding.json → roster`.

---

## 8. Ranks  (`ranks.json`)

| Rank | Point budget | Commands (display text, `command_size`) | To promote to next: battles / wins / Wisdom |
|---|---|---|---|
| Lieutenant | 10 | about a battalion (up to ~1,000 men) | 5 / 2 / – |
| Captain | 12 | a strong battalion (up to ~1,200 men) | 15 / 7 / 35 |
| Major | 14 | two battalions, a small regiment (up to ~1,400 men) | 30 / 14 / 45 |
| Lieutenant Colonel | 16 | a regiment (up to ~1,600 men) | 50 / 24 / 55 |
| Colonel | 18 | a large regiment (up to ~1,800 men) | 80 / 40 / 65 |
| General | 20 | about a brigade (up to ~2,000 men) | – |

**Command size (v1.3, display text only):** the men figure is the budget spent on infantry at 100 per company; cavalry and gun sections field fewer men per point. History grew 3-10× per rank; the game keeps 10-20 points as a gameplay choice, because ranked opponents are always the same rank and the budget only sets battle size.

Counts are lifetime ranked-battle totals. Skirmishes don't count. Promotion is checked after each battle. There is no demotion. Ranked opponents are always the same rank, so the bigger budget is never an edge over a weaker opponent; it only means a bigger battle. The one exception is scenario maps (§21), where a 10-point garrison faces a 14-point attacker by design.
Why: rank is earned through play (a win rate of about 50%), and the Wisdom gate makes INT matter for advancement.
Example: one officer may fight all 3 of the day's ranked battles (§22), so at a 50% win rate it reaches General in about 27-28 days (80 battles; prototype median 28, p10-p90 27-33). An INT 20 officer (Wisdom cap 68) takes much longer to reach Wisdom 65.

**Ranked opponent (V1 PvE, `ranks.rules.opponent` and `battle.ai_general`):** the opponent officer copies the player officer and then adds `uniform(−10, +10)` (one roll, applied to every innate attribute, Wisdom and skill). Hidden attributes are freshly rolled. The opponent's army is built from a random archetype's point shares (round down per type, leftover points go to infantry), with a random stance, 20% of points (rounded down, infantry first) held as reserve, and the standing order `rally / morale_below / 45` (§14.1).

---

## 9. Units  (`units.json`)

| Unit | Cost | Troops | Toughness | Strength / company | Fire | Melee | Range | Melee reach | Speed | Morale | Skill |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Infantry Company | 1 | 100 | 1.0 | 100 | 6 | 6 | 2 | 0 | 2 | 60 | Marksmanship / Bayonet Drill |
| Cavalry Squadron | 2 | 100 | 1.4 | 140 | 1 | 20 | 1 | 1 | 4 | 65 | Horsemanship |
| Gun Section (2 guns) | 3 | 50 | 3.0 | 150 | 25 | 1 | 6 | 0 | 1 | 55 | Artillery Command |

- **Display names (v1.3):** the cannon unit (id `cannon`, unchanged) is shown as **Gun Section (2 guns)**, narrated as "gun section" (`units.cannon.narration_name`; `legacy_names: ["Cannon Battery"]`). 50 men and 2 guns is a historical gun section, not a 4-6 gun battery, which puts typical armies at about 2-5 guns per 1,000 men, the historical range. Every unit also has a `narration_name` (company, squadron, gun section). No number changed.
- **Strength = troops × toughness.** Damage is dealt in strength. The live troop count drops by `round(strength damage / toughness)`. Morale, elimination and timeout all use strength, so a point of any unit type is worth about the same.
- **Companies effective** = `alive troops / troops per company`. A half-dead company does half damage.
- **Canister:** cannon firing at distance ≤ 1 deals ×1.25. At distance 0 cannons fight melee only.
- **Speed:** armies move as one formation (§15.3), so V1 uses speed only for narration order and pursuit flavour. It is kept for later systems.
- **Targeting:** each enemy type's share of incoming damage = `alive troops × exposure (1.0) × preference`. Fire preferences: cannon → cavalry 1.2, cannon → cannon 0.8, everything else 1.0. Melee preferences: infantry → cannon 1.5, cavalry → cannon 1.6, everything else 1.0. Reserves can't be targeted.

Why: infantry is the cheap, durable anvil, cavalry the fast hammer, and cannon a long-range threat with few men that cavalry hunts.
Prototype, budget 14, mirror officers, all terrains: all-infantry 54%, foot + horse 54%, gun line 52%, horse 48%, combined 47%, mixed 47%. Every archetype falls in 47-54% overall, but terrain swings them (gun line 34% on Open Field and 67% at River Crossing; all-infantry 73% in Forest).

---

## 10. Building an army

The player picks unit counts within the officer's point budget (unspent points are lost). Up to 30% of the budget (rounded down, in whole units) may be marked **Reserve**. Reserves don't fight or take damage until committed (§14). They count in starting strength.
Example: a Major (14 pts) fields 5 infantry, 3 cavalry and 1 cannon (5 + 6 + 3 = 14), with 2 infantry in reserve (2 pts ≤ 4.2).

---

## 11. Formations and the officer AI  (`formations.json`)

The **player never picks the formation.** The officer does, after seeing the terrain and the enemy's composition (scouts), but not the enemy's formation or stance.

### 11.1 Cycle and matchup matrix

**Id policy (v1.3):** ids never change; display names may. The formation id `tight_wedge` is kept, and its display name is now **Attack Column** (`formations.json → formations.tight_wedge.name`, with `legacy_names: ["Tight Wedge"]`). Code, saves and logs key on ids only. The same rule applies to every JSON file (`units.json` and `formations.json → id_policy`).

**Attack Column > Pincer > Wide Line > Defensive Screen > Attack Column.** The diagonals (Column vs Line, Pincer vs Screen) are neutral.

`matchup_damage_mult[mine][theirs]` multiplies **all damage my army deals**:

| mine \ theirs | Wide Line | Attack Column | Pincer | Def. Screen |
|---|---|---|---|---|
| Wide Line | 1.00 | 1.00 | 0.94 | 1.07 |
| Attack Column | 1.00 | 1.00 | 1.07 | 0.94 |
| Pincer | 1.07 | 0.94 | 1.00 | 1.00 |
| Def. Screen | 0.94 | 1.07 | 1.00 | 1.00 |

**Why each link holds (v1.3, historical reasons; `formations.json → counter_reasons`, shown on the formation card and in the replay's formation panel, no new log event):**
- **Attack Column > Pincer:** the column punches through a centre the enemy thinned to reach round the flanks (Austerlitz 1805, Blenheim 1704).
- **Pincer > Wide Line:** the flank attack rolls up a long line where it is weakest, at its open end (Leuthen 1757, Cowpens 1781).
- **Wide Line > Defensive Screen:** a dense, braced defence is a big target; the wider line overlaps it and pours musketry into it from front and sides.
- **Defensive Screen > Attack Column:** steady troops waiting behind a skirmish screen break an assault column as it comes on (Bussaco 1810).

(The old prototype had the column losing to two formations. This fixes it into a clean cycle.)

### 11.2 Formation profiles

| Formation | Fire × | Melee × | Damage taken × | Advance + | Other |
|---|---|---|---|---|---|
| Wide Line | 1.08 | 0.92 | 1.00 | 0 | |
| Attack Column | 0.92 | 1.12 | 1.03 | +0.25 | |
| Pincer | 1.00 | 1.06 | 1.00 | 0 | cavalry melee ×1.03 |
| Defensive Screen | 0.98 | 0.96 | 0.97 | −0.25 | |

**D2 DECIDED 2026-11-22 (captain):** counter multipliers stay at ×1.07 for the winner and ×0.94 for the loser. The countered side should win 24-29% on average across the 4 cycle pairs, with each pair within 22-31% (QA check B5, `battle.json → balance_targets`).

Prototype (formations forced uniformly at random, all comps, terrains and stances): Wide Line 50.1%, Column 47.5%, Pincer 51.4%, Screen 51.0%. With the AI picking: Line 48.1%, Column 47.2%, Pincer 53.8%, Screen 51.4%. All are under the 55% cap. A countered formation wins about 28% on average (24.5-30.5% per pair), because 0.94 vs 1.07 is a big swing in a close fight. Per terrain, formations range from 40.8% (Column on Hill) to 56.9% (Pincer in Forest). See decision D2.

### 11.3 Officer AI: formation choice

For each formation f:
```
score(f) = compFit(f) + terrainFit(f) + stanceBias(f) + aggressionBias(f) + traitBias(f) + roleBias(f)
         + 5.0 × insight × counterValue(f) + noise × Gumbel()
```
- `compFit(f) = Σ_type share(type) × fit[f][type]`, where share is the fraction of **points** (not troops). Fit table: Line 0.30 inf / 0 cav / 0.20 can; Column 0.10 / 0.40 / 0; Pincer 0.15 / 0.30 / 0.05; Screen 0.10 / 0 / 0.35.
- `terrainFit(f) = 2.0 × (terrain.formation_mult[f] − 1)`.
- `roleBias(f)` is 0 in ranked battles. In a scenario it is the side's `ai_formation_bias` from `scenarios.json` (defender: Screen +0.15, Line +0.05, Column −0.15; attacker: Column +0.10, Pincer +0.10, Screen −0.15).
- `stanceBias` comes from `stances.json` (§13). `aggressionBias = perPoint[f] × (Aggression − 50)`. `traitBias` comes from Hothead.
- **Enemy prediction:** `P(e) = softmax over e of (compFit_enemy(e) + terrainFit(e)) / 0.15`. Then `counterValue(f) = Σ_e P(e) × (matchup[f][e] − 1)`.
- `insight = clamp((0.5 × BT + 0.3 × Wisdom + 0.2 × INT) / 100 + traitInsight, 0, 1)`.
- `noise = 0.03 + 0.22 × (1 − insight) + 0.001 × max(0, 50 − Temperament)`. Gumbel = `−ln(−ln(u))`, with u from the battle RNG (4 draws per side, in formation order Line, Column, Pincer, Screen).
- Pick the highest score.

Why: officers form up to suit their troops and ground, wise ones read the enemy and counter, and dim or hot-tempered ones are erratic. The player shapes the choice through army composition and stance but never dictates it.
Example: BT 60, Wisdom 40, INT 50 gives insight 0.52 and noise scale 0.136. A cavalry-heavy enemy is predicted to form a Column, so Screen's counterValue is about +0.05 and adds `5 × 0.52 × 0.05 ≈ +0.13` to Screen's score.
Prototype pick rates: Line 33%, Column 20%, Pincer 23%, Screen 23%.

---

## 12. Terrain  (`terrain.json`)

Both armies fight on the same ground in V1 (**D6 DECIDED 2026-11-22 (captain):** symmetric terrain for V1; attacker/defender sides are deferred to the world map or a DLC, see the note at the end of this section). Multipliers below 1 are penalties and get scaled by ADA and traits (§2, §6). Multipliers above 1 are bonuses and are not scaled.

| | Open Field | Forest | Hill | River Crossing |
|---|---|---|---|---|
| Advance + | 0 | −0.25 | −0.10 | −0.25 |
| Infantry fire | 1.00 | 0.85 | 1.05 | 1.10 |
| Cannon fire | 1.15 | 0.85 | 1.15 | 1.10 |
| Cavalry fire | 1.00 | 1.00 | 1.00 | 1.00 |
| Infantry melee | 1.00 | 1.05 | 1.00 | 0.85 |
| Cavalry melee | 1.10 | 0.80 | 0.85 | 0.75 |
| Cannon melee | 1.00 | 1.00 | 1.00 | 1.00 |
| Cannon range + | 0 | −1 | +1 | 0 |
| Cavalry reach + | 0 | −0.5 | 0 | 0 |
| Wide Line × | 1.03 | 0.95 | 1.03 | 1.03 |
| Attack Column × | 1.00 | 1.00 | 0.96 | 1.04 |
| Pincer × | 1.01 | 1.04 | 1.00 | 0.94 |
| Def. Screen × | 0.99 | 1.03 | 1.04 | 1.02 |

The formation multiplier applies to all damage that formation deals on that terrain.
Why: open ground rewards horse and guns, woods reward infantry and ambush, hills reward guns and dug-in lines, and rivers reward firepower over the ford while punishing melee and wide envelopments.
Example: a Pincer in Forest deals ×1.04 on everything. Cavalry melee there is ×0.80 (×0.818 with ADA 80) and the charge reach shrinks from 1 to 0.5.

**Future / deferred: attacker and defender sides (not in V1).** On Hill and River Crossing, one side would hold the crest or the far bank and stay put, and the other would have to attack. Prototype estimates, not proof (`prototype/roles_exp.py`, `final_roles.txt`; Major budget of 14 points only). At equal points the defender wins about **65% on Hill** and **59% on River Crossing**. Giving the attacker **+1 army point** brings both to about **50%** (49% and 50%). The modifiers tested are in `terrain.json → deferred_attacker_defender`. The resolver already takes terrain as data, so adding sides later is a table change plus one input field. Other budgets, and the officer AI's role-based formation lean, need their own balance pass when this returns. More detail is in discussion.md, topic B.

---

## 13. General stances  (`stances.json`), the player's choice

| Stance | Advance / tick | Holds at | Fire × | Melee × | Damage taken × | Rout threshold + | Auto-reserve tick | AI bias (Line/Column/Pincer/Screen) |
|---|---|---|---|---|---|---|---|---|
| Aggressive | 1.00 | – | 1.00 | 1.04 | 1.08 | −3 | 4 | 0 / +0.15 / +0.10 / −0.15 |
| Balanced | 0.75 | – | 1.00 | 1.00 | 1.00 | 0 | 6 | 0 / 0 / 0 / 0 |
| Cautious | 0.50 | distance ≤ 2 | 1.06 | 0.95 | 0.94 | +3 | 8 | +0.10 / −0.15 / 0 / +0.15 |

"Holds at" means a Cautious army stops advancing once the distance is ≤ 2 (it fires and waits).
Why: stance is the general's main lever. It tells the officer how much risk to take, and it nudges, but doesn't dictate, his formation.
Prototype stance matrix (row win %): Aggressive vs Balanced 53%, vs Cautious 50%. Balanced vs Cautious 47%. Cautious vs Aggressive 48.5%. All within 47-53%.

---

## 14. Messenger  (`messenger.json`). **D1 DECIDED 2026-11-22 (captain)**

One messenger per battle with one of two orders:
- **Rally:** when it arrives, morale `+= 0.12 × max(0, startMorale − morale) × (0.75 + 0.005 × Inspiration)`, and morale loss ×0.90 for the next 2 ticks.
- **Commit reserves:** when it arrives, all reserves join the front, and the whole army deals ×1.10 damage for 2 ticks (a flank attack). If no reserves are left, the messenger is wasted (logged `messenger_wasted`).

**Timing (applies to every send):** an order "sent at tick N" counts as leaving at the **end** of tick N. It arrives `1` tick later (+1 with Hesitant), at the start of tick N + delay, before movement. The earliest send is tick 1 and the latest is tick 19. If the battle ends before the arrival tick, the messenger never arrives (logged `messenger_lost`).

### 14.1 How the player sends it (decided)
The player has two ways to send the messenger, and may use one, both, or neither.

**A. Standing order (optional, set before battle).** `{action, condition, value}`, one condition per order:

| condition | meaning | range (step) | default |
|---|---|---|---|
| `morale_below` | own morale < value | 20-80 (5) | 45 |
| `strength_below_pct` | own strength (front + reserve) < value% of starting strength | 30-90 (5) | 60 |
| `enemy_morale_below` | enemy morale < value (press the advantage) | 20-80 (5) | 40 |
| `tick_reached` | tick index ≥ value | 1-19 (1) | 4 |

It is checked at the end of each tick, after the rout check, only if neither side has routed, using the post-tick state. Its send tick is the first tick whose check passes. New players get `rally / morale_below / 45` pre-filled.
Example: `rally, morale_below 45`. Morale ends tick 5 at 43.8, so it is sent at the end of tick 5 and the rally lands at the start of tick 6.

**B. Live click (only during the first viewing).** While the first playback is showing tick t, and the messenger is unsent and the battle undecided at t, the player can click Rally or Send Reserves.
- The click records `live_send_tick = t` and `live_action` into that army's battle input. The client re-runs the pure resolver with the same seed and the new input. Ticks 1..t come out identical because the order only takes effect at t + delay, so playback carries on from tick t + 1 with no jump.
- First-viewing controls: pause and 1×/2× speed only, with no rewind or scrubbing. "Skip to end" is allowed but forfeits any unsent live click; the standing order still applies.
- If the player quits mid-viewing, the battle is finalised with whatever was recorded so far (no click means `live_send_tick = null`). The standing order still applies.
- The battle counts against the daily limit when first viewing starts. Quitting does not refund it.

**Both exist → the first to trigger wins.** There is one messenger only. The order with the earlier send tick is used, and the other is cancelled (logged `standing_order_cancelled` or `live_click_ignored`). If both trigger on the same tick, the live click wins. Once the messenger has gone, the button is disabled for the rest of the viewing.
Example: the standing order is `rally morale_below 45` and fires at tick 5, so the live click button greys out from tick 5 onward. If the player had clicked "Send Reserves" at tick 3, the reserves order would be used and the standing order cancelled.

**Re-watches.** When the first viewing ends, the battle record stores the final inputs (both armies, including the messenger fields, plus terrain and seed) and the log. Re-watches replay that record. The messenger is fixed and can't be changed or added, and replays and share links re-derive an identical log from the stored inputs.

**Auto reserves:** if reserves are still waiting, the officer commits them himself (no bonus) at the stance's auto-reserve tick (4/6/8, Glory Seeker 4, Hesitant +2) or when morale < 45, whichever comes first.
**AI opponent:** always uses the standing order `rally / morale_below / 45` and never a live click.

Why: the live click keeps the player "the general" while it stays deterministic, because the click is just an input recorded at a turn index. The standing order covers players who don't want to watch. Rally rewards sending it at the right moment (late enough that a lot of morale has been lost, early enough to arrive before the rout), and reserves reward timing a flank attack.
Example (rally effect): start morale 62, current 40, Inspiration 60: `0.12 × 22 × 1.05 = +2.8` morale and 10% less morale loss for 2 ticks. In a close morale race that is often decisive.
Prototype: a good rally (sent when morale < 45) vs no messenger wins 59%. Reserves sent at tick 3 vs none: 56%. When both sides rally, sending it at the right moment beats a blind tick-3 send 53% of the time. **D8 DECIDED 2026-11-22 (captain):** rally stays at 12%. The UI label and narration spell the effect out ("+3 morale, and the men hold steadier for 2 turns"). The `rally` log event carries `morale_gain` for this, and the button tooltip uses `narration.json → rally_ui_label`. The D1 lock-in only fixed the control rules, so these numbers are unchanged.

---

## 15. Battle resolver

### 15.1 Contract (pure function)
```
resolve_battle(armyA: Dictionary, armyB: Dictionary, terrain_id: String, seed: int, scenario: Dictionary|null = null) -> {result, log}
army = { officer, stance, units:{infantry,cavalry,cannon}, reserve:{...},
         messenger:{ standing_order:{action,condition,value}|null, live_send_tick:int|null, live_action|null }, side_name }
```
- `scenario` is null for ranked battles and Skirmish. For a scenario it is the entry from `scenarios.json` (§21); the defender is always side B. It adds no RNG draws.
- No globals, clock, file IO or scene tree. All tables are passed in or loaded once into an immutable config.
- The same inputs and seed always give a byte-identical log. Use one `RandomNumberGenerator` (PCG32) seeded with `seed`, and draw in exactly this order: A formation noise ×4, B formation noise ×4, then each tick: A damage variance, B damage variance, A temperament noise, B temperament noise. A hidden trait never consumes a draw.
- Live play is a replay: the client runs the resolver, then animates the log. A live messenger click at displayed tick t sets `live_send_tick = t` and re-runs the resolver. Ticks 1..t are identical, so playback continues seamlessly (§14.1). Re-watches never re-run with new inputs.
- Later plug-ins (chain of command, PvP, world map) call the same function server-side.

### 15.2 Setup
1. Front troops = (units − reserve) × troops. Starting strength `S = Σ all units × troops × toughness`.
2. Each officer picks a formation (§11.3), A first, then B.
3. Start morale = strength-weighted mean of unit morale + `0.02 × (Leadership − 50)` + formation start add (all 0 in V1) + Born Leader 2, capped at 100.
4. Rout threshold = `25 + stance add − 0.03 × (EB − 50) + trait adds`.
5. Distance = 6.0 (hundreds of paces).

Example: 5 inf, 1 cav and 2 cannon give S = 500 + 140 + 300 = 940. Start morale `(500×60 + 140×65 + 300×55)/940 = 59.1`, and Leadership 70 makes it 59.5. Aggressive with EB 60 gives threshold `25 − 3 − 0.3 = 21.7`.

### 15.3 Tick loop (max 20 ticks)
1. **Orders:** messenger arrivals, then auto-reserves.
2. **Movement:** each side's advance = `stance.advance + formation.advance_add + terrain.advance_add (+ Rash)`, floored at 0. It is 0 if Cautious and distance ≤ 2. A scenario defender (`holds_position`) always has advance 0. `distance = max(0, distance − advA − advB)`.
3. **Combat** (simultaneous; compute both sides before applying). For each unit type with front troops:
   - If `distance ≤ reach` (reach = melee_reach + terrain reach add; cannons only at distance 0), it fights **melee**.
   - Else if `distance ≤ range` (range + terrain range add) and firepower > 0, it **fires** (canister ×1.25 for cannons at ≤ 1).
   - Else it does nothing.
   ```
   dmg = companiesEffective × stat
         × formation(fire|melee)_mult × formation.unit_melee_mult[type]
         × terrain(fire|melee)_mult[type] (penalties ADA/trait-scaled)
         × stance(fire|melee)_mult
         × (1 + 0.001 × (skill − 50))                    # unit skill
         × [melee only] (1 + 0.0006 × (ATH − 50)) × (1 + 0.001 × (Aggression − 50))
         × trait unit mults
         × matchup[myF][theirF] × (1 + 0.001 × (Wisdom − 50))
         × terrain.formation_mult[myF] (penalty-scaled)
         × variance (uniform 0.75-1.25, one roll per side per tick)
         × 1.10 if a messenger reserve bonus is active
         × [fire only] scenario defender fire_mult (1.15) when the scenario defender fires
   strengthDamage = dmg × enemy damage_taken (formation × stance × Aggression × traits × scenario walls damage_taken_mult if the target is the scenario defender)
   ```
   Split it across enemy front types by the targeting weights (§9). Troops lost = `min(alive, round(strengthDamage_type / toughness))`.
4. **Morale** for each side:
   - If it took casualties: `loss = 100 × (strengthLost + 0.25 × meleeStrengthLost) / S × 0.75`
     `× (1 − 0.001 × (EB − 50)) × (1 − 0.0006 × (Leadership − 50)) × trait mults × rally 0.90 (if active)`
     `× scenario defender morale_loss_mult (0.85, defender only)` `× (1 + uniform(−n, n))`, where `n = 0.30 × (1 − Temperament/99)`.
   - If it took no casualties: morale `+= 0.5 + 0.02 × (Inspiration − 50)`.
   - Clamp to 0-100. Then check hidden-trait triggers and hidden-attribute reveal triggers.
5. **Rout check:** a side routs if morale < its threshold or its strength (front + reserve) < 25% of S.
   - Exactly one side routs: the other wins and the battle ends.
   - Both rout: the larger `(morale − threshold)` wins, and equal is a draw.
   - **Scenario objective** (only when `scenario` is set), checked after the rout rule above in this order: if the defender routed or was eliminated, the attacker wins; else if the attacker routed, the defender wins; else if the attacker's strength is below `(1 − 0.40) × S_attacker` or the tick is ≥ 12, the defender wins (reason `objective`). Scenario battles therefore never reach the timeout.
   - Pursuit: the winner's cavalry deals `0.5 × melee` extra casualties to the router. This shows in the log and the troop counts but never changes the result.
6. **Timeout** after tick 20: `score = 0.5 × strength/S + 0.5 × morale/100`. Higher wins. A difference under 0.02 is a draw.

Example (one volley): 6 full infantry companies with Marksmanship 70 and Wisdom 60 fire from a Wide Line (Open Field) against a Defensive Screen at distance 2, variance roll 1.00: `6 × 6 × 1.08 × 1.00 × 1.00 × 1.02 × 1.07 × 1.01 × 1.03 = 44.1`. The Screen takes ×0.97, so 42.8 strength. The enemy front has 500 inf, 100 cav and 100 cannon troops, so the weights are 5:1:1. Losses: 31 infantry, `6.1/1.4 = 4` riders and `6.1/3 = 2` gunners, 42.6 strength in all. Against S = 940 that is `100 × 42.6/940 × 0.75 = 3.4` morale (before modifiers and noise).

Prototype: average battle length is 8.5 ticks and the draw rate is about 0.9%.

### 15.4 Result object
`{ winner: "A"|"B"|"draw", reason: "rout"|"eliminated"|"timeout"|"double_rout"|"objective", scenario_id: String|null, ticks, formations:{A,B}, final:{A:{troops by type, strength, morale}, B:{...}}, reveals:[...], growth_inputs:{units_fielded, outcome} }`

---

## 16. Event log, replay and narration  (`narration.json`)

The log is the only thing the replay and the narration read. Shape (JSON, version 1):
```json
{
  "v": 1, "seed": 123456789, "terrain": "hill", "inputs_hash": "sha1-of-canonical-inputs",
  "setup": {"A": {"formation":"wide_line","stance":"balanced","start_morale":59.5,"rout_threshold":24.7,
                  "troops":{"infantry":500,"cavalry":100,"cannon":100},"reserve":{"infantry":200}}, "B": {}},
  "ticks": [
    {"t": 1, "distance": 4.5,
     "state": {"A":{"troops":{"infantry":500,"cavalry":100,"cannon":100},"reserve":{"infantry":200},"morale":59.5},"B":{}},
     "events": [
       {"type":"advance","side":"A","distance":4.5},
       {"type":"cannon","side":"A","unit":"cannon","target":"B","casualties":{"infantry":18,"cavalry":3,"cannon":0}},
       {"type":"morale_shaken","side":"B","morale":38.2}
     ]}
  ],
  "result": {"winner":"A","reason":"rout","ticks":9}
}
```
- `state` is the **post-tick** snapshot (live troop counts per type, reserves and morale per side). The replay tweens between snapshots.
- Event types: `battle_start, formation_chosen, advance, hold, volley, cannon, canister, charge, melee, morale_shaken (first time below 45 and below 35), messenger_sent (with `source: standing_order|live_click`), standing_order_cancelled, live_click_ignored, rally, reserves_committed, auto_reserves, messenger_wasted, messenger_lost, trait_revealed, hidden_attribute_revealed, rout, pursuit, battle_end_win, battle_end_draw, scenario_held, scenario_losses_reached`. `volley` means infantry fire, `charge` means cavalry melee and `melee` means infantry melee.
- **Narration:** each event maps to a template list in `narration.json`. Variant = `hash(seed, tick, event_index) mod count`, so a replay narrates identically. To keep the feed readable, show at most 4 lines per tick in this priority order: rout > messenger/reserve/reveal > charge > cannon > volley/melee > advance.
- Example line: `"Round shot from the Blues tears into the ranks: 18 down."`

---

## 17. After a ranked battle (fixed order)
1. Record the result and the reveals.
2. Wisdom growth (§3).
3. Battle practice skill gains (§4).
4. Attribute growth roll (§2), using a separate seeded RNG: `seed2 = hash(seed, officer_id)`.
5. Promotion check (§8).

Skirmishes and scenario replays skip all five. A taken scenario assignment (§22) is a ranked battle and runs all five, with the scenario's Wisdom multiplier on a win (§3, §21).

---

## 18. Economy  (`economy.json`). **D11 DECIDED 2026-11-22 (captain): buy-to-play**

Line of Command is a **one-time Steam purchase at about $19.99**. There is no subscription, no in-game currency and no microtransactions. DLC comes later, under the never-sold list below. Every player has the same game.

**Daily limits (pacing, the same for everyone):**

| Limit | Value | Table |
|---|---|---|
| Ranked battles / day | 3 | `economy.daily_limits` |
| Breeds / day | 1 | `breeding.limits` (mirrored in `economy.daily_limits`) |
| Training clicks / day | 6, max 3 on any one officer | `skills.training` (mirrored) |
| Roster slots | 20, manual release, pedigree ghosts (**D10 DECIDED 2026-11-22 (captain)**) | `breeding.roster` (mirrored) |

Why: the prototype showed that without limits a heavy grinder's best officer beats a 1-battle-a-day player's about 91% of the time after a month (discussion.md, topic A). The limits keep that gap bounded.

**Unlimited, no progress (D4 DECIDED 2026-11-22 (captain)):** Skirmish vs AI and scenario replays are free and unlimited for everyone. They write nothing to an officer: no XP, Wisdom, skill or attribute growth, rank progress, trait or hidden reveals, and no breeding-eligibility count. Every ranked battle, including a scenario, is taken as an assignment from the daily board and uses one of the 3 daily ranked battles (§22).

**In the base game:** an unlimited replay archive; replay controls (play/pause, 4× speed, scrubbing, a per-tick stat overlay); default uniforms, banners and portrait frames; the house heraldry editor.

**DLC allowed:** new theatres and terrain packs, scenario packs, campaigns, cosmetics (uniforms, flags, house crests, narrator voices, replay themes), and a replay studio (slow motion, GIF/MP4 export, share links).

**Never sold:** officers, bloodlines, breeds, traits or trait reveals, attribute/skill/Wisdom points or boosts, extra daily ranked battles, breeds or training clicks (timer skips), rerolls, buyer-only formations, units or stances (new ones ship free to all and unlock through play), loot boxes or random paid rolls, owner-only PvP maps, and crypto/NFTs/tokens.

**Proof of no stat advantage.** Every progression input is one of: ranked battles (3/day), breeds (1/day), training clicks (6/day), Wisdom/skill/attribute growth (only from ranked battles and clicks), and trait reveals (only in ranked battles). Every limit is the same for every player, and no purchase touches any of them. Skirmishes and scenario replays write nothing to an officer. QA check E5 in `sim-plan.md` proves that owning any DLC or cosmetic changes no progression or battle number.

Daily reset is at 00:00 UTC (**D9 DECIDED 2026-11-22 (captain)**).

---

## 19. Decided balance targets and prototype estimates (not proof)

**D3 DECIDED 2026-11-22 (captain):** a +20 total officer edge (every innate attribute, Wisdom and skill +20) targets about **64%**, with a QA band of 60-65% (B2). Leadership stays the strongest single skill (B3b). No single stat at +20 may exceed 56% (B3). These are recorded in `battle.json → balance_targets`. The current officer coefficients in §2-§5 meet all three.

Throwaway Python sim in `/workspace/sim` (copy in `prototype/`) that reads these JSON files. Hidden traits, pursuit and narration were not simulated.
- Officer edge (every visible stat +X, random comps, terrain and stances, 6,000 battles): **+10 → 57.4%, +20 → 64.1%, +30 → 70.6%.** This meets the D3 target (about 64%, band 60-65%).
- Single-stat +20 (5,000 battles each, D3 cap 56%): Leadership 53.3% (strongest skill, as decided), Bravery 52.8%, Artillery Command 51.8%, the rest 50.6-51.6%.
- Formations: overall 47.5-51.4% when forced and 47.2-53.8% when AI-picked. All are under 55%. Counter matchups win 68-75%.
- Compositions: 47-54% overall. Stances: 47-53%.
- Messenger: smart rally vs none 59%. Smart vs blind (both sending) 53%.
- Breeding: about 90% of children within ±6 of the midparent. Carrier × carrier shows a recessive 24.2% of the time. A homozygous founder bred to random mates: the child shows it 28.5%, grandchild 16.6%, gen 5 5.5%. In 20% of lines the trait skips the child and reappears within 5 generations.
- Battles last 8.5 ticks on average. Draws are about 0.9%.
- Scenarios (§21, `prototype/scenarios_final.py`, 24,000 seeded runs each): Hold the Fort (walls ×0.68) defender wins **47.5%** (target 47%, band 44-50%), **40.5%** with an officer 10 points weaker. Last Stand (walls ×0.735) **34.6%** (target 35%, band 32-38%), **29.2%** with an officer 10 points weaker. The prototype does not simulate messengers in scenarios, and the player's garrison is a random legal 10-point army, so real players who build well will do somewhat better; QA S1-S2 re-measure it in the engine.

## 20. Explicitly out of V1
Chain of command (officers under officers), PvP, world map, Foxhole/EU4 layering, officer age/death/retirement, schools, equipment, weather, attacker/defender sides on normal maps (D6, deferred; §12; only the scenario maps in §21 have sides). Plug-in points: `resolve_battle` is pure and versioned (`log.v`), armies are plain dictionaries, and terrain is an id plus a table.

---

## 21. Scenario maps  (`scenarios.json`). **D12 DECIDED 2026-11-22 (captain)**

Two hand-made fort scenarios ship in V1, as a proving ground for young officers. Both are open to **Lieutenant and Captain** officers. The player is always the defender (side B); the AI is the attacker (side A). The terrain is Open Field.

| | Hold the Fort | Last Stand |
|---|---|---|
| Garrison (player) | 10 points, any stance, reserve and messenger as normal | same |
| Attacker (AI) | 14 points, built by the ranked-opponent rules (§8: officer = player officer + uniform(−10, +10), archetype army, 20% reserve, standing order rally/45), stance Aggressive or Balanced only | same |
| Walls: damage the garrison takes | **×0.68** | **×0.735** (a broken earthwork) |
| Garrison fire / morale loss | ×1.15 / ×0.85, and it never advances | same |
| Garrison wins if | it holds **12 turns**, or the attacker loses **40%** of its strength, without routing first | same |
| Target defender win rate (QA band) | **47%** (44-50%) | **35%** (32-38%) |
| Wisdom on a win | **×1.06** | **×1.43** |

**Historical odds (v1.3, story only):** real forts were stormed at about 3-6 attackers per defender (Yorktown Redoubt 10, 1781, about 6:1 and taken; Fort Wagner, 1863, about 2.8:1 and repulsed). The battle stays 14 vs 10 points. The briefing, blurb and narration tell the larger odds as story: the garrison faces the vanguard of a column three times its size, and the rest is still on the road (`scenarios.<id>.blurb`, `historical_odds_note`; `narration.json → briefing_scenario`, `scenario_held`). Literal 3:1 odds would need walls ×0.23 and a 30-point attacker, beyond a General's budget, so they are deferred (§23).

**Wisdom pay rule:** `wisdom_win_mult = min(2, 0.5 / target_defender_win_rate)`, rounded to 2 decimals, applied on a win only. A loss uses the normal loss multiplier (×1.25).
Why: harder wins pay more. Losses already pay ×1.25, so the expected Wisdom per attempt is about +3% (Hold the Fort) and +17% (Last Stand) against a normal 50% ranked battle. That is capped by the 3 daily battles and offset by fewer wins toward rank, so scenarios are not a farm (QA S3b).

**Daily rule (v1.1):** a scenario is a ranked battle only when the player takes a scenario assignment from the daily board (§22). That uses one of the 3 daily ranked battles and gives full progress: Wisdom, skills, the attribute roll, rank counts, reveals and the breeding-eligibility count. Any other play of a scenario is a **replay**: free, unlimited, no progress and no battle used (D4).

**Balancing rule:** each scenario has a target win rate and a QA band, measured in simulation over random garrisons and officers (sim-plan S1-S4). If the measured rate leaves the band, re-tune only the walls `damage_taken_mult` (in the prototype each 0.01 moved it about 3 points for Hold the Fort and about 1.7 points for Last Stand).

Example: a Lieutenant with INT 50 and Wisdom 30 wins a Hold the Fort assignment: `gain = 2.0 × (1 − 30/80) × 1.0 × 1.06 = 1.33` Wisdom, and that day it has 2 ranked battles left.

---

## 22. Campaign map and daily assignments  (`campaign.json`). **D13 DECIDED 2026-11-22 (captain), v1.1**

The 3 daily ranked battles are presented as **assignments from the war general** (General Hawthorne, of the Blues) on a small campaign map. It is still solo against NPC opponents. Nothing here changes a battle or progression number: an assignment is an ordinary ranked battle (or scenario) with a location attached.

**Map.** There are 10 fixed locations. Terrain stays symmetric (D6). Each location has a controlling side: in V1 this is flavour, but it is a real field so a shared war can use it later.

| Location | Terrain | Fort | Start controller | Adjacent to |
|---|---|---|---|---|
| Ashford Crossroads | Open Field | | Blues | Fort Corwen, Harrow Wood, Kestrel Ridge |
| Fort Corwen | Open Field | yes | Blues | Ashford Crossroads, Blackwater Ford, Harrow Wood |
| Harrow Wood | Forest | | Blues | Ashford Crossroads, Fort Corwen, Millbrook Bridge, Kestrel Ridge |
| Kestrel Ridge | Hill | | Blues | Ashford Crossroads, Harrow Wood, Blackwater Ford |
| Blackwater Ford | River Crossing | | Blues | Fort Corwen, Kestrel Ridge, Saint-Aubin Redoubt, Greyfriars Heights |
| Millbrook Bridge | River Crossing | | Reds | Harrow Wood, The Thornwood, Saint-Aubin Redoubt |
| Saint-Aubin Redoubt | Open Field | yes | Reds | Blackwater Ford, Millbrook Bridge, Greyfriars Heights, The Thornwood |
| Greyfriars Heights | Hill | | Reds | Blackwater Ford, Saint-Aubin Redoubt, Castle Varne |
| The Thornwood | Forest | | Reds | Millbrook Bridge, Saint-Aubin Redoubt, Castle Varne |
| Castle Varne | Open Field | yes | Reds | Greyfriars Heights, The Thornwood |

Fort locations are Open Field because both scenarios are fought on Open Field (§21). A standard battle can also be offered at a fort.

**The daily board.** At 00:00 UTC the game generates **6 options**; the player takes up to 3 (the existing daily limit).
- **Seed:** `hash32("loc-board-v1", scope_id, day_index)`. In V1, `scope_id` is the account id; a shared war would pass the war id instead. `day_index` is whole days since 2026-01-01 00:00 UTC. The RNG is the same PCG32 the battles use.
- **Input (the snapshot):** the board is built **once per day, the first time the player opens it after that day's 00:00 UTC reset**, from the set of ranks in the roster at that moment. The game may not be running at 00:00 UTC, which is why the snapshot is taken when the board is first opened rather than at the reset itself. The seed is unchanged.
- **Frozen:** once built, the board does not regenerate that day. Later breeding, releases or promotions don't change it, and the same scope, day and snapshot ranks always give the same board.
  - If an officer on the snapshot is released or promoted later that day, the options stay. Eligibility is checked **at pick time** against the picking officer's current rank (own rank or one below).
  - Changing the roster before opening the board only changes which ranks get covered. Board outcomes give no extra rewards, so there is nothing to gain.
- **Steps:**
  1. **Cover every owned rank.** Take the lowest owned rank r and add a standard option at r (it suits officers of rank r and r+1). Remove r and r+1 and repeat. This needs at most 3 options, and the first one always fits the lowest-rank officer.
  2. **Scenarios** (only if the player owns a Lieutenant or Captain): draw the count with weights 0 : 40%, 1 : 45%, 2 : 15%. With 2, offer one of each; with 1, Hold the Fort 65% / Last Stand 35%. Scenarios go only at fort locations.
  3. **Fill** the remaining slots with standard options at ranks drawn uniformly from the owned ranks.
  4. **Locations:** scenarios draw distinct forts; standard options draw distinct unused locations, uniformly.
  5. **Variety:** while the board has fewer than 3 distinct terrains, move the last standard option not yet moved to an unused location of a missing terrain.
  6. **Order and text:** sort by rank, with scenarios last. `option_id = "<day_index>-<slot>"`. The brief comes from `narration.json → briefing_standard | briefing_scenario`, with variant `hash(seed, slot) mod count`.
- **Each option shows:** location, terrain, type (standard or scenario), rank and eligible ranks, point budget, the general's brief, and `wisdom_win_mult` (1.0 for standard battles; the §21 value for scenarios). There is no new reward lever.

**Rank rule (kept simple).** An officer may take an option of **their own rank or one rank below**. Both armies use the option's point budget, and the opponent comes from the existing generator (§8: officer ±10, archetype army). There is no fighting above your rank, so there is no new disadvantage rule. Scenarios are open to Lieutenants and Captains, with the budgets in §21.

**Picking.**
- Assigning an officer to an option uses one of the 3 daily ranked battles, and each option can be taken once.
- **An officer may take up to 3 assignments a day** (all 3 daily battles; **D13, captain, 2026-11-22**). The account cap stays 3 (`economy.daily_limits`). One officer can reach General in about 27-28 days (§8).
  - A new account has 3 starter Lieutenants (§7, D14), so all 3 battles can be used from day 1.
- Unused options expire at the next reset. Nothing banks.
- **Battle seed:** `hash32(board seed, option_id, officer_id)`.

**Outcome (cosmetic only).** A win flips the location's flag to the Blues in the player's own campaign view; a loss shows the Reds' flag. Narration names the location (`location_battle_start`, `location_won`, `location_lost`). There are no extra rewards, and control never affects anything else in V1.

Example: an account with a Lieutenant, two Captains and a Major gets standard options at Lieutenant (covering Lieutenant and Captain) and Major (covering Major and Lieutenant Colonel), say 1 Hold the Fort at Fort Corwen, and 3 more standard options. The player sends a Captain to Kestrel Ridge (Hill, Lieutenant option, 10 points each side), the other Captain to Hold the Fort, and the Major to a Major option at Blackwater Ford (River Crossing, 14 points each side). That uses all 3 battles.

Prototype (`prototype/board.py`, 10,000 generated days, random rank mixes): no rule violations, and every board regenerated identically. Distinct terrains per board: 3 on 44% of days, 4 on 56%. Terrain share of options: Open Field 42.5%, Forest 19.0%, Hill 19.4%, River 19.1%. Routing battles through the board changed the player's win rate by 0.6 points (no edge) and 0.1 points (+20 edge) against direct ranked battles (`board_balance.py`, 20,000 battles each).

### 22.1 Forward compatibility: the shared war (not in V1)

The following are designed in now so a shared Foxhole-style war can reuse them:
- **Fields:**
  - `campaign.sides` and `locations[].controller`;
  - `option.side` (always `blues` in V1);
  - `board.seed.scope_id`: account id now, war id later, so every player in a war sees the same board.
- **Contributions log:** every finished assignment appends `{war_id (null in V1), day_index, option_id, location_id, side, officer_id, rank, result, reason, ticks, final strengths}` to the account. A war server would add these up per location.
- **NPC fill-in:** `fill_npc(side, rank, seed)` returns an officer and an army from the existing opponent generator, which V1 already uses for every opponent. A war would call the same function when a side is short of humans.
- **Not in V1:** shared world state, front lines moving or control changing from results, choosing a side, PvP, server-side war ticks, and any reward for controlling ground.

---

## 23. Deferred / DLC ideas  (v1.3, from the Military Historian's research; not in V1)

None of these is in V1, and none changes a V1 number. The reasoning and test numbers are in `historian-assessment.md`.
- **Arm-vs-formation counters:** cavalry struggles against squares, guns punish columns and squares, cavalry catches lines. This is a small engine change (one lookup of unit type × enemy formation) plus a re-tune. Even ±5% moved Attack Column to 42% forced (band 45-55%), so it needs a balancing pass. It belongs with a formation DLC or a V1.x balance pass.
- **New formations:** Square (best as an officer reflex skill against cavalry), Open Order / skirmishers (strong in Forest, weak to cavalry in the open), Ordre Mixte (a default for low-skill AI officers), Oblique / Echelon attack, and a Reverse-slope defence (Hill only, cuts artillery damage; needs attacker/defender sides, D6).
- **Morale-conditional counters:** a column beats a shaken line but loses to a steady one.
- **A reserve bonus** for committing the reserve against a disordered enemy (Fontenoy, Cowpens).
- **"Scale the token":** a point means a company at low rank and a battalion, regiment or division higher up, so shown troop counts grow about 5-10× per rank while the maths stays the same. This touches the live counter, replay and narration (QA B18), so it is a small engine change. It fits the chain of command and world map.
- **Paper vs field strength:** units arrive under strength after campaigning (shared-war layer).
- **Real fort and siege odds (3:1 and more):** for sieges on the world map or in a DLC, where the attacker isn't limited by a rank budget.
- **A cannon cap** (e.g. at most 1 gun section per 3 infantry companies): tested and declined for V1, because it pushed formation results out of their bands (Wide Line 44.2%, Pincer 56.0%, +20 officer 65.7%). It would need a re-tune. The Gun Section label covers the history.
- **The Attack Column > Pincer strength** (×1.10 / ×0.91 for that one pair) is **awaiting the captain**; v1.3 keeps ×1.07 / ×0.94 (D2).
