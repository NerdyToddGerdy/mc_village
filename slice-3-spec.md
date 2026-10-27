# Slice 3 Spec — The First Expedition

Companion to `block-village-design-brief.md`, `slice-1-spec.md` and `slice-2-spec.md`. Slice 3 builds on everything in Slices 1 and 2; this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table (§16).

Tracking issue: #12. Decisions settled with the owner (2026-10-20), and recorded in the brief (§5, §8, §13, §14):

| Question | Decision |
|---|---|
| Destination | **An old mine** a short walk off the map. Stone and coal, with **iron** as the discovery. |
| Discovery payoff | Iron ore, smelted at the fireplace with coal, gives iron ingots, which make **iron tools** at the bench. |
| How it's shown | A **small second block map** for the mine site, with its own view. Travel is a timed walk, like the meadow. |
| Party (#23) | **1–3 residents**, Ada eligible. **One expedition out at a time.** |
| Danger | **Hazards cause injuries** (cave-in, fall, darkness). No mobs or combat, so #19 stays open. |
| Injuries | An injured resident walks and works slower and can't mine. A **serious injury** triggers the retreat return policy. Injuries **heal over time in the resident's own bed** at home. |
| Ada (#17) | **Ada is protected:** she can be hurt, but never seriously, and the party always gets her home. Death stays open (#20). |
| Interrupts (#25) | The game pauses for the player **at the discovery** and **when someone is seriously hurt**. Everything else follows the return policy. |

Still open: #19 (combat), #20 (death and rescue), #22 (regeneration: the old mine's ore doesn't come back, the rest is open), #66 (night time and mob drops).

## 1. Scope and done criteria

Slice 3 is done when, from a Slice 2 village, a player can:

- [ ] Build an expedition board and read the old mine's site report.
- [ ] Plan a party of 1–3 with provisions, spare tools, a cargo target and a return policy, and see supplies and cargo share the carrying capacity.
- [ ] Watch supplies get packed, then send the party off and see the village keep working without them.
- [ ] Switch to the old mine and watch the party mine, eat from its provisions and fill its packs.
- [ ] Decide what to do when the party finds iron, and when someone is seriously hurt.
- [ ] See the party come home, unload, and the cargo get hauled to the stockpile. Injured residents heal in bed.
- [ ] Smelt iron and craft an iron pickaxe.
- [ ] Understand every stall from its on-screen reason alone.

## 2. More than one map (#100, #101)

**Maps.** The sim holds the village plus any number of **site maps**, each its own block grid with its own trees, boulders, items, stockpile cells and buildings. The village's id is `"village"`; the old mine's is `"old_mine"`.

**Who is where.** Every resident and every building records the map it's on. Paths and jobs never cross maps: a resident only claims work on their own map. Moving between maps happens only through travel (#108). Nothing walks from one grid to another.

**Every map ticks every tick**, so work on a map nobody is looking at still happens.

**The village's counts are the village's.** The tally bar, the goals and the save summary count only what's in the village. Coal lying at the mine isn't in the village's stock until it's carried home.

**Stuck reasons and toasts** carry their map. Clicking one about the other map switches the view to it first.

**Paint and Build are for the village.** On a site map, the toolbar shows only Gather and Craft. Stockpiles, farms and buildings can't go on a site; an expedition packs what it gathers instead (§11).

**Switching the view.**
- A chalk **map switcher** in the tally bar shows **Village** and, once it's known, **Old mine**. The default key is **Tab**, rebindable.
- Each map keeps its own camera position and zoom. A map seen for the first time opens near its entrance.
- The selection clears when you switch, since it belongs to the map left behind.
- While residents work on a map that isn't in view, a dim line under the tally bar says so, "Party at the old mine: mining", and switches to it on a click.

**Saving.** Save format **v15** stores each map separately, with residents and buildings tagged with their map, and the camera of each map plus which map was in view. Older saves upgrade with everything on the village map and get an unvisited old mine when they load.

## 3. The old mine (#102)

**The map** is hand-laid, **16×16**, with:
- the **entrance** on the west edge, where a party arrives and leaves, under a timber frame;
- **rock walls**, which can't be mined;
- **6 boulders** (cobblestone) and **6 coal ore** blocks;
- an **iron vein** of 4 blocks, hidden behind rubble at the end of the deepest tunnel;
- the **door down** to Level 2 on the east edge, behind a boulder (§13a, #132), reached by a way round the loose ceiling in the east tunnel.

**Mining** works as in the village: the Mine and Break orders mark boulders and ore, and residents with a pickaxe break them. Ore blocks drop their ore (§4).

**Light.** Torches on the walls light the tunnels near them. Floor further than the torch light (§16) from every torch is **dark**, drawn darker so the dark tunnels read at a glance. Darkness is a hazard (§12).

**The hidden vein** stands as plain rock wall until it's found (§13): it can't be marked, mined or walked through, and the site report doesn't show it.

**Depletion.** Ore and boulders don't come back once mined, and the site report's estimates go down as they're mined. Tree regrowth stays open (#22).

**The site report** (brief §8), shown on the expedition board (#105) before departure:
- **Before anyone has been there:** what the village has been told ("An old mine a short walk east. Stone and coal, they say."), the travel time, and stone and coal with no estimates. No hazards or access notes are known yet.
- **Once visited:** estimated reserves for stone and coal, and iron as **"?"**; the known hazards ("Dark tunnels past the torches"); and access notes ("Narrow tunnels: 1 resident per tunnel").
- **Once the iron is discovered:** iron and its estimated reserve.

## 4. Coal, iron ore and iron ingots (#103)

| Item | From | Used for |
|---|---|---|
| Coal | Coal ore blocks | Smelting fuel (§5) |
| Iron ore | The iron vein, once it's discovered | Smelting into ingots (§5) |
| Iron ingot | Smelting at the fireplace (§5) | Iron tools (§5) |

Each has its own colour, distinct from cobblestone and logs, an icon for the Craft panel, and a tally in the Materials group once it first turns up. Ingots are stacked as crossing layers of bars. Hauling and stockpiling treat them like any other item. On a site map, they're packed as cargo instead (§11).

## 5. Smelting and iron tools (#104)

**Smelting.** The fireplace gains **Smelt iron**: 1 iron ore and 1 coal make 1 iron ingot, in `SMELT_TIME`. Coal goes in the furnace's fuel slot. It's Cook work, like everything at the fireplace, and it's queued by hand: the standing order only makes meals.

**Iron tools** are made at the bench, the third tier after wood and stone:

| Recipe | Takes | Makes |
|---|---|---|
| Iron axe | 3 iron ingots, 2 sticks | 1 iron axe |
| Iron pickaxe | 3 iron ingots, 2 sticks | 1 iron pickaxe |

They last longer and work faster than stone (the tier rows in §16). Residents already prefer the best tool about, so an iron one is picked up over stone.

**The toolsmith's spare** is the best tier there's material for: iron when there are 3 ingots, then stone, then wood.

## 6. The expedition board (#105)

**Building.** A 1×1 job building in the Build menu, shown once the founding is done. It costs 6 planks and 4 sticks and is built in one stage, like the bench. Like the bench and the fireplace, it reserves the 3×3 plot its upgrade, the **map room**, will need, and **R** turns which side the plot is on.

**Look.** A plank board on two posts with a map pinned to its face: the route to the old mine, and a red pin at the end.

**Word of the old mine.** When the board is finished, the village learns of the old mine: it becomes **known**, so the map switcher shows it, though nobody has been. A toast says so.

**Selecting the board** opens the expedition planner above the toolbar (§7). Before the first expedition, it shows the old mine's site report (§3).

**Staging.** The row of the plot in front of the board is where the party gathers. Packed supplies stack up as crates on the row beyond it.

## 7. Planning (#106)

The planner draws up one plan:
- **Destination:** the old mine, the only one in Slice 3.
- **Party:** 1 to 3 residents (`PARTY_MAX`), Ada included. Each is listed with their Mine level, pickaxe and hunger. Anyone who can't go is listed with why: away at the meadow, still walking in, on the road, or already at a site.
- **Objective:** bring back N of a resource the village knows the site has: stone or coal, and iron once it's discovered.
- **Provisions:** meals to take, with an estimate of the minutes at the site they cover, counting a meal as `MEAL_FOOD`.
- **Return food:** `RETURN_MEALS` per member is kept for the walk home and left out of the estimate. **Spend it** lets the party eat it (brief §8).
- **Spare pickaxes** to take.
- **Packs:** each member carries `PACK_CAPACITY` items. A meal or a spare pickaxe takes 1, and cargo gets the rest, so more provisions leave less room to bring things back. A bar shows supplies, the cargo target and what's spare.
- **Return policy:** any of target reached, packs full, or food running low. A serious injury stops the game for the player, who can call them home (§12).

**What stops a plan** is listed in the player's words, and **Start packing** stays disabled until there's nothing:
- no party, or more than 3;
- someone who can't go;
- fewer meals than the walk home needs;
- supplies that fill the packs, or a target bigger than the room left;
- no return policy.

**Start packing** confirms the plan. It starts packing (§8) and sends nobody yet.

**One at a time** (#25): while an expedition is packing or out, the board shows that one instead of a new plan.

## 8. Packing and departure (#107)

**Packing.** Once a plan is confirmed, its meals (bread or cooked mutton) and spare pickaxes are delivered to the board by residents with Haul on, before any stockpile hauling. A spare pickaxe keeps its wear. What's packed is the board's: nobody eats it and nothing else uses it. It shows as a growing pile of crates.

**Gathering.** Party members finish what they're doing, then pack (whether or not they have Haul on, so a party of one can still pack), then walk to the board and wait. A hungry member goes to eat and comes back. While packing, the party takes no other village work.

**Stuck reasons:**
- "Expedition: Waiting for 2 meals to pack", "Waiting for 1 spare pickaxe to pack" and "Waiting for Tomas" sit in the stuck list's dim waiting tier. They're progress, not blockers.
- "Expedition: No meals to pack. Cooks make them at the fireplace, or plan fewer" is a blocker, with a flag over the board. The same goes for spare pickaxes ("Craft one at the bench, or plan fewer").

**Depart** is the player's call (brief §10). The button is enabled once everything is packed and the whole party is at the board, and otherwise says what it's waiting for. From then on, party members are out of village labor: their jobs end and they set off for the signpost (§9). The packed supplies go with them, and the board is empty again.

**Calling it off.** Before departure, **Call off the expedition** (a destructive button) unpacks everything. The supplies are set down by the board, loose, and hauled back to the stockpile, and the party goes back to work.

**Saving.** Save format **v16** saves the expedition (the plan, its state, and what was packed and carried), and each resident's `trip`. What's packed at the board is saved with the board, tools with their wear. Older saves have no expedition, and anyone away is at the meadow.

## 9. Travel (#108)

**The route signpost** stands on the village's east edge, halfway down, pointing off the map toward the old mine. Like the meadow's, it can't be built on, farmed or stockpiled. Selecting it shows the walk (`MINE_TRIP` each way) and who's on the road or carrying the packs to it.

**Outbound.** After Depart, each party member walks to the signpost carrying the packs, drawn as a crate on their side. There they step off the map and are **on the road** for `MINE_TRIP`, then appear at the site's entrance. On the way, they take no village work.

**On the road**, residents aren't drawn on either map, don't work and don't get hungry. Their panel, the signpost and the line under the tally bar say "On the road to the old mine, N s" or "On the road home, N s". The line switches to the place they're headed when clicked.

**Arriving.** At the entrance, the site counts as visited, and the party works from its packs (§11).

**Coming home.** The party heads home when its return policy is met (§11), when the player chooses Retreat (§12) or Mark it and return later (§13), or when the player calls it home with **Call the party home**: beside the party line while the site is in view ("The party is here: mining"), on the board's planner, or on a party member's panel. That's enabled once the whole party is at the site. Each member walks to the entrance and steps onto the road home, with the packs. Whatever wasn't packed stays at the site.

**The way home** takes the same `MINE_TRIP`, until Slice 4's minecarts shorten it. They appear at the village signpost.

**The meadow** trip is unchanged. Both trips use the same "away on the road" code: a resident who's away has a `trip` saying where to ("meadow", a site, or "village" for home) and a time they're due.

**Saving.** No format change: the expedition's `leg` (out or home), its cargo and its count of broken pickaxes are new keys in the saved expedition, and travel is the residents' `away`, `trip` and due time, as in v16.

## 10. Return and unloading (#112)

**Unloading.** When the last party member is back at the signpost, the cargo and leftover meals and tools are set down there as stacks. They're hauled to the stockpile by anyone with Haul on, the party included, before other loose items. With no stockpile room, the usual "Stockpile is full" applies.

**The report** is a toast, and stays on the board's planner under "Last expedition":
- "Back from the old mine: 9 coal, 6 cobblestone" (or "with nothing mined");
- "3 meals eaten, 1 pickaxe broken". Meals eaten are the packed meals that didn't come back;
- "Tomas seriously injured", when anyone was hurt (§12).

**Recovery.** The party rejoins village labor straight away, and anyone hurt goes to bed to heal (§12). The expedition is over, so the board can plan the next one.

## 11. The party works the site (#109)

**The packs.** Once out, the party's packs hold its meals (provisions), its spare pickaxes, and its **cargo**: what it mines. Together they fill `PACK_CAPACITY` per member. Nothing is set down at the entrance on arrival. The packs are drawn as crates just inside the entrance, a crate for every 3 items.

**Working by its orders.** At the site, party members work without the player and whatever their job toggles, in this order:
- The seriously hurt wait at the entrance (§12).
- A member whose pickaxe broke takes the best spare from the packs.
- Mined items are carried into the packs at the entrance. The objective's resource comes first until there's enough, then anything else mined. Extra of the objective is packed last, and only once nothing is left marked to mine, so the packs keep room for what's still to come.
- If the vein is to be investigated, someone with a pickaxe surveys it (§13).
- Members with a pickaxe, and not hurt, mine whatever is marked.

**Marking the objective.** The party marks blocks of the objective's resource itself, nearest the entrance first and one at a time, until what's packed, lying about and marked will make the target. It leaves blocks under a known loose ceiling (§12) for the player to choose. The player can still mark more on the site map with Gather.

**Eating** works as at home, but from the packs: a hungry member walks to the entrance and eats a meal. The return food (`RETURN_MEALS` each) is left alone unless the plan chose **Spend it**. With nothing left to eat, a member goes hungry, and says so.

**The return policy** is checked whenever the whole party is at work there, unless a choice is waiting for the player:
- **Target reached:** the objective's resource packed reaches the target.
- **Packs full:** no room left.
- **Food runs low:** no meals left the party may eat.
- And always: **nothing left to mine**, once nothing is marked or left of the objective, nothing is lying about to pack, and nobody is busy.

When one is met, the party heads home with a toast: "Heading home: target reached". **Call the party home** still sends them home at any time.

**The party panel.** While the site is in view, the panel under the party line shows each member's task, pickaxe and uses left, hunger and health; the packs against their capacity, the cargo by item, the meals left (and how many are kept for the walk home) and the spare pickaxes; the objective's progress; and what will bring them home. The board's planner shows the same while they're out.

**Stuck reasons** at the site carry its map, with the site's name as who's stuck:
- "Old mine: No pickaxe left. The party can only pack what's mined; call them home";
- "Old mine: Everyone is hurt, so nobody can mine. Call them home";
- "Old mine: The packs are full" (waiting, when the packs-full policy is off);
- "Old mine: Investigating the vein needs someone with a pickaxe".

## 12. Hazards and injuries (#110)

**Hazards** are specific events at specific places (brief §8), all in the site report once someone has been there:
- **Loose ceilings** over three of the old mine's blocks, drawn with cracks. Mining one brings it down on the miner with `CAVE_IN_CHANCE`, serious with `CAVE_IN_SERIOUS`. The party never marks these itself.
- **A ledge** in the dark tunnel to the iron: the floor drops, with a pale lip. Each step onto it in the dark is a fall with `FALL_CHANCE`, serious with `FALL_SERIOUS`.
- **Dark tunnels:** work there is slower (`DARK_WORK`), and the ledge is dark.

Rolls use the sim's seeded random numbers, so a game replays the same.

**Injured** (a white bandage on the resident, and "Health: Injured" in their panel): walks and works at `INJURED_SPEED`, and can't mine, by order or by job. At the site they still pack.

**Seriously hurt:** can't work at all. At the site, **the game stops** for the player (§13's choice dialog):
- **Retreat:** the party heads home now, with what it has packed ("Heading home: retreat, Tomas is seriously hurt");
- **Press on:** the hurt one waits at the entrance while the rest keep working, and walks home with them.

**Ada (the PC)** can be hurt, but never seriously: her injuries stop at injured, so she always walks home.

**Healing** happens at home. A hurt resident rests in **their own bed** (beside their house) for `HEAL_TIME`, then goes back to work with a toast. Without a bed of their own, they rest where they are, at `HEAL_NO_BED` speed. They eat when hungry, then go back to resting. The stuck list's waiting tier says "Tomas: Seriously hurt, resting in bed (240 s)", or "Injured, resting: no bed of their own, so it's slower (180 s)". A hurt resident can't join a party.

**The report** names who was hurt: "Ada injured, Tomas seriously injured".

Death and rescue stay open (#20).

## 13. The iron discovery (#111)

**Finding it.** Mining a block within `FIND_RADIUS` steps of the hidden vein finds it. In the old mine, that's the rubble at the end of the deepest tunnel. The vein is revealed and can be seen, marked and mined, though its size isn't known yet. A toast says "The party found iron in the old mine." With a party there, **the game stops** with three choices, each with its known cost:
- **Keep mining:** carry on for the objective. The vein stays marked.
- **Investigate:** a party member walks to the vein and spends `SURVEY_TIME` and `SURVEY_USES` pickaxe uses surveying it. Then the vein's size is known, and iron is a resource the planner can send a party for.
- **Mark it and return later:** the party heads home now.

**Remembered.** The find is saved knowledge. Until it's surveyed, the site report shows "Iron vein found, not surveyed" and iron with no estimate, and the planner can't target it. Once surveyed, iron has its reserve.

**Choices that stop the game.** The discovery and a serious injury share one mechanism: the sim keeps a list of **pending choices**, and the game pauses while there's one, can't be unpaused, and shows a centred dialog: what happened, "The game is paused until you choose", and each option with its cost. Answering carries on at the speed the game had. Pending choices are saved.

It's the only discovery in Slice 3.

**Saving.** Save format **v17** saves each resident's injury and healing time, the pending choices, the expedition's packs, the old mine's `found` and `ledges`, and its blocks' `loose`. Older saves upgrade with nobody hurt and no choice waiting, and the old mine gets its hazards. A party already out keeps its meals in the packs; one that had set its supplies down at the entrance finds them there and packs them again.

## 13a. Deeper levels (#132)

The old mine stays useful through **deeper levels**. Each level depletes; the mine as a whole doesn't (brief §13, #130).

**Levels.** The old mine is **Level 1**, the hand-laid old workings. Each level below it is a site map of its own, `old_mine_2`, `old_mine_3` and so on, about 16×16, named "Old mine, level 2". It appears on the map switcher once its door is opened.

**The door down.** Every level has a **door at its far end**, on the east edge, opposite the entrance on the west. On deeper levels the entrance is the way back up. The door is drawn from the start as a heavy plank door with iron bands in a timber frame, set in the rock, and there's always a block of stone in front of it, so the party has to mine its way there.
- **Dig to the door** (the party panel) marks the blocks between the party and the door, loose ceilings included: the player chose the way. The party never digs to the door by itself: marking blocks for its objective, it leaves the block in front of the door alone.
- Once the way is open, a party member walks to the door. **The game stops** with three choices, each with its cost, through the same pending-choice dialog as the discovery and serious injuries:
  - **Go down now:** the door opens and the party works the level below instead. The objective carries over.
  - **Mark it for later:** the party heads home now. The door stays marked.
  - **Keep mining here:** the party carries on with this level. The door stays marked.
- Reaching the door makes the level below ready. Opening it puts the level on the map switcher. A party bound for a level below a marked door opens it on the way down.

**A different pattern on every floor.** Level 1 is the old workings: straight tunnels with timber supports. Deeper levels are generated from the game's **seed** and the level number, so a level always comes out the same for a seed. Each comes from a **pattern family** (`game/sim/mine_levels.gd`):
- **Winding cave:** one meandering passage, a cell or two wide, with pockets off it.
- **Pillared hall:** a wide room broken by a grid of stone pillars.
- **Branching tunnels:** a maze of narrow tunnels, with ore in the dead ends.
- **Underground stream:** a cavern split by water that runs most of the way across. Water can't be walked through on a site map, so the way goes around it.
- **Collapsed chamber:** a field of rubble, with many loose ceilings.

The first five levels down use each family once, in an order the seed picks. After that, families come back with other settings (size, mirroring and where the ore lies), never the same family twice in a row. Every level keeps a minable way from the entrance to the door, and some coal and iron. Ore is set into the walls beside the floor, iron furthest in. Deeper levels' ore is in plain sight: there's no hidden vein below Level 1.

**Going down and up.** The party walks: through the road and Level 1's entrance, across each level to its door, and down through it, so each level down adds a walk across the level above. Coming home, the party walks to each level's entrance and up into the level above, in front of its door, then on to the road. Cargo comes back up the same way, in the packs. Rail ends at the mine entrance (Slice 4).

**Room for the objective.** Digging through a level gives stone the party didn't come for. The packs keep room for the rest of the objective: anything else is packed only into the room left over (this applies at every site).

**Deeper is richer and riskier.** Each level down adds `LEVEL_ORE` coal and iron blocks to Level 1's 6 coal and 4 iron, and has fewer torches (`5 − level`, at least 1), so more of it is dark. The cave-in and fall chances rise by `LEVEL_RISK` of Level 1's for each level down, and there are more loose ceilings and ledges.

**The site report** names the level's pattern and, for any level of the old mine, lists every level known so far: its pattern, the ore blocks left (once visited) and whether its door is open, found or not reached. Before anyone has been down, a level's report says "Behind the door at the far end of the old mine. Nobody has been down." Its travel time adds the walk across the levels above to the road's.

**Planning.** Once there's more than one level, the planner has a **Work level** row, a button per level. The objective, reserves and travel time are that level's.

**Saving.** Save format **v20** saves the seed and each level's map (its pattern, door and door state, and what's been mined), like any other map. Older saves get the seed, and the old mine gets its door with a boulder in front of it, not yet reached, and the opening beside it that avoids the loose ceiling.

## 14. The Slice 3 playtests (#113)

**The bot** (`tests/playtest_slice3.gd`) starts from a Slice 2 village saved in `tests/fixtures/slice2_village.save`, made once by `tests/fixtures/make_slice2_fixture.gd`. Through input, it builds the board, plans Ada and Tomas for 10 cobblestone, packs and departs, keeps the village working, marks the rubble, answers the discovery with Investigate, marks iron and coal, answers a serious injury (triggered by the test) with Retreat, watches the return and unloading, smelts iron and crafts an iron pickaxe. It fails on any blocker in the stuck list that doesn't name something the player can do.

**The hand playtest** is the owner's: the checklist is in the PR for #113.

## 15. Controls

| Action | Default key |
|---|---|
| Switch between the village and a site | Tab |
| Place an expedition board | None (rebindable). It's in the Build menu |

## 16. Tuning table (provisional)

| Name | Value | Meaning |
|---|---|---|
| Old mine size | 16×16 | Cells (its layout is hand-laid in `game/sim/old_mine.gd`). |
| `MINE_TRIP` | 60 s | Time on the road between the village signpost and the old mine, each way. |
| `ORE_YIELD` coal | 2 | Coal dropped by a coal ore block. |
| `ORE_YIELD` iron | 2 | Iron ore dropped by an iron ore block. |
| `TORCH_LIGHT` | 3 cells | How far a torch lights; open floor beyond every torch's light is dark. |
| `SMELT_TIME` | 5 s | Smelting one iron ingot at the fireplace. |
| `CHOP_TIME` iron | 3.5 s | Felling a tree with an iron axe (stone 5 s). |
| `BREAK_TIME` iron | 4 s | Breaking a boulder or ore block with an iron pickaxe (stone 6 s). |
| `DURABILITY` iron | 60 uses | An iron tool's uses (stone 25). |
| Expedition board cost | 6 planks, 4 sticks | One stage. |
| `PARTY_MAX` | 3 | Residents in a party, at most. |
| `PACK_CAPACITY` | 15 | Items each party member carries, shared by supplies and cargo. |
| `RETURN_MEALS` | 1 | Meals per member kept for the walk home. |
| `MEAL_FOOD` | 50 | Food a meal counts as when estimating time at the site (bread's). |
| `CAVE_IN_CHANCE` | 0.5 | Chance that mining a block under a loose ceiling brings it down on the miner. |
| `CAVE_IN_SERIOUS` | 0.5 | Chance a cave-in's injury is serious. |
| `FALL_CHANCE` | 0.05 | Chance of a fall each time someone steps onto a ledge in the dark. |
| `FALL_SERIOUS` | 0.25 | Chance a fall's injury is serious. |
| `DARK_WORK` | 0.7 | Work speed in an unlit tunnel. |
| `INJURED_SPEED` | 0.6 | Walk and work speed while injured. |
| `HEAL_TIME` | 120 s, 300 s | Rest in bed to heal: injured, seriously hurt. |
| `HEAL_NO_BED` | 0.5 | Healing speed without a bed of one's own. |
| `FIND_RADIUS` | 2 steps | Mining a block this close to the hidden vein finds it. |
| `SURVEY_TIME` | 15 s | Investigating the vein. |
| `SURVEY_USES` | 3 | Pickaxe uses investigating takes. |
| Loose ceilings, ledge | 3 blocks, 1 cell | Placed in `game/sim/old_mine.gd`. |
| Deeper level size | about 16×16 | 15–18 by 14–17 for a family that comes back (#132). |
| `LEVEL_ORE` | coal 2, iron 1 | Ore blocks each level down adds to Level 1's 6 coal and 4 iron. |
| `LEVEL_RISK` | 0.25 | Each level down raises the cave-in and fall chances by this share of Level 1's. |
| Torches on a level | 5 − level, at least 1 | Fewer the deeper it is. |
| Loose ceilings on a level | 2 + level | Plus 6 in a collapsed chamber. |
| Ledges on a level | 1 + level ÷ 2 | In the dark. |


## Diamonds on the deep levels (#186)

From **level 4** down (`MineLevels.DEEP_ORES`, data: the first level, a base count, one more every `every` levels, a maximum; a later ore is a new row), a level has **diamond ore**: 1 block on level 4, more the deeper (2 from level 6, 3 from level 8), placed from a stream of its own so every other part of a level, and every level above 4, is exactly as it was. The blocks are **hidden** like the iron vein: unseen, unmarked and not in any report until someone mines within `FIND_RADIUS` of one.
- **The first find** on a level (`Sim._check_find_diamond`) reveals the level's diamonds, makes diamonds a known resource of that level (`SimMap.diamond_found`, the site report's resources, `plan_targets`, so a row for the cargo priority list, joining at the bottom marked New), and stops the game: "The party found diamonds on level 4 of the old mine", Keep mining or Mark it and return later.
- **An iron pickaxe is needed** (`Tuning.DIAMOND_PICK_TIER` 3). With less, a gather job fails with "Diamond ore needs an iron pickaxe"; the party doesn't mark diamonds unless someone (or a spare in the packs) has one (`Sim.can_mine_diamond`), and the site's stuck list says "Diamond ore needs an iron pickaxe". A block gives 1 diamond.
- **The item.** `diamond` (Ores group, so it's in the tally bar's dropdown; pale cyan, with a cut-stone icon). **Diamond axe and pickaxe**, tier 4 (3 diamonds and 2 sticks each, at the bench): `CHOP_TIME` 2.5 s, `BREAK_TIME` 2.5 s, 150 uses. **The toolsmith** queues a diamond spare when there are 3 diamonds, then iron, then stone. Later ore in `DEEP_ORES` (gold; redstone and lapis belong to Slice 6) is a new row.
- **Saving:** v36; `diamond_found` on a level map. Levels already generated in an old save keep their layout, with no diamonds.
