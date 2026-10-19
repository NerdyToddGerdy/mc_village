# Slice 2 Spec — A Functioning Village

Companion to `block-village-design-brief.md` and `slice-1-spec.md`. Slice 2 builds on everything in Slice 1; this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table (§12).

Tracking issue: #11. Decisions settled with the owner while writing this spec:

| Question | Decision |
|---|---|
| Needs (#18) | **Food only.** No rest or happiness yet. |
| First food | **Wheat → bread**, plus **meat from sheep**. |
| Jobs | Every resident has a **level in every job**, rising with practice, plus **on/off toggles and priorities**. You can still give direct orders. |
| Skill effect | Higher levels work **faster and give better results**. |
| Recruitment (#24) | **No free bed, no arrival**, as in Minecraft. |
| Beds | A **bed is part of every house** (its last construction stage) and needs wool. |
| Job buildings | **Start simple and evolve in place.** Cooking starts at a **fireplace**, placed with room reserved for it to become a kitchen later. Every job building reserves the space its upgrade needs. |
| Sheep | **A few roam the clearing** at the start, enough for Ada's and Tomas's beds. When they're gone, **a trip to a meadow** off the map finds more. |
| Wool and meat | **Hunting** a sheep drops 1 wool and 1 raw mutton. No shearing or breeding yet. |

## 1. Scope and done criteria

Slice 2 is done when, from a fresh start, a player can:

- [ ] Hunt the clearing's sheep for wool and mutton.
- [ ] Finish both opening houses including their beds, then welcome Tomas (who now needs a free bed).
- [ ] Paint a farm, watch wheat be planted, grow and get harvested.
- [ ] Build a fireplace, with its kitchen space reserved, and see residents bake bread and cook mutton.
- [ ] See residents get hungry, fetch food and eat, and see a clear reason when there's no food.
- [ ] Turn jobs on and off and set priorities per resident, and watch skill levels rise with work.
- [ ] Have a toolsmith keep spare tools stocked, so broken tools get replaced without the player.
- [ ] Send a resident to the sheep meadow and have them come back with wool and mutton.
- [ ] Build a third house with its bed and have a new traveler arrive.
- [ ] Understand every stall from its on-screen reason alone.

## 2. Changes to Slice 1 rules

- **A bigger clearing:** the map grows from 18×18 to **32×32** (provisional), with proportionally more trees (about 40) and boulders (about 16).
  - There's room for a third house, farm plots, the fireplace and the reserved plots that let buildings grow.
  - Ada starts near the middle, and the camera opens on her.
  - Saves record the map size, so older 18×18 saves keep their size.
- **House stages** become Foundation → Walls → Roof → **Bed**. The bed stage costs 3 wool and 3 planks, and the bed is placed inside, against the wall opposite the door.
- **The clearing starts with 6 sheep**, enough wool for the two opening beds.
- **Arrivals need a free bed** (§7). Tomas comes once the second house, bed included, is finished.
- **Ada's house** is hers when its bed is finished, not when its roof is.
- **Slice 1 goals** gain "Hunt sheep for wool" before Ada's house. The founding checklist otherwise stays.
- **Tool breakage:** while anyone has the Toolsmith job switched on, a resident whose tool breaks fetches a spare instead of stopping (§6). With no toolsmith, the Slice 1 rule holds: they stop and report.

## 3. Sheep, hunting and the meadow

**Sheep** are animals that wander slowly within the clearing, avoiding trees, boulders and buildings. Six start in the clearing. None arrive on their own (regrowth is an open question, §13).

**Hunt order** (default key **G**): click or drag over sheep to mark them, as with Mine. A resident with Hunt switched on walks to the sheep, following it if it moves, and hunts it. A hunt drops **1 wool and 1 raw mutton** where the sheep stood. No tool is needed. Higher Hunt levels hunt faster.

**The sheep meadow** is a place off the map, reached from a signpost at the map's left edge.
- Select one or two residents and choose **Send to the meadow** in the resident panel.
- They walk off the map and are **away** for the trip time. While away, they don't work in the village; the panel shows when they'll be back.
- They return carrying what they found: **2 sheep's worth per resident** (2 wool and 2 raw mutton each), limited by what the meadow has.
- The meadow holds **8 sheep** to start. When it's empty, the trip returns with nothing and the meadow shows as "No sheep left".
- This is a deliberately small taste of Slice 3's expeditions: someone leaves, the village works without them, and they come back carrying something.

## 4. Food and hunger

**Food items:** wheat, bread, raw mutton, cooked mutton. Residents eat bread and cooked mutton. Raw mutton can be eaten in a pinch for less.

**Hunger** runs from 100 (full) to 0 and drops steadily, emptying in about 6 minutes of game time.
- **Eating:** below 40, a resident's next job is to fetch the nearest food and eat it. Food is eaten where it's picked up; no tables yet.
  - Bread restores 50, cooked mutton 60, and raw mutton 20.
- **Hungry** (below 25): works 25% slower. The resident panel shows "Hungry".
- **Starving** (0): stops working, and the stuck list shows "Starving: no food stored". There's no death in Slice 2, since death is an open decision (#20). They recover as soon as food exists.
- **Away residents** (on a meadow trip) don't get hungry while away.

**Farms.** **Farm** order (default key **P**, plant): paint a farm plot over open grass, as with a stockpile.
- A resident with Farm switched on **plants** each empty cell (2 seconds, no seeds needed).
- Wheat **grows** for 2 minutes, drawn as rising stages.
- When ripe, a farmer **harvests** it (2 seconds) for 2 wheat, and the cell goes back to empty.
- Ripe wheat that isn't harvested waits; it doesn't spoil.

**Fireplace.** A new job building (build menu, default key **K**). It's a 1×1 stone fireplace costing 6 cobblestone. Placing it reserves the **3×3 plot** around it that the kitchen will need later (§8). Like the bench, it has a queue, worked by residents with Cook switched on:

| Recipe | Inputs | Output |
|---|---|---|
| Bread | 3 wheat | 1 bread |
| Cooked mutton | 1 raw mutton, 1 log (fuel) | 1 cooked mutton |

The fireplace gets the same queue rules as the bench (skipping blocked recipes, Queue 5). It also gets a standing order: **"Keep 6 meals in stock"**, on by default. When stored bread and cooked mutton total fewer than 6, cooks queue whichever recipe their inputs allow.

## 5. Jobs, priorities and skills

**Job types:** Mine, Haul, Build, Craft (the bench's planks and sticks), Toolsmith (the bench's tools), Farm, Cook, Hunt.

Each resident has, for **every** job:
- **On or off.** Everything starts on.
- **Priority** 1 to 3, where 1 is first. Everything starts at 2.
- **Level** 1 to 5, rising with experience.

**Claiming** (replacing Slice 1's single fixed order):
1. Direct and queued orders first, regardless of toggles.
2. Then eating, when hungry (§4).
3. Then jobs that are switched on, priority 1 first, then 2, then 3. Within a priority, Slice 1's order still applies: bench and fireplace work, then building, then gathering, then hauling.

**Skills.**
- **Experience:** each finished task in a job gives 1 point in that job. Levels 2, 3, 4 and 5 need 8, 25, 50 and 90 points.
- **No fading:** skills don't drop when unused.
- **Speed:** each level above 1 makes that job's work 15% faster.
- **Better results:**

| Job | Better result |
|---|---|
| Mine | +1 log or cobblestone per tree or boulder at levels 3 and 5 |
| Farm | +1 wheat per harvest at levels 3 and 5 |
| Cook | Bread takes 2 wheat instead of 3 at level 4 and up |
| Toolsmith | Tools get +20% uses per level above 1 |
| Haul | +1 carry capacity at levels 3 and 5 |
| Craft | Planks recipe gives 5 instead of 4 at level 4 and up |
| Build, Hunt | Speed only |

**New arrivals** start at level 1 everywhere except one job, picked by the sim's seeded random number generator, which starts at level 3. A traveler's toast says it ("Tomas is a skilled farmer").

**Character panel.** The resident panel gains a **Jobs** grid. Each row shows a job's on/off switch, priority (1, 2 or 3; click to cycle) and level with a progress bar to the next level.

## 6. Toolsmith

A resident with **Toolsmith** switched on keeps the village in spare tools:
- For each tool kind someone is using (axe, pickaxe), the toolsmith keeps **1 spare** in stock, of the best tier the bench can make with materials on hand. Spare tools come from the toolsmith's own bench queue entries, marked "(toolsmith)".
- A resident whose tool breaks **fetches a spare** instead of stopping. Their "Axe broke" report clears as soon as they pick it up.
- **Nothing to make a spare from:** the stuck list says why ("Toolsmith needs 2 more sticks for a spare axe").
- **No toolsmith at all:** Slice 1's rule holds, and residents stop and report.
- No repairs yet. Worn tools keep their uses (Slice 1, §7).

## 7. Recruitment

- **A traveler arrives when a finished house has a free bed**, after a short delay (45 seconds). One arrives per free bed, one at a time.
- They walk in from the map edge and claim the house. The first traveler is always Tomas; later names come from a list.
- **A finished house without a bed** shows "House needs a bed: 3 more wool" in the stuck list once wool runs short, since that's what's stopping arrivals.
- Food doesn't gate arrivals, but newcomers do need feeding, so food production has to grow with the village.

## 8. Buildings and orders added

**Job buildings start simple and evolve in place.** Each job building starts as its simplest form and reserves the plot its next form needs.
- **Reserved plot:** shown as a faint dashed outline. It stays clear: nothing can be built or stockpiled on it. Trees and boulders already there are left alone until the upgrade needs the space.
- **The upgrade itself** is later work (§14). It keeps the building's queue and adds capacity or recipes.

| Starts as | Grows into (later) | Reserved plot |
|---|---|---|
| Fireplace (1×1) | Kitchen | 3×3, fireplace at its back wall |
| Crafting bench (1×1) | Workshop | 3×3, bench at its back wall, for benches placed from Slice 2 on |

A bench placed in Slice 1 (in older saves) has no reserved plot. It can be upgraded later only if the 3×3 around it happens to be clear.

| Thing | How | Cost |
|---|---|---|
| Bed | House stage 4 | 3 wool, 3 planks |
| Fireplace | Build menu, K | 6 cobblestone (reserves a 3×3 kitchen plot) |
| Farm plot | Farm order, P (drag) | free |
| Hunt mark | Hunt order, G (click or drag) | — |
| Meadow trip | Resident panel: Send to the meadow | — |

## 9. Stuck reasons added

- "Starving: no food stored", and "Hungry" on the resident.
- "House needs a bed: N more wool".
- "Fireplace: Bread needs N more wheat", using the bench's wording rules.
- When placing a job building, "Not enough room to grow into a kitchen" (or a workshop) if its reserved plot would overlap a building or the map edge.
- "Toolsmith needs N more X for a spare Y".
- "No one does Farm" (or Hunt, Cook, and so on), when there's work of that type and every resident has it switched off.
- "Meadow has no sheep left", when a trip is planned.

## 10. Saving

Save format v4 adds the map size, sheep, farm plots and wheat growth, the fireplace, its queue, standing order and reserved plot, reserved plots for new benches, residents' hunger, job toggles, priorities and skills, the meadow's remaining sheep, and residents away on trips.

The v3→v4 upgrade step:
- Records the map size as 18×18, so older saves keep their size.
- Gives existing residents full hunger, all jobs on at priority 2, and level 1 everywhere.
- Adds a finished bed to every finished house (so old saves keep their residents housed).
- Adds no sheep to the clearing (old saves are past the opening).
- Gives the meadow its starting 8 sheep.

## 11. Controls added

| Key | Action |
|---|---|
| G | Hunt order |
| P | Farm order |
| K | Place a fireplace |

All are rebindable (Slice 1, §10).

## 12. Tuning table (provisional)

| Key | Value |
|---|---|
| `map_size` | 32 × 32 (was 18 × 18) |
| `start_trees` / `start_boulders` | about 40 / about 16, laid out by hand |
| `start_sheep` | 6 |
| `sheep_walk` | 0.6 cells/s, pausing often |
| `hunt_time` | 4 s |
| `meadow_sheep` | 8 |
| `meadow_trip` | 90 s away |
| `meadow_take` | 2 sheep per resident |
| `hunger_drop` | 100 → 0 in 360 s |
| `eat_below` / `hungry_below` | 40 / 25 |
| `hungry_slow` | 25% slower |
| `food_value` | bread 50, cooked mutton 60, raw mutton 20 |
| `plant_time` / `harvest_time` | 2 s / 2 s |
| `wheat_grow` | 120 s |
| `wheat_yield` | 2 |
| `bake_time` / `cook_time` | 3 s / 3 s |
| `meal_stock` | 6 |
| `skill_levels` | 8, 25, 50, 90 points |
| `skill_speed` | +15% per level above 1 |
| `arrival_delay` | 45 s per free bed |

## 13. Open questions (not blocking the start)

- **Regrowth (#22):** do trees regrow from saplings, and do sheep return to the clearing or the meadow over time? Without regrowth, a long game runs out of trees, and wool caps the number of beds at 6 + 8 = 14 sheep, so about 4 extra beds. Proposed default for Slice 2: the meadow regains 1 sheep every 4 minutes up to 8, and trees don't regrow yet.
- **Building customization (#21):** still fixed templates in Slice 2.

## 14. Deferred

Rest and sleep, happiness, shears and breeding, the inn, travelers' requests, food variety effects, spoiling, and tables for eating.

**Building upgrades** (designed in §8, built later):
- **Fireplace → kitchen:** a bigger queue, two cooks at once, and new recipes.
- **Bench → workshop:** two crafters at once, and later tool repair.
- **Farm plot → barn-backed farm:** seed storage, and later fences.
