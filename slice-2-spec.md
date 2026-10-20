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
- **House stages** become Foundation → Walls → Roof → **Bed**. The bed stage costs 3 wool and 3 planks.
  - The bed sits in the house's **top corner**: the back corner, furthest from the camera.
  - It's two cells long, with a plank frame, a white pillow and a red blanket.
  - The roof is cut away while the bed is being built, and whenever the house is selected or hovered, so the bed can be seen.
- **The clearing starts with 6 sheep**, enough wool for the two opening beds.
- **Arrivals need a free bed** (§7). Tomas comes once the second house, bed included, is finished.
- **Ada's house** is hers when its bed is finished, not when its roof is.
- **Slice 1 goals** gain "Hunt sheep for wool" before Ada's house. The founding checklist otherwise stays.
- **Tool breakage:** while anyone has the Toolsmith job switched on, a resident whose tool breaks fetches a spare instead of stopping (§6). With no toolsmith, the Slice 1 rule holds: they stop and report.

## 3. Sheep, hunting and the meadow

**Sheep** are animals that wander slowly within the clearing, avoiding trees, boulders and buildings. Six start in the clearing. None arrive in the clearing on their own; the meadow regains its sheep (below).

**Hunt order** (default key **G**): click or drag over sheep to mark them, as with Mine. A resident with Hunt switched on walks to the sheep, following it if it moves, and hunts it. A hunt drops **1 wool and 1 raw mutton** where the sheep stood. No tool is needed. Higher Hunt levels hunt faster.

