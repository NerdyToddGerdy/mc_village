# Slice 2 Spec — A Functioning Village

Companion to `block-village-design-brief.md` and `slice-1-spec.md`. Slice 2 builds on everything in Slice 1; this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table (§12).

Tracking issue: #11. Decisions settled with the owner while writing this spec:

| Question | Decision |
|---|---|
| Needs (#18) | **Food only.** No rest or happiness yet. |
| First food | **Wheat → bread**, plus **meat from sheep**. |
| Jobs | Every resident has a **level in every job**, rising with practice, and **one job**, picked from a dropdown (#134, replacing the first decision's on/off toggles and priorities). **Ada does everything.** You can still give direct orders. |
| Skill effect | Higher levels work **faster and give better results**. |
| Recruitment (#24) | **No free bed, no arrival**, as in Minecraft. |
| Beds | A **bed is part of every house** (its last construction stage) and needs wool. |
| Job buildings | **Start simple and evolve in place.** Cooking starts at a **fireplace**, placed with room reserved for it to become a kitchen later. Every job building reserves the space its upgrade needs. |
| Sheep | **A few roam the clearing** at the start, enough for Ada's and Tomas's beds. When they're gone, **a trip to a meadow** off the map finds more. |
| Wool and meat | **Hunting** a sheep drops 1 wool and 1 raw mutton. No shearing or breeding yet. |

## 1. Scope and done criteria

Slice 2 is done when, from a fresh start, a player can:

**Done (#11).** Every item below is played through by `tests/playtest_village.gd` with real input: keys, clicks and drags. The founding is set up by command there, since `tests/playtest.gd` already plays it through input.

- [x] Hunt the clearing's sheep for wool and mutton.
- [x] Finish both opening houses including their beds, then welcome Tomas (who now needs a free bed).
- [x] Paint a farm, watch wheat be planted, grow and get harvested.
- [x] Build a fireplace, with its kitchen space reserved, and see residents bake bread and cook mutton.
- [x] See residents get hungry, fetch food and eat, and see a clear reason when there's no food.
- [x] Give each resident a job, and watch skill levels rise with work. (First built as on/off toggles and priorities; one job each since #134.)
- [x] Have a toolsmith keep spare tools stocked, so broken tools get replaced without the player.
- [x] Send a resident to the sheep meadow and have them come back with wool and mutton.
- [x] Build a third house with its bed and have a new traveler arrive.
- [x] Understand every stall from its on-screen reason alone.

## 2. Changes to Slice 1 rules

- **A bigger clearing:** the map grows from 18×18 to **32×32** (provisional), with proportionally more trees (about 40) and boulders (about 16).
  - There's room for a third house, farm plots, the fireplace and the reserved plots that let buildings grow.
  - Ada starts near the middle, and the camera opens on her.
  - Saves record the map size, so older 18×18 saves keep their size.
- **House stages** become Foundation → Walls → Roof → **Bed**. The bed stage costs 3 wool and 3 planks.
  - The bed sits in the house's **top corner**: the back corner, furthest from the camera.
  - It's two cells long, with a plank frame, a white pillow and a red blanket.
  - The roof is cut away while the bed is being built, and whenever the house is selected or hovered, so the bed can be seen.
- **The clearing starts with 3 sheep**, enough wool for Ada's bed. The second bed's wool comes from the meadow (#182, below). Saved games keep their sheep.
- **Arrivals need a free bed** (§7). Tomas comes once the second house, bed included, is finished.
- **Ada's house** is hers when its bed is finished, not when its roof is.
- **The founding (reworked in #182)** teaches the stockpile first, both tools together, a first trip to the meadow, and the chopping block:

  | # | Goal | Done when |
  |---|---|---|
  | 1 | Chop a tree | a tree is felled |
  | 2 | Paint a stockpile | a stockpile is painted |
  | 3 | Build a crafting bench | a bench is finished |
  | 4 | Craft an axe and a pickaxe | both have been crafted |
  | 5 | Break a boulder | a boulder is broken |
  | 6 | Hunt sheep for wool | a sheep is hunted (or Ada's house is finished, in saves from before sheep) |
  | 7 | Build Ada's house | a house is finished |
  | 8 | Build a fireplace | a fireplace is finished. It cooks the clearing's mutton, the trip's meals |
  | 9 | Build an expedition board | a board is finished |
  | 10 | Fetch wool from the meadow | a meadow trip comes home with wool |
  | 11 | Build a second house | two houses are finished |
  | 12 | Welcome a traveler | the traveler has moved in |
  | 13 | Build Tomas a chopping block | a chopping block is finished |

  - **Automatic ingredients from the start:** the bench queues a recipe's planks and sticks in a new game, marked **A**. The first house no longer unlocks it.
  - **The board** shows in the Build menu once Ada's house is finished, rather than after the founding.
  - **The first traveler is a lumberjack**, so the last goal gives him his workstation. Later arrivals are skilled in a random job, as before. The toast reads "Tomas, a skilled lumberjack, has arrived."
  - The goals read the village's stats, including which buildings have ever been finished. The fireplace goal was added beside the issue's twelve, since a meadow trip packs a meal for the walk home.
  - **Older saves** (v26→v27): automatic ingredients turn on. A save past the old pickaxe goal counts the new tools goal as done, and one with two houses counts the fireplace, board and meadow steps as done. A founding that was complete stays complete.
  - "Make Ada the toolsmith" (added by #91) went with #134, and "Two residents at work" with #182. The hints name the Gather and Paint menus (#93, #94).
- **After the founding (#81):** the goals panel folds to a small "Founding ✓" chip, since it has nothing left to guide. Whether Slice 2 gets a checklist of its own is still open. Saves made after the founding are labelled with facts about the village, "4 residents, 3 houses, 18 meals", rather than "Founding complete", so they can be told apart. The menu's subtitle reads "Your village: …" the same way. Older saves labelled "Founding complete" are listed by the same facts, read from the save.
- **Tool breakage:** while a resident's job is Toolsmith, a resident whose tool breaks fetches a spare instead of stopping (§6). With no toolsmith, the Slice 1 rule holds: they stop and report, and the report says how to fix it: "Axe broke. Craft one at the bench, or make someone the toolsmith" (#91, #134).

## 3. Sheep, hunting and the meadow

**Sheep** are animals that wander slowly within the clearing, avoiding trees, boulders and buildings. Six start in the clearing. None arrive in the clearing on their own; the meadow regains its sheep (below).

**Hunt order** (default key **G**): click or drag over sheep to mark them, as with Mine. A resident with Hunt switched on walks to the sheep, following it if it moves, and hunts it. A hunt drops **1 wool and 1 raw mutton** where the sheep stood. No tool is needed. Higher Hunt levels hunt faster.

**The sheep meadow** is a place off the map, reached from a signpost at the map's left edge. *Replaced in Slice 3.5 (#137): the meadow is now an expedition site with its own map, planned at the expedition board, and Send to the meadow is gone. See `slice-3.5-spec.md` §3. The rules below are how Slice 2 played.*
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

The fireplace gets the same queue rules as the bench (skipping blocked recipes, queuing several at once). It also gets a standing order: **"Keep 6 meals in stock"**, on by default. When stored bread and cooked mutton total fewer than 6, cooks queue whichever recipe their inputs allow.
- The standing order queues **one meal at a time**, bread first, and only when its inputs exist somewhere. So it never leaves the fireplace stuck. A recipe you queue yourself can be blocked, and then the stuck list says so ("Fireplace: Bread needs 3 more wheat").
- Turning the standing order off removes the meals it queued. The switch sits in the fireplace's panel.
- Selecting a finished fireplace opens its panel on the right, as the bench does. The toolbar's **Craft** button opens the panel, with a tab for every finished bench and fireplace (#76).
- Hungry residents leave raw mutton for the fireplace. They eat it only when there's no other food.
- Fireplace work is the **Cook** job (§5) and ranks with bench work.

## 5. Jobs and skills

**Job types:** Lumberjack, Stonemason, Haul, Build, Craft (the bench's planks and sticks), Toolsmith (the bench's tools), Farm, Cook, Hunt. Lumberjack and Stonemason replaced Mine (#177): Lumberjack works trees and Stonemason works boulders and ore.

**One job each (#134).** This replaces the first decision, an on/off switch and a priority for every job (#47, #78).
- **Every resident but Ada has one job**, or **No job**. They claim work of that job only.
- **Idle hauling:** when there's no work of their job, or they have none, a resident hauls loose items to stockpiles. With nothing to haul either, they wait.
- **Ada does everything.** She claims every kind of work, in Slice 1's fixed order (station work, then building, farming, gathering, then hauling). Her job reads **Everything**, with no dropdown. She's the generalist who covers whatever nobody has been given, tools queued by hand included.
- **Each resident has a level** 1 to 5 in every job, rising with experience, whatever their job.
- **New arrivals** start with the job they're skilled in ("Tomas is a skilled farmer" arrives as a Farmer).
- **Older saves** (v23, #177): a resident whose job was Mine becomes a Lumberjack, since nobody's trees and boulders were counted apart, so the tie rule applies. Mine's experience is copied to both Lumberjack and Stonemason.
- **Older saves** (v22): each resident other than Ada gets their switched-on job with the best priority, ties broken by level and then the job list's order, or Haul if all were off. The switches and priorities go.

**Jobs need their workstation (#184).** A resident works their job only once they've claimed a finished workstation of it, like Minecraft's job-site blocks. One resident claims each workstation, so two farmers need two composters.

| Job | Workstation | Cost (provisional) | Reserves room for |
|---|---|---|---|
| Lumberjack | Chopping block | 4 planks | Sawmill |
| Stonemason | Mason's bench | 2 planks, 4 cobblestone | Mason's workshop |
| Build | Builder's table | 4 planks, 2 logs | Builder's yard |
| Craft | Crafting bench | 4 logs | Workshop |
| Toolsmith | Toolsmith's bench | 4 planks, 3 cobblestone | Anvil (once there's iron) |
| Farm | Composter | 4 planks | Granary |
| Cook | Fireplace | 6 cobblestone | Kitchen |
| Hunt | Hunter's lodge | 6 logs, 2 planks | Tannery |
| Haul | none: always available | | |

- **A workstation isn't a home.** A house's bed is still what brings a traveler and where a resident heals. Building a workstation adds no bed, and a house unlocks no job.
- **Claiming:** a resident whose job needs a workstation, and who has none, claims the nearest free finished one. Its panel names them ("Tomas's composter"). A new job frees the old workstation. A workstation that's removed frees its resident, who claims another free one if there is one.
- **No workstation:** the job can still be given. Until one is free the resident hauls, their job reads "Farmer (no composter)", and the stuck list says "Tomas: Build a composter to start work".
- **Arrivals** come with their skilled job, and haul until its workstation is built.
- **Ada claims none.** She does everything, at any building.
- **Where the work happens:** crafters and cooks work at their own claimed station first, then any free one. Lumberjacks and stonemasons work their own workstation's area only. Farmers tend any plot.
- **Toolsmith:** tools are still made at a crafting bench. The toolsmith's bench is where the toolsmith works from, and spare tools (§6) need a resident toolsmith who has claimed one.
- **The jobs board and dropdown** show the free workstations: "Farm · level 3 · 1 composter free", or "· no composter". Each column counts the workstations built under the number of residents with the job.
- **Older saves** (v24): finished benches, fireplaces, chopping blocks and mason's benches go to residents whose jobs match, first come first served. Everyone else hauls, with the reason shown, until one is built.

**Claiming:**
1. Direct and queued orders first, whatever the job.
2. Then eating, when hungry (§4).
3. Then work of their job, once they have its workstation: for Ada, every job in Slice 1's order.
4. Then hauling.

**Village jobs board (#78, #134).** Everyone's jobs are on one board, opened with **J** (rebindable) or the **Jobs** button in the tally bar, and closed with J, the button or Esc.
- **Rows** are residents, each with their tunic swatch and name; clicking a name selects them. Next to the name is their **job dropdown** ("Farmer, level 3 ▾"); Ada's reads "Everything".
- **Columns** are the eight jobs. A column's header counts the residents with that job, Ada aside, and reads "nobody" in yellow at 0 (Haul aside, since everyone hauls).
- **A cell** shows the resident's level in that job and a tick of progress to the next level. Their own job's cell is lit.
- **The dropdown** lists each job with the resident's level in it, best first, and how many residents already have it ("Farm · level 3 · 2 farmers"), then **No job: haul**. Choosing one gives them that job and closes it; a click elsewhere or Esc closes it too.
- **The resident panel** has a **Job** line with the same dropdown ("Farmer, level 3 ▾"), and a **Jobs board** button.
- The board sits where the goals panel is, and the goals panel hides while it's open.

**Skills.**
- **Experience:** each finished task in a job gives 1 point in that job. Levels 2, 3, 4 and 5 need 8, 25, 50 and 90 points.
- **No fading:** skills don't drop when unused.
- **Speed:** each level above 1 makes that job's work 15% faster.
- **Better results:**

| Job | Better result |
|---|---|
| Lumberjack | +1 log per tree at levels 3 and 5 |
| Stonemason | +1 cobblestone or ore per boulder or ore block at levels 3 and 5 |
| Farm | +1 wheat per harvest at levels 3 and 5 |
| Cook | Bread takes 2 wheat instead of 3 at level 4 and up |
| Toolsmith | Tools get +20% uses per level above 1 |
| Haul | +1 carry capacity at levels 3 and 5 |
| Craft | Planks recipe gives 5 instead of 4 at level 4 and up |
| Build, Hunt | Speed only |

**How skills apply** (#48):
- **Experience:** a point is earned when a whole task finishes: a tree felled, a stage built, a recipe made, a plot planted or harvested, a sheep hunted, a load hauled or delivered. That's true whether the work was claimed or ordered directly. Carrying to a site counts as Build. Carrying ingredients to a station counts as the recipe's job.
- **New levels:** reaching one gets a toast, for example "Ada is now level 2 at Lumberjack".
- **Speed:** the 15% per level applies to the work itself (chopping, building, crafting, planting), not to walking.
- **Bread at level 4:** a level-4 cook still waits for the recipe's 3 wheat at the fireplace but uses only 2. The spare wheat counts toward the next bread, and when the queue empties it's put back out.
- **Tools:** a toolsmith's extra uses are rounded. A level-2 wooden pickaxe has 12 uses.
- **Carry capacity:** the Haul bonus applies to all carrying, hauling and deliveries alike.
- **Direct orders:** changing a job doesn't cancel a direct or queued order.

**New arrivals** start at level 1 everywhere except one job, picked by the sim's seeded random number generator, which starts at level 3. A traveler's toast says it ("Tomas is a skilled farmer").

**How work maps to jobs** (#47):
- **Lumberjack:** marked trees, then their own work at a chopping block (below). **Stonemason:** marked boulders, then their own work at a mason's bench, and mining at the old mine and surveying the vein. **Hunt:** marked sheep. **Farm:** planting and harvesting.
- **Build:** building, and carrying materials to construction sites.
- **Craft / Toolsmith / Cook:** making and carrying ingredients for station recipes. Planks and sticks are Craft, tools are Toolsmith, fireplace recipes are Cook. A Crafter makes the planks and sticks queued ahead of a pickaxe and leaves the pickaxe itself.
- **Haul:** carrying loose items to stockpiles.
- Ada's order is: station work (Craft, Toolsmith, Cook), then Build, then Farm, then marked trees, boulders and animals (nearest first), then Haul. She never fells or breaks anything unmarked.
- A new job stops work of the old one.
- "No one is a farmer" (or lumberjack, cook, and so on) appears in the stuck list when there's work of that job, no resident has it, and Ada can't see to it: she's away, on another map, resting or packing for an expedition.
- A party member keeps their job while away (#106). It applies again once they're back.

**Workstations: the chopping block and the mason's bench (#177).** A lumberjack or stonemason with no marked work finds their own, but only around a workstation the player has built.
- **The buildings:** the chopping block (4 planks) and the mason's bench (2 planks, 4 cobblestone) are 1×1, from the Build menu. Each reserves a 3×3 plot for its upgrade, a sawmill or a mason's workshop (§8).
- **Work area:** everything within 8 cells of the workstation. It's drawn as a dashed chalk circle while the workstation is selected or being placed.
- **Their own work**, once nothing marked is left, in this order:
  1. carry logs or cobblestone lying in a work area to the workstation's pile;
  2. a lumberjack plants saplings (below);
  3. fell the nearest unmarked tree, or break the nearest unmarked boulder, in a work area.
- **Pile:** the two cells beside the workstation, inside its plot, hold up to 20 logs or cobblestone. Haulers carry logs and cobblestone to the nearest pile with room before the stockpile, and anything over goes to the stockpile. Builders, crafters and packing take from a pile like a stockpile.
- **Keep-stock target:** each workstation keeps 20 by default, set in steps of 5 in its panel. Gatherers stop their own work once the village has that many (piles, stockpiles and loose items together). Marked work goes on regardless.
- **Protected land:** a gatherer's own work never takes a tree or boulder that's marked **Keep**, or that stands in a building's footprint or reserved plot, on a stockpile, farm or pen, or beside a house's door. **Keep** is a Gather order (click or drag; clicking a kept one unmarks it) and a toggle in a tree's or boulder's panel. A kept tree shows a green ring. Kept trees are still felled when marked.
- **Ada** works marked trees and boulders but never makes her own work, so she never clears the land on her own.
- **Saplings (settles #22 for village trees):** a felled tree drops 1 sapling, with a 30% chance of a second. A lumberjack plants saplings on open grass in a chopping block's work area. The spot must be off protected land and off the map's edge, at least 3 cells from another tree and 2 from a boulder. A sapling grows into a full tree in 5 minutes: it shows as a sapling, then a young tree at half-time, then a full tree. Until then it can't be marked or chopped, though it blocks the way like a tree. A blueprint placed over a sapling lifts it back into a sapling item. Saplings are stockpiled and hauled like anything else.
- **The workstation's panel** shows its pile, its target, the resident who has claimed it (#184), and its stuck reasons.
- **Processing (#178):** each workstation is also a station with a queue, and gets a tab in the Craft panel.
  - The chopping block saws **5 planks from a log** ("Sawn planks"), against the bench's 4. A level-4 lumberjack saws 6. The bench's Planks recipe stays.
  - The mason's bench cuts **2 cobblestone into 2 stone bricks**. Stone bricks are a new building material. Nothing uses them yet; the mason's workshop, the kitchen and a sturdier house will.
  - Sawing is Lumberjack work and cutting is Stonemason work, so their levels speed it up. Ada does it too, like all station work.
  - **Standing order:** a chopping block keeps 20 planks and a mason's bench 10 stone bricks, set in steps of 5 in its panel and its Craft panel tab (0 is off). While the village has fewer, it queues one batch at a time, like the fireplace's meals, when the inputs are on hand. Batches queued by hand are made regardless.

**Jobs make their own work (#183).** A resident whose job has no marked work finds work of that job by themselves, but only within limits the player has set up. Marks come first, and anyone whose job fits can work them. Ada never makes her own work.

| Job | Works on its own | Area or limit |
|---|---|---|
| Lumberjack, Stonemason | fells trees, breaks boulders | their workstation's work area (above) |
| Hunter | hunts wild animals in the village | down to a **herd floor** per species |
| Farmer | plants and harvests | painted farm plots |
| Cook, Crafter, Toolsmith | standing orders | their workstation |
| Hauler | carries loose items | the stockpiles and piles |
| Builder | blueprints only | none of their own |

- **Herd floor:** hunters with a claimed hunter's lodge hunt unmarked wild animals in the village, nearest first, while more than the floor of that species are left. Each species starts at 2. The jobs board's "Hunters leave" row sets them, with − and + for each species in the village. Animals already marked or being hunted don't count toward the floor, so it holds with several hunters. Marked animals are hunted even below the floor. Penned animals are never hunted on a hunter's own (#139).
- **Stuck reasons:** "Hunter: herd at its floor (2 sheep)", or "Hunter: no animals to hunt" when the village has none. Both are waiting, not stuck. A lumberjack's or stonemason's limits show on their workstation (above).

**Character panel.** The resident panel first had a **Jobs** grid (#47). The Village jobs board (#78, above) replaced it; the panel has the job dropdown and a button to the board.

## 6. Toolsmith

A resident whose job is **Toolsmith** keeps the village in spare tools (#91, #134). **Ada doesn't count**: she makes tools queued by hand, but spares need a toolsmith of the village's own.
- For each tool kind someone is using (axe, pickaxe), the toolsmith keeps **1 spare** in stock, of the best tier the bench can make with materials on hand. Spare tools come from the toolsmith's own bench queue entries, marked "(toolsmith)".
- A resident whose tool breaks **fetches a spare** instead of stopping. Their "Axe broke" report clears as soon as they pick it up.
- **Nothing to make a spare from:** the stuck list says why ("Toolsmith needs 2 more sticks for a spare axe").
- **No toolsmith at all:** no spares are queued, Slice 1's rule holds, and residents stop and report ("Axe broke. Craft one at the bench, or make someone the toolsmith").
- **In use** means someone holds a tool of that kind or has had one break. **A spare** is any axe or pickaxe lying about or stockpiled.
- **Which tier:** stone when there's enough cobblestone on hand for it, otherwise wood. Its planks and sticks are queued ahead of it like any other recipe, once that's unlocked.
- **One entry at a time:** each kind gets one toolsmith entry, at the first finished bench. If you remove the entry, the toolsmith queues it again. To stop it, give them another job.
- **While a spare is coming:** a resident whose tool broke shows "Axe broke. Waiting for the toolsmith’s spare" until it's made.

**Equipping a chosen tool** (owner's request, made alongside #49):
- **The Equip button:** the resident panel's Axe and Pickaxe rows show **Equip** whenever an axe or pickaxe is lying about or stockpiled. It lists each one with its uses left and where it is, best first.
- **Choosing one** is a direct order: the resident walks over and picks it up, leaving the tool they had where the new one lay.
- **Keeping it:** a chosen tool is **kept until it breaks**. The resident doesn't swap it for a better one lying around. "Kept until it breaks" shows under the row, with **Use the best** to let them swap again.
- No repairs yet. Worn tools keep their uses (Slice 1, §7).

## 7. Recruitment

- **A traveler arrives when a finished house has a free bed**, after a short delay (45 seconds). One arrives per free bed, one at a time.
- They walk in from the map edge and claim the house. The first traveler is always Tomas; then Mira, Jonas, Elsa, Bram, Ines, Otto and Lena.
- **Each resident has their own tunic colour (#79)**, so they can be told apart on the map. Ada's is teal, and each traveler's is fixed with their name: plum, orange, blue, violet, maroon, jade, pale grey and pink. The hues are far from the grass, from each other and from the chalk marks. A tenth resident repeats Tomas's colour, as their name does.
  - Behind a tree or wall, a resident shows as a faint silhouette in their tunic colour rather than plain chalk.
  - Hovering a resident, or selecting them, shows a chalk name tag above their head. Like the other marks, it's drawn over everything.
  - The selection ring is a thick chalk band on a dark under-stroke, also drawn over everything.
  - A swatch of the tunic colour sits beside the resident's name in the resident panel and the multi-select list, before a toast about them, and on their stuck-list entries.
- **A finished house without a bed** shows "House needs a bed: 3 more wool" in the stuck list once wool runs short, since that's what's stopping arrivals.
- Food doesn't gate arrivals, but newcomers do need feeding, so food production has to grow with the village.

## 7a. Craft menu in the toolbar (#57)

Once a crafting bench is finished, a **Craft** button appears in the orders toolbar (default key C, rebindable).
- It opens the bench panel above the toolbar, so crafting doesn't need the bench in view.
- **The recipes and queue appear only there, on the right.** Selecting the bench in the world, or its entry in the stuck list, opens the Craft panel at that bench. The selection panel on the left shows just a summary: the bench's status, any stuck reason, and an "Open the craft menu" button when the panel is closed.
- Esc closes it.

**Layout (#76, #95).** The panel is laid out like a crafting table's screen, in the HUD's slate-and-chalk style (decided with the owner), with our own code-drawn item icons.
- **Tabs:** with more than one station, a row of tabs at the top, one per bench and fireplace ("Bench", "Fireplace", "Bench 2"). A station with a blocker has a yellow flag on its tab.
- **What it's doing** and its first stuck reason come first, in a line of fixed height.
- **Recipe book** (left): a slot per recipe at the station, showing its result's icon. Click one to show it. A recipe there isn't enough on hand for one of is dimmed, with a yellow corner. On hand means in the station, on the way, or lying about.
- **Crafting grid** (middle): the chosen recipe's ingredients on a 3×3 grid in its pattern, as in Minecraft: planks are a log, sticks two planks stacked, an axe three planks and two sticks in an axe's shape. Slots of an ingredient the village is short of are outlined in yellow. **The grid only shows the recipe:** residents fetch the ingredients, so nothing is dropped into it. The patterns are display data in `defs.gd` and never change what a recipe costs.
- **Fireplace:** a furnace instead of a grid: what's cooked (with its count), a flame, and the fuel below. Cooked mutton burns a log; bread needs no fuel.
- **Arrow and result:** an arrow to the result slot, with its count, the recipe's name, and **− Queue n +** (#76). The count stays per recipe, from 1 to 20.
- **Queue:** below a rule, a hotbar of slots, one per queued item; the first fills as it's made, and the toolsmith's and auto-queued entries carry a small T or A. Clicking a slot removes it. Past 8, "and N more".
- **On hand:** the station's ingredients as read-only slots with counts.
- **Steady layout:** everything above the queue keeps its size, so the Queue control never moves under the cursor while the queue changes.
- **Fit:** at 1280×720 the bench panel sits under a short stuck list without covering the house blueprint. A long stuck list can be folded (§9) to make room.

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
| Chopping block (1×1, #177) | Sawmill | 3×3, block at its back wall; its pile sits on the two cells beside it |
| Mason's bench (1×1, #177) | Mason's workshop | 3×3, bench at its back wall; its pile sits on the two cells beside it |

| Storehouse (3×3, #189) | A bigger storehouse | 3×5: its footprint and two rows behind it, away from the door |

A bench placed in Slice 1 (in older saves) has no reserved plot. It can be upgraded later only if the 3×3 around it happens to be clear.

| Thing | How | Cost |
|---|---|---|
| Bed | House stage 4 | 3 wool, 3 planks |
| Fireplace | Build menu, K | 6 cobblestone (reserves a 3×3 kitchen plot) |
| Chopping block | Build menu (#177) | 4 planks (reserves a 3×3 sawmill plot) |
| Mason's bench | Build menu (#177) | 2 planks, 4 cobblestone (reserves a 3×3 mason's workshop plot) |
| Storehouse | Build menu (#189) | 6 cobblestone, then 12 planks and 4 logs (reserves room behind it) |
| Chest | Bench recipe (#189) | 8 planks |
| Keep mark | Gather menu, Keep (click or drag) | — |
| Toolsmith's bench, composter, hunter's lodge, builder's table | Build menu (#184) | See §5 |
| Farm plot | Farm order, P (drag) | free |
| Hunt mark | Hunt order, G (click or drag) | — |
| Meadow trip | Resident panel: Send to the meadow | — |

**The storehouse (#189)** is the village's main storage. Painted stockpiles stay, as overflow.
- **The building:** 3×3, from the Build menu, built in two stages (a cobblestone floor, then plank walls). It holds nothing until it's built. Its door is the middle of its front side, which R turns, and its upgrade plot runs back from the door.
- **Chests:** a chest is crafted at the bench (8 planks) and carried in by a hauler. A storehouse holds up to **4 chests**, each with **9 stacks of anything**, so storage grows visibly. Chests sit inside the low walls, clear of the path from the door, and each lid shows squares of the first few kinds of thing in it.
- **Hauling:** haulers carry a loose item to the nearest storehouse with room for it, before any stockpile. A workstation's pile still comes first for its own logs or cobblestone. Stockpile cells take the overflow: they're used only when no storehouse has room, or before the village has one. Haulers carry chests in before they put anything away.
- **Fetching:** residents reach what's in a storehouse at its door. Crafting, cooking, building, equipping, eating and packing take from the chests as from a stockpile.
- **Its panel** shows its chests, how many of their stacks are full, and what they hold.
- **Before any storage:** the founding's first logs stay where they were dropped, as before.
- **Later (each its own issue):** more chests or a bigger building, storehouses marked for food or crafting, a granary or pantry, and a loading dock by the village station.

## 9. Stuck reasons added

- "Starving: no food stored", and "Hungry" on the resident.
- "House needs a bed: N more wool".
- "Fireplace: Bread needs N more wheat", using the bench's wording rules.
- When placing a job building, "Not enough room to grow into a kitchen" (or a workshop) if its reserved plot would overlap a building or the map edge.
- "Toolsmith needs N more X for a spare Y".
- "No one is a farmer" (or hunter, cook, and so on), when there's work of that type, no resident has the job, and Ada can't see to it (§5, #134).
- "Meadow has no sheep left", when a trip is planned.
- Workstations (#177): "Chopping block: No trees in range. Plant saplings or move the chopping block", "Mason's bench: No boulders in range", and "Stonemason: no pickaxe" on a stonemason with none to pick up. Waiting, not stuck: "Target reached (20 cobblestone)", "Full (20 logs)" (the overflow goes to the stockpile), "Saplings growing: no grown trees in range yet", and "No lumberjack to work it" while no one has claimed it.
- "Tomas: Build a composter to start work", for a resident whose job has no free workstation (#184).
- Storehouses (#189): "The storehouse is full" when a loose item has nowhere to go (beside "Stockpile is full" when there's a stockpile too), "Can’t reach the storehouse: its door is blocked", and "No chests yet. Craft one at the bench (8 planks)".
- "Tomas: Hunter: herd at its floor (2 sheep)" or "Hunter: no animals to hunt", waiting, for a hunter with nothing above the floor and nothing marked (#183).

**Stuck and waiting (#77).** The stuck list has two tiers:
- **Stuck:** work that can't go on. These entries get a yellow flag in the list and on the map, and the list puts the longest-stuck first. An entry keeps its age while only its count changes ("4 more planks" becoming "3 more planks").
- **Waiting:** a standing order (the toolsmith's spare, the fireplace's meals) that's short of materials. It's advice rather than a blocker, so it has no flag. The tier is one dim line, "2 standing orders waiting", that opens on click to show the entries in dim text.
- **Folding:** clicking the "Stuck (n)" header folds the list into a small chip under the speed buttons. A new blocker opens it again. With nothing stuck but something waiting, the list is just the waiting line.

## 10. Saving

Slice 2 changes the save format one step per change, each with its own upgrade step and fixture, rather than in one jump. **v4 (#52) adds the map size.** Later steps add sheep, farm plots and wheat growth, the fireplace, its queue, standing order and reserved plot, reserved plots for new benches, residents' hunger, job toggles, priorities and skills, the meadow's remaining sheep, residents away on trips, and the new tunic colours.

Taken together, the upgrade steps:
- Record the map size as 18×18 for saves from before v4, so older saves keep their size (v3→v4).
- Gives existing residents full hunger, all jobs on at priority 2, and level 1 everywhere.
- Adds a finished bed to every finished house (so old saves keep their residents housed).
- Adds no farm plots (v7→v8, #45).
- Gives existing residents every job on at priority 2 (v9→v10, #47).
- Gives existing residents level 1 in every job (v10→v11, #48).
- Gives each resident one job, and Ada Everything, in place of the switches and priorities (v21→v22, #134; see §5).
- Hands existing benches, fireplaces, chopping blocks and mason's benches to residents whose jobs match (v23→v24, #184; see §5).
- Starts every species at the default herd floor (v24→v25, #183).
- Gives each existing chopping block and mason's bench the default standing order: 20 planks, 10 stone bricks (v25→v26, #178).
- Turns automatic ingredients on and carries the founding's progress over to the reworked goals (v26→v27, #182; see above).
- Nothing changes for storehouses (v27→v28, #189): older saves have none. A storehouse saves its chest count, and its chests' stacks are saved with the map's items, keyed by chest slot.
- Turns a Mine resident into a Lumberjack, with Mine's experience in both Lumberjack and Stonemason (v22→v23, #177; see §5). No village has a workstation, sapling or Keep mark yet.
- Marks no tools as chosen (v11→v12, equipping).
- Gives older saves a full meadow with nobody away (v12→v13, #50).
- Swaps each resident's old tunic for the new colour in the same place on the list (v13→v14, #79).
- Gives existing buildings no reserved plot, so Slice 1 benches reserve nothing (v8→v9, #46).
- Adds no sheep to the clearing (old saves are past the opening).
- Gives the meadow its starting 8 sheep.

## 11. Controls added

| Key | Action |
|---|---|
| E | Open the Gather menu (#94) |
| X | Mine order, directly |
| G | Hunt order, directly |
| Z | Open the Paint menu (#93); Z then 1 is Stockpile |
| P | Farm plot order, directly |
| B | Open the Build menu |
| J | Open the Village jobs board (#78) |
| 1–9, while a toolbar menu is open | Pick that row (B then 2 places a house) |
| K | Place a fireplace |
| A drag that starts on a painted cell | Erase that zone: stockpile cells (#63) or farm plots (#93) |

All are rebindable (Slice 1, §10), except 1–9 inside an open menu. Chop trees, Break boulders, Keep, Stockpile and the workstations from #177 and #184 have actions with no default key. Settings files from before #93 hand Z from Stockpile to the Paint menu. A new default key the player has already given to something else is left with them, and the new action starts with no key.

**Orders toolbar (#93, #94).** The toolbar is **Gather ▸ · Paint ▸ · Build ▸ · Craft**. This replaces Slice 1's Mine, Hunt, Stockpile and Farm buttons (slice-1-spec.md §10, §12).
- **Menus:** Gather, Paint and Build each open a small menu above the toolbar, all built from one control and one data table, so a later order is a new row rather than a new button. Each row shows the order's mark, its name, a line about it, its number in the menu, and its direct key if it has one.
- **Picking a row** switches that order on (or starts placing that building) and closes the menu. Unlike the direct keys, picking the order that's already on leaves it on.
- **Gather:** Mine (trees and boulders), Chop trees (trees only), Break boulders (boulders only; the stuck list still says "Needs a pickaxe"), Keep (in the village, #177), and Hunt, which shows while there are live sheep. Shift-drag and Alt-drag still limit Mine to trees or boulders.
- **Paint:** Stockpile and Farm plot. Farming is available from the start, so Farm plot always shows.
- **What's on:** while one of its orders is on, the Gather or Paint button names it, as in "Gather: Hunt" or "Paint: Farm plot", and shows that order's mark. Otherwise the button reads "Gather ▸" or "Paint ▸".
- **Right-click** on the ground with residents selected still sends them there while any Gather or Paint order is on, and leaves the order on. With a menu open, right-click closes it. Right-click on a tree, boulder or animal opens the radial Gather menu (#176, below).

**Radial Gather menu (#176).** Right-clicking a tree, boulder or animal (an ore block counts as a boulder) opens a ring of wedges centred on the cursor, with or without residents selected.

| Target | Wedges |
|---|---|
| Tree | **Chop** (mark it for anyone), **Chop now** (order the selected residents), **Chop all trees nearby** (marks the trees within 4 cells) |
| Boulder or ore | **Break**, **Break now**, **Break all nearby** |
| Animal | **Hunt**, **Hunt now** |
| Already marked | **Cancel** takes the first wedge's place |

- **"Now" wedges** show only with residents selected. They're direct orders, as right-click gave before.
- **Choosing:** click a wedge; or press right, drag to a wedge and release on it; or press 1–4. Esc, a click outside the ring or a right-click on the ground closes it. A right-click on another target moves it there.
- **Never silent:** a wedge that can't work now is greyed, and hovering it says why, in yellow below the ring: "Break now: Tomas has no pickaxe", "Chop now: Ada is away" (or starving, or hurt). Picking it says so in a toast.
- **The middle** names the target and what it drops ("Tree · 4 logs", "Sheep · 1 wool and 1 raw mutton"). Clicking it selects the target.
- **Shift + right-click** on a target skips the radial and queues the order (Chop now, Break now or Hunt now) for the selected residents, as before. It's the fast path.
- **Look:** slate wedges with chalk outlines and each order's mark, the hovered one filled in chalk, drawn over the world without motion.
- Placing a building, right-click still cancels the placement. The Gather and Paint orders and drag-marking are unchanged: the radial is for single targets.
- **Erasing farm plots:** with Farm plot on, a drag that starts on a plot erases the plots in its rectangle, previewed in red like stockpile cells. Anything growing on them is lost, as with the plot panel's Remove plot.

**Tools dropdown (#90).** A click pins the list open, and a second click unpins it. A click anywhere outside the button and the list, or Esc, closes it. Only keyboard focus (tabbing to the button) holds it open, not the focus a click leaves behind. Hovering the gap between the button and the list counts as hovering, but the rest of their bounding box doesn't, and the mouse leaving the window ends hovering.

**Erasing stockpile cells (#63).** With the Stockpile order on, a drag that starts on a stockpile cell erases every stockpile cell in its rectangle instead of painting, and a click on one cell erases just that cell, as clicking a marked tree unmarks it under Mine.
- **Preview:** while erasing, the rectangle is outlined in cut red and each cell that will go is filled red, with the hint "Release to erase these stockpile cells".
- **Items left behind:** stacks on erased cells stay where they are and count as loose. They're hauled to the cells that are left, if any have room.
- **Haulers on the way:** a haul heading to an erased cell heads for another cell with room instead. If none has room, the haul ends and anything carried is set down, loose.
- **No stockpile left:** erasing the last cell brings back the usual no-stockpile behaviour (nothing is hauled). "Stockpile is full" shows as before when the remaining cells have no room.

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
| `work_radius` | 8 cells around a chopping block or mason's bench (#177) |
| `work_store` | 20 logs or cobblestone in a workstation's pile |
| `keep_stock` / `keep_step` | 20 by default / steps of 5 |
| `make_keep` / `make_step` | 20 planks at a chopping block, 10 stone bricks at a mason's bench / steps of 5 (#178) |
| `chests` / `chest_stacks` | 4 chests in a storehouse / 9 stacks in a chest (#189) |
| `herd_floor` | 2 wild animals of each species, until changed on the jobs board (#183) |
| `saplings` / `sapling_extra` | 1 per felled tree / 30% chance of a second |
| `sapling_grow` / `plant_tree_time` | 300 s / 2 s |

## 13. Open questions (not blocking the start)

- **Regrowth (#22):** do trees regrow from saplings? Without regrowth, a long game runs out of trees. (Decided: the meadow regains 1 sheep every 4 minutes up to 8. Trees don't regrow yet.)
- **Building customization (#21):** still fixed templates in Slice 2.

## 14. Deferred

Rest and sleep, happiness, shears, the inn, travelers' requests, food variety effects, spoiling, and tables for eating. Breeding came in with Slice 3.5's pens (`slice-3.5-spec.md`).

**Building upgrades** (designed in §8, built later):
- **Fireplace → kitchen:** a bigger queue, two cooks at once, and new recipes.
- **Bench → workshop:** two crafters at once, and later tool repair.
- **Farm plot → barn-backed farm:** seed storage, and later fences.
