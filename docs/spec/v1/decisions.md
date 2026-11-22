# Line of Command V1: Design Decisions (all decided)

Ranked by importance, one decision per section. Every decision below was made by the captain on 2026-11-22; the spec and the JSON use exactly these answers.

**Status (2026-11-22): spec v1.4** (SD-4 balance fixes for B5, B14, B15; no decision changed). D1-D14 are all decided by the captain. D2 (×1.07 / ×0.94) is unchanged and now passes B5 in the prototype without the ×1.10 / ×0.91 proposal, so that proposal is optional (numbers under D2). There are no open decisions. There are no open questions. Deferred ideas are listed at the end.

---

## D1. How does the player send the messenger?  **DECIDED 2026-11-22 (captain)**

**Decision:** a live click during the first viewing of the battle (no rewind), plus an optional standing order set before battle (e.g. "rally below 45"). This was the recommended option.
- The click records the turn being shown into the battle input, and the battle is recalculated from the same seed, so everything up to that turn is unchanged and replays stay reproducible.
- Standing orders can be set on own morale, own strength %, enemy morale, or turn number.
- If both exist, whichever triggers first is used. There is one messenger only, and on a tie the live click wins.
- Re-watches can't change the messenger.
- Full rules: spec.md §14.1 and `messenger.json`. QA checks: B19-B22.

---

## D2. How hard should formation counters hit?  **DECIDED 2026-11-22 (captain)**

**Decision:** keep the recommended strength. The formation that wins the matchup deals ×1.07 damage and the countered one ×0.94. The countered side should win about 24-29% of battles on average (QA check B5; each pair must stay within 22-31%). Prototype: 28% on average. A +20 officer in the wrong formation still loses 59% of the time, so formation outweighs officer quality as the brief wants.

**v1.4 note (SD-4, no change to the decision):** Lead Dev's M1 run had Pincer countered by Column at 35.8% (B5 band 22-31%). The cause was the Column's own fire (×0.92), not the counter strength, so v1.4 sets `formations.tight_wedge.fire_mult` to 1.00 and keeps ×1.07 / ×0.94. Prototype estimates, not proof (20k battles per orientation):

| Option | Pincer countered by Column | Mean of 4 pairs | Changes D2? |
|---|---|---|---|
| v1.3 as built | 35.3% (engine 35.8%) | – | – |
| **v1.4: Column fire ×1.00, counters ×1.07 / ×0.94** | **29.2%** | 28.2% (pairs 25.9-29.2%) | no |
| Historian's proposal instead: Column > Pincer ×1.10 / ×0.91, fire ×0.92 | 26.8% | – | yes (captain) |

The ×1.10 / ×0.91 proposal lowers the Pincer's rate; it does not push it out of the band. It is no longer needed to pass B5. The captain can still choose it for historical flavour, but then the pair should be re-measured with the v1.4 fire value, because both together would make that one pair sharper still.

---

## D3. How strong should the officer edge be?  **DECIDED 2026-11-22 (captain)**

**Decision:** keep the recommendation.
- An officer who is 20 points better across the board wins about **64%** of the time (QA band 60-65%, check B2). Prototype: 64.1%.
- Leadership stays the strongest single skill (check B3b). Prototype: 53.3%.
- No single stat at +20 may give more than 56% (check B3).

---

## D4. Skirmish and scenario replays  **DECIDED 2026-11-22 (captain)**

With no subscription there is no paid tier to gate anything behind. **Skirmish vs AI and scenario replays are free and unlimited for everyone, and they give no progress** (no Wisdom, skills, attributes, rank, reveals or breeding-eligibility count). QA check E2 proves they write nothing. Data: `economy.json → unlimited_no_progress_modes`.

---

## D5. How fast should breeding improve a bloodline?  **DECIDED 2026-11-22 (captain): sd 4**

Every child lands near the parents' average, with a random wobble (sd 4). Breeding the best to the best improves the roster about +0.5 per generation. Above 80 it slows sharply.