**The sheep meadow** is a place off the map, reached from a signpost at the map's left edge.
- Select one or two residents and choose **Send to the meadow** in the resident panel.
- They walk off the map and are **away** for the trip time. While away, they don't work in the village; the panel shows when they'll be back.
- They return carrying what they found: **2 sheep's worth per resident** (2 wool and 2 raw mutton each), limited by what the meadow has.
- The meadow holds **8 sheep** to start. When it's empty, the trip returns with nothing and the meadow shows as "No sheep left".
- **The meadow regains sheep** (decided with the owner, #22): 1 every 4 minutes, up to 8.
- **How it plays** (#50):
  - **The signpost** sits at the left edge's middle cell. Clicking it shows the meadow's sheep and when the next one returns. Nothing can be built, stockpiled or farmed on it.
  - **Sending:** **Send to the meadow** appears in the resident panel, or as "Send both" when two are selected. It's an order: the resident walks to the signpost, then is away for 90 s.
  - **While away,** residents aren't drawn and can't be clicked or given orders. Right-clicking with one selected says they're away. Their panel shows "At the meadow, back in N s".
  - **Coming back,** they reappear at the signpost and drop their wool and mutton there for hauling. The meadow's sheep are taken on return, not on departure, and a toast says what they brought. "Meadow has no sheep left" shows while someone heads to an empty meadow.
- This is a deliberately small taste of Slice 3's expeditions: someone leaves, the village works without them, and they come back carrying something.

## 4. Food and hunger

**Food items:** berries, wheat, bread, raw mutton, cooked mutton. Residents eat berries, bread and cooked mutton. Raw mutton can be eaten in a pinch for less.

**Berry bushes** are the early food, before farms and the fireplace (decided with the owner).
- **Where:** 6 bushes grow around the opening.
- **Berries:** each holds up to 3, and one grows back every 45 seconds.
- **Eating:** a hungry resident walks to the nearest food. At a bush, they eat berries one at a time, 15 each, until nearly full (90) or the bush is bare.
- **Walking:** bushes don't block it.
- **Buildings:** a building placed over a bush clears it.
- **Older saves:** they get the same bushes, minus any that would sit on something.

**Hunger** runs from 100 (full) to 0 and drops steadily, emptying in about 6 minutes of game time.
- **Eating:** below 40, a resident's next job, after any orders you've given them, is to fetch the nearest food and eat it. Food is eaten where it's picked up; no tables yet.
  - Berries restore 15, raw mutton 20, bread 50, and cooked mutton 60.
- **Hungry** (below 25): works 25% slower. The resident panel shows "Hungry".
- **Starving** (0): stops working, and the stuck list shows "Starving: no food stored". There's no death in Slice 2, since death is an open decision (#20). They recover as soon as food exists.
- **Away residents** (on a meadow trip) don't get hungry while away.

**Farms.** **Farm** order (default key **P**, plant): paint a farm plot over open grass, as with a stockpile.
- A resident with Farm switched on **plants** each empty cell (2 seconds, no seeds needed).
- Wheat **grows** for 2 minutes, drawn as rising stages.
- When ripe, a farmer **harvests** it (2 seconds) for 2 wheat, and the cell goes back to empty.
- Ripe wheat that isn't harvested waits; it doesn't spoil.
- Harvested wheat drops on the cell and is hauled to a stockpile like anything else. The stock bar counts it.
- **A plot is replanted only once its harvest has been collected** (decided with the owner). With no stockpile to take it to, the wheat waits on the plot and the stuck list says "Harvested wheat needs a stockpile before replanting".
- **Where plots go:** only open grass. Trees, boulders, berry bushes, buildings and stockpile cells are skipped when painting. A stockpile can't be painted over a farm either. Placing a building over plots clears them, as it does stockpile cells. Plots can't go on a reserved plot (§8).
- **Selecting a plot** shows its state (empty, growing with a percentage, ripe) and who is working it, with **Remove this plot**.
- Farming is the **Farm** job (§5). Within a priority, farm work comes after building and delivering to sites, and before mining. Ripe cells are harvested before empty ones are planted.

**Fireplace.** A new job building (build menu, default key **K**). It's a 1×1 stone fireplace costing 6 cobblestone. Placing it reserves the **3×3 plot** around it that the kitchen will need later (§8). Like the bench, it has a queue, worked by residents with Cook switched on:

| Recipe | Inputs | Output |
|---|---|---|
| Bread | 3 wheat | 1 bread |
| Cooked mutton | 1 raw mutton, 1 log (fuel) | 1 cooked mutton |

The fireplace gets the same queue rules as the bench (skipping blocked recipes, Queue 5). It also gets a standing order: **"Keep 6 meals in stock"**, on by default. When stored bread and cooked mutton total fewer than 6, cooks queue whichever recipe their inputs allow.
- The standing order queues **one meal at a time**, bread first, and only when its inputs exist somewhere. So it never leaves the fireplace stuck. A recipe you queue yourself can be blocked, and then the stuck list says so ("Fireplace: Bread needs 3 more wheat").
- Turning the standing order off removes the meals it queued. The switch sits in the fireplace's panel.
- Selecting a finished fireplace opens its panel on the right, as the bench does. The toolbar's **Craft** button and its **Next** button step through every finished bench and fireplace.
- Hungry residents leave raw mutton for the fireplace. They eat it only when there's no other food.
- Fireplace work is the **Cook** job (§5) and ranks with bench work.

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

**How skills apply** (#48):
- **Experience:** a point is earned when a whole task finishes: a tree felled, a stage built, a recipe made, a plot planted or harvested, a sheep hunted, a load hauled or delivered. That's true whether the work was claimed or ordered directly. Carrying to a site counts as Build. Carrying ingredients to a station counts as the recipe's job.
- **New levels:** reaching one gets a toast, for example "Ada is now level 2 at Mine".
- **Speed:** the 15% per level applies to the work itself (chopping, building, crafting, planting), not to walking.
- **Bread at level 4:** a level-4 cook still waits for the recipe's 3 wheat at the fireplace but uses only 2. The spare wheat counts toward the next bread, and when the queue empties it's put back out.
- **Tools:** a toolsmith's extra uses are rounded. A level-2 wooden pickaxe has 12 uses.
- **Carry capacity:** the Haul bonus applies to all carrying, hauling and deliveries alike.
- **Direct orders:** switching a job off doesn't cancel a direct or queued order of that kind.

**New arrivals** start at level 1 everywhere except one job, picked by the sim's seeded random number generator, which starts at level 3. A traveler's toast says it ("Tomas is a skilled farmer").

**How work maps to jobs** (#47):
- **Mine:** marked trees and boulders. **Hunt:** marked sheep. **Farm:** planting and harvesting.
- **Build:** building, and carrying materials to construction sites.
- **Craft / Toolsmith / Cook:** making and carrying ingredients for station recipes. Planks and sticks are Craft, tools are Toolsmith, fireplace recipes are Cook. With Toolsmith off, a resident still makes the planks and sticks queued ahead of a pickaxe and leaves the pickaxe itself.
- **Haul:** carrying loose items to stockpiles.
- Within one priority, the order is: station work (Craft, Toolsmith, Cook), then Build, then Farm, then Mine and Hunt (nearest first), then Haul.
- Switching off the job a resident is doing stops it. Changing a priority doesn't interrupt current work.
- With every job off, a resident still eats and follows direct and queued orders.
- "No one does X" appears in the stuck list when there's work of that job and every resident has it off.

**Character panel.** The resident panel gains a **Jobs** grid. Each row shows a job's on/off switch, priority (1, 2 or 3; click to cycle) and level with a progress bar to the next level.

## 6. Toolsmith

A resident with **Toolsmith** switched on keeps the village in spare tools:
- For each tool kind someone is using (axe, pickaxe), the toolsmith keeps **1 spare** in stock, of the best tier the bench can make with materials on hand. Spare tools come from the toolsmith's own bench queue entries, marked "(toolsmith)".
- A resident whose tool breaks **fetches a spare** instead of stopping. Their "Axe broke" report clears as soon as they pick it up.
- **Nothing to make a spare from:** the stuck list says why ("Toolsmith needs 2 more sticks for a spare axe").
- **No toolsmith at all:** Slice 1's rule holds, and residents stop and report.
- **In use** means someone holds a tool of that kind or has had one break. **A spare** is any axe or pickaxe lying about or stockpiled.
- **Which tier:** stone when there's enough cobblestone on hand for it, otherwise wood. Its planks and sticks are queued ahead of it like any other recipe, once that's unlocked.
- **One entry at a time:** each kind gets one toolsmith entry, at the first finished bench. If you remove the entry, the toolsmith queues it again. To stop it, switch Toolsmith off.
- **While a spare is coming:** a resident whose tool broke shows "Axe broke. Waiting for the toolsmith’s spare" until it's made.

**Equipping a chosen tool** (owner's request, made alongside #49):
- **The Equip button:** the resident panel's Axe and Pickaxe rows show **Equip** whenever an axe or pickaxe is lying about or stockpiled. It lists each one with its uses left and where it is, best first.
- **Choosing one** is a direct order: the resident walks over and picks it up, leaving the tool they had where the new one lay.
- **Keeping it:** a chosen tool is **kept until it breaks**. The resident doesn't swap it for a better one lying around. "Kept until it breaks" shows under the row, with **Use the best** to let them swap again.
- No repairs yet. Worn tools keep their uses (Slice 1, §7).

## 7. Recruitment

- **A traveler arrives when a finished house has a free bed**, after a short delay (45 seconds). One arrives per free bed, one at a time.
- They walk in from the map edge and claim the house. The first traveler is always Tomas; then Mira, Jonas, Elsa, Bram, Ines, Otto and Lena.
- **A finished house without a bed** shows "House needs a bed: 3 more wool" in the stuck list once wool runs short, since that's what's stopping arrivals.
- Food doesn't gate arrivals, but newcomers do need feeding, so food production has to grow with the village.

## 7a. Craft menu in the toolbar (#57)

Once a crafting bench is finished, a **Craft** button appears in the orders toolbar (default key C, rebindable).
- It opens the bench panel above the toolbar, so crafting doesn't need the bench in view.
- **The recipes and queue appear only there, on the right.** Selecting the bench in the world, or its entry in the stuck list, opens the Craft panel at that bench. The selection panel on the left shows just a summary: the bench's status, any stuck reason, and an "Open the craft menu" button when the panel is closed.
- With more than one bench, the panel says "Bench 1 of 2" and has **Next bench**.
- Esc closes it.
- **Steady layout:** the bench panel lists its recipes first, at a fixed size, and keeps the status, stuck reasons and queue in a fixed-height area below. The Queue buttons never move under the cursor.

## 8. Buildings and orders added

**Job buildings start simple and evolve in place.** Each job building starts as its simplest form and reserves the plot its next form needs.
- **Reserved plot:** shown as a faint dashed outline, and while placing, next to the blueprint. It stays clear: nothing can be built, stockpiled or farmed on it, though residents walk across it. Placing the building clears stockpile cells and farm plots from it. Trees and boulders already there are left alone until the upgrade needs the space.
- **Turning:** R turns which side the plot opens toward. The building sits in the middle of the plot's back wall, and the fireplace's mouth faces the plot.
- **Room to grow:** a job building's own plot must stay on the map and clear of other buildings and plots, or placement says "Not enough room to grow into a kitchen" (or a workshop).
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

Slice 2 changes the save format one step per change, each with its own upgrade step and fixture, rather than in one jump. **v4 (#52) adds the map size.** Later steps add sheep, farm plots and wheat growth, the fireplace, its queue, standing order and reserved plot, reserved plots for new benches, residents' hunger, job toggles, priorities and skills, the meadow's remaining sheep, and residents away on trips.

Taken together, the upgrade steps:
- Record the map size as 18×18 for saves from before v4, so older saves keep their size (v3→v4).
- Gives existing residents full hunger, all jobs on at priority 2, and level 1 everywhere.
- Adds a finished bed to every finished house (so old saves keep their residents housed).
- Adds no farm plots (v7→v8, #45).
- Gives existing residents every job on at priority 2 (v9→v10, #47).
- Gives existing residents level 1 in every job (v10→v11, #48).
- Marks no tools as chosen (v11→v12, equipping).
- Gives older saves a full meadow with nobody away (v12→v13, #50).
- Gives existing buildings no reserved plot, so Slice 1 benches reserve nothing (v8→v9, #46).
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
| `meadow_regrow` | 1 sheep per 240 s, up to 8 |
| `hunger_drop` | 100 → 0 in 360 s |
| `eat_below` / `hungry_below` | 40 / 25 |
| `hungry_slow` | 25% slower |
| `food_value` | berries 15, raw mutton 20, bread 50, cooked mutton 60 |
| `bush_max` / `bush_regrow` | 3 berries / 45 s each |
| `eat_until` (at a bush) / `eat_time` | 90 / 1.5 s per item |
| `plant_time` / `harvest_time` | 2 s / 2 s |
| `wheat_grow` | 120 s |
| `wheat_yield` | 2 |
| `bake_time` / `cook_time` | 3 s / 3 s |
| `meal_stock` | 6 |
| `skill_levels` | 8, 25, 50, 90 points |
| `skill_speed` | +15% per level above 1 |
| `arrival_delay` | 45 s per free bed |

## 13. Open questions (not blocking the start)

- **Regrowth (#22):** do trees regrow from saplings? Without regrowth, a long game runs out of trees. (Decided: the meadow regains 1 sheep every 4 minutes up to 8. Trees don't regrow yet.)
- **Building customization (#21):** still fixed templates in Slice 2.

## 14. Deferred

Rest and sleep, happiness, shears and breeding, the inn, travelers' requests, food variety effects, spoiling, and tables for eating.

**Building upgrades** (designed in §8, built later):
- **Fireplace → kitchen:** a bigger queue, two cooks at once, and new recipes.
- **Bench → workshop:** two crafters at once, and later tool repair.
- **Farm plot → barn-backed farm:** seed storage, and later fences.
