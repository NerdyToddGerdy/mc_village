# Slice 3 Spec — The First Expedition

Companion to `block-village-design-brief.md`, `slice-1-spec.md` and `slice-2-spec.md`. Slice 3 builds on everything in Slices 1 and 2; this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table (§11).

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

**Paint and Build are for the village.** On a site map, the toolbar shows only Gather and Craft. Stockpiles, farms and buildings can't go on a site; an expedition packs what it gathers instead (#109).

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
- **5 boulders** (cobblestone) and **6 coal ore** blocks;
- an **iron vein** of 4 blocks, hidden behind rubble at the end of the deepest tunnel.

**Mining** works as in the village: the Mine and Break orders mark boulders and ore, and residents with a pickaxe break them. Ore blocks drop their ore (§4).

**Light.** Torches on the walls light the tunnels near them. Floor further than the torch light (§11) from every torch is **dark**, drawn darker so the dark tunnels read at a glance. Darkness is a hazard (#110).

**The hidden vein** stands as plain rock wall until it's discovered (#111): it can't be marked, mined or walked through, and the site report doesn't show it.

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

Each has its own colour, distinct from cobblestone and logs, an icon for the Craft panel, and a tally in the Materials group once it first turns up. Ingots are stacked as crossing layers of bars. Hauling and stockpiling treat them like any other item. On a site map, they're packed as cargo instead (#109).

## 5. Smelting and iron tools (#104)

**Smelting.** The fireplace gains **Smelt iron**: 1 iron ore and 1 coal make 1 iron ingot, in `SMELT_TIME`. Coal goes in the furnace's fuel slot. It's Cook work, like everything at the fireplace, and it's queued by hand: the standing order only makes meals.

**Iron tools** are made at the bench, the third tier after wood and stone:

| Recipe | Takes | Makes |
|---|---|---|
| Iron axe | 3 iron ingots, 2 sticks | 1 iron axe |
| Iron pickaxe | 3 iron ingots, 2 sticks | 1 iron pickaxe |

They last longer and work faster than stone (the tier rows in §11). Residents already prefer the best tool about, so an iron one is picked up over stone.

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
- **Return policy:** any of target reached, packs full, or food running low. A serious injury always brings the party home and stops the game for the player (#110).

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

**Depart** is the player's call (brief §10). The button is enabled once everything is packed and the whole party is at the board, and otherwise says what it's waiting for. From then on, party members are out of village labor: their jobs end, nobody can give them orders, and they don't get hungry on the road. The packed supplies go with them, and the board is empty again.

**On the road.** Each member is away for `MINE_TRIP`, and their panel says "On the road to the old mine, N s". The line under the tally bar says the same and switches to the old mine when clicked. When they get there, they appear at the site's entrance, the site counts as visited, and the first to arrive sets the supplies down there. (Until #108, #109 and #112, that's where a trip ends. Travel's signpost and the way home, packs on site, and the return are still to come.)

**Calling it off.** Before departure, **Call off the expedition** (a destructive button) unpacks everything. The supplies are set down by the board, loose, and hauled back to the stockpile, and the party goes back to work.

**Saving.** Save format **v16** saves the expedition (the plan, its state, and what was packed and carried), and each resident's `trip`. What's packed at the board is saved with the board, tools with their wear. Older saves have no expedition, and anyone away is at the meadow.

## 9. Still to build

These issues carry their own rules until they're built; each one adds its section here.

- #108 Travel to and from the old mine.
- #109 The party works the site.
- #110 Hazards and injuries.
- #111 The iron discovery.
- #112 Return and unloading.
- #113 The Slice 3 bot playtest and hand playtest.

## 10. Controls

| Action | Default key |
|---|---|
| Switch between the village and a site | Tab |
| Place an expedition board | None (rebindable). It's in the Build menu |

## 11. Tuning table (provisional)

| Name | Value | Meaning |
|---|---|---|
| Old mine size | 16×16 | Cells (its layout is hand-laid in `game/sim/old_mine.gd`). |
| `MINE_TRIP` | 60 s | Walking time between the village and the old mine, each way (#108). |
| `ORE_YIELD` coal | 2 | Coal dropped by a coal ore block. |
| `ORE_YIELD` iron | 2 | Iron ore dropped by an iron ore block. |
| `TORCH_LIGHT` | 3 cells | How far a torch lights; open floor beyond every torch's light is dark. |
| `SMELT_TIME` | 5 s | Smelting one iron ingot at the fireplace. |
| `CHOP_TIME` iron | 3.5 s | Felling a tree with an iron axe (stone 5 s). |
| `BREAK_TIME` iron | 4 s | Breaking a boulder or ore block with an iron pickaxe (stone 6 s). |
| `DURABILITY` iron | 60 uses | An iron tool's uses (stone 25). |
| Expedition board cost | 6 planks, 4 sticks | One stage. |
| `PARTY_MAX` | 3 | Residents in a party, at most. |
| `PACK_CAPACITY` | 10 | Items each party member carries, shared by supplies and cargo. |
| `RETURN_MEALS` | 1 | Meals per member kept for the walk home. |
| `MEAL_FOOD` | 50 | Food a meal counts as when estimating time at the site (bread's). |