| Wobble (sd) | Predictability (within ±6 of the parents' average) | Gain per generation (approx.) |
|---|---|---|
| 3 | about 95% | about +0.35 |
| **4 (decided)** | about 90% | about +0.5 |
| 5 | about 77% | about +0.7 |

With 1 breed a day, a dedicated player gets a solid "60s" bloodline in about a month and elite 80s over several months.
**Decided: 4 (as recommended).** It's predictable, like PhotoFinish (you can see the likely range before you breed), with enough surprise for good days.

---

## D6. Should Hill and River Crossing have an attacker and a defender?  **DECIDED 2026-11-22 (captain): symmetric for V1**

Both armies fight on the same ground in V1. Attacker/defender sides are **deferred**, to arrive with the world map or a DLC. The prototype findings are kept in spec.md §12 ("Future / deferred") and discussion.md, topic B: at equal points the defender wins about 65% on Hill and 59% on River Crossing, and +1 army point for the attacker brings both to about 50%.

---

## D7. Can players see hidden "carrier" traits?  **DECIDED 2026-11-22 (captain): B**, shown once any relative has shown the trait

An officer may carry a recessive trait they don't show.

- **A. Never shown.** Pure surprise, but frustrating for serious breeders.
- **B. Shown once any relative in the pedigree has shown it (decided).** Watching bloodlines pays off, and the breeding preview gives odds for known alleles.
- **C. Always shown.** Predictable, but no "skipped a generation!" surprise.

**Decided: B (as recommended).**

---

## D8. How strong should the Rally be?  **DECIDED 2026-11-22 (captain): A**, keep 12%, with clearer UI and narration

Rally restores 12% of the morale lost so far (adjusted by Inspiration), and it softens morale loss for 2 turns. On screen that can look small ("+3 morale"), but battles are close morale races, so it swings about 9 points of win rate.

- **A. Keep it (decided)** and make the narration and UI show "+3 morale, steadier for 2 turns."
- **B. Make it 20%:** a more visible effect, but the messenger becomes about 63% vs not using it.

**Decided: A (as recommended).**

---

## D9. When do the daily limits reset?  **DECIDED 2026-11-22 (captain): A**, 00:00 UTC

- **A. 00:00 UTC (current):** one global reset, simplest, but mid-day for some players.
- **B. Local midnight:** friendlier, but you need to stop clock-changing abuse (pin the time zone once a week).

**Decided: A (as recommended).**

---

## D10. Roster size  **DECIDED 2026-11-22 (captain)**

The roster stays at **20 slots**, with manual release and pedigree ghosts (released officers stay in family trees). There is no ageing or retirement in V1. Data: `breeding.json → roster`.

---

## D11. How is the game paid for?  **DECIDED 2026-11-22 (captain): buy-to-play**

- **One-time Steam purchase at about $19.99.** There is no subscription, no in-game currency and no microtransactions.
- **Daily limits kept as pacing, the same for everyone:** 3 ranked battles, 1 breed, and 6 training clicks (max 3 per officer) a day, resetting at 00:00 UTC.
- **DLC later.** Allowed: theatres and terrain packs, scenario packs, campaigns, cosmetics, a replay studio. **Never sold:** officers, bloodlines, breeds, traits, stat points or boosts, extra daily battles/breeds/drills, rerolls, buyer-only formations/units/stances, loot boxes, owner-only PvP maps, crypto/NFTs.
- QA check E5 proves that no purchasable item changes any progression or battle number.

Data: `economy.json`; spec.md §18. The reasoning and prototype numbers are in discussion.md, topic A. The stopped subscription study is kept in `prototype/longsim.py` and `d11_out.txt` for the record.

---

## D12. Scenario maps  **DECIDED 2026-11-22 (captain)**

- **Hold the Fort** ships in V1, a bit easier than first proposed. A 10-point garrison (Lieutenant or Captain officer) holds against a 14-point AI attacker on Open Field. It wins by holding 12 turns or inflicting 40% losses. **Target 47% (QA band 44-50%)**; walls ×0.68 measured **47.5%** (24,000 seeded prototype runs) and 40.5% with an officer 10 points weaker. Wisdom on a win ×1.06.
- **Last Stand** (the Systems Designer's addition, a harder step on the same rules): walls ×0.735, **target 35% (band 32-38%)**, measured 34.6% and 29.2% with a weaker officer. Wisdom on a win ×1.43.
- Wisdom pay = `min(2, 0.5 / target)`. Since v1.1, a scenario is a ranked battle only when taken as an assignment from the daily board (D13). That uses one of the 3 daily ranked battles and gives progress; any other play is a free replay with no progress.

Data: `scenarios.json`; spec.md §21; QA S1-S6.

---

## D13. Daily battles as assignments from the war general  **DECIDED 2026-11-22 (captain), spec v1.1; per-officer cap v1.2**

The 3 daily ranked battles are picked from a board of 6 assignments on a 10-location campaign map. Solo vs NPC. Outcomes are cosmetic (a personal map flag and narration). The Systems Designer's calls within it:
- An officer may take an assignment of its own rank or one rank below.
- **Per-officer cap: DECIDED 2026-11-22 (captain):** one officer may take up to **3 assignments a day** (all 3 daily battles). The account cap stays at 3. One officer reaches General in about 27-28 days (prototype median 28).
- Up to 2 scenarios a day, only at forts.

Data: `campaign.json`; spec.md §22; QA C1-C9. A shared Foxhole-style war is future work (spec §22.1).

---

## D14. First roster size  **DECIDED 2026-11-22 (captain)**

New accounts start with **3 Lieutenants** from the normal new-officer rules (attributes 20-60, 1 visible strength and 1 visible weakness). Their visible strengths and weaknesses are all different. V1 has no sex mechanic, so any 2 unrelated officers can breed; all 3 starter pairs are legal on day 1, and the first breed can happen on day 2 (each parent needs 3 ranked battles). Data: `breeding.json → starter_roster`; spec.md §7; QA R10.

---

## Deferred ideas (not in V1, kept so they aren't lost)

- **Attacker/defender sides on normal maps (D6).** For the world map or a DLC. Prototype: at equal points the defender wins about 65% on Hill and 59% on River Crossing, and +1 attacker point brings both to about 50%. Modifiers are in `terrain.json → deferred_attacker_defender`, and the details are in spec.md §12 and discussion.md, topic B.
- **Banking unused daily battles (up to 7 days)** so weekend players keep pace. This was suggested in discussion.md but not simulated or adopted.
- **More scenarios** (scenario packs are on the DLC-allowed list). Each one needs its own target win rate, band and Wisdom multiplier, using the §21 rule.
- **Subscription study (stopped).** Results are kept in `prototype/longsim.py` and `d11_out.txt` for the record.
- **Shared Foxhole-style war** (pick a side, NPC officers and armies fill in when humans are short): hooks are in spec §22.1 and `campaign.json → shared_war_hooks`.
- Already out of scope from the brief: chain of command, PvP, world map, Foxhole/EU4 layering, ageing and retirement.
- **From the Military Historian's research (v1.3; spec §23, `historian-assessment.md`):** arm-vs-formation counters (needs a re-tune), new formations (Square, Open Order, Ordre Mixte, Oblique/Echelon, Reverse-slope), morale-conditional counters (column vs shaken line), a reserve bonus against a disordered enemy, "scale the token" troop display per rank, paper vs field strength, real fort/siege odds (3:1 and up), and a cannon cap (tested and declined for V1: it pushed formation results out of their bands).
