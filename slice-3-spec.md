# Slice 3 Spec — The First Expedition

Companion to `block-village-design-brief.md`, `slice-1-spec.md` and `slice-2-spec.md`. Slice 3 builds on everything in Slices 1 and 2; this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table (§7).

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

**Light.** Torches on the walls light the tunnels near them. Floor further than the torch light (§7) from every torch is **dark**, drawn darker so the dark tunnels read at a glance. Darkness is a hazard (#110).

**The hidden vein** stands as plain rock wall until it's discovered (#111): it can't be marked, mined or walked through, and the site report doesn't show it.

**Depletion.** Ore and boulders don't come back once mined, and the site report's estimates go down as they're mined. Tree regrowth stays open (#22).

**The site report** (brief §8), shown on the expedition board (#105) before departure:
- **Before anyone has been there:** what the village has been told ("An old mine a short walk east. Stone and coal, they say."), the travel time, and stone and coal with no estimates. No hazards or access notes are known yet.
- **Once visited:** estimated reserves for stone and coal, and iron as **"?"**; the known hazards ("Dark tunnels past the torches"); and access notes ("Narrow tunnels: 1 resident per tunnel").
- **Once the iron is discovered:** iron and its estimated reserve.

## 4. Coal, iron ore and iron ingots (#103)

| Item | From | Used for |
|---|---|---|
| Coal | Coal ore blocks | Smelting fuel (#104) |
| Iron ore | The iron vein, once it's discovered | Smelting into ingots (#104) |
| Iron ingot | Smelting at the fireplace (#104) | Iron tools (#104) |

Each has its own colour, distinct from cobblestone and logs, an icon for the Craft panel, and a tally in the Materials group once it first turns up. Ingots are stacked as crossing layers of bars. Hauling and stockpiling treat them like any other item. On a site map, they're packed as cargo instead (#109).

## 5. Still to build

These issues carry their own rules until they're built; each one adds its section here.

- #104 Smelting at the fireplace and iron tools.
- #105 The expedition board.
- #106 Planning: party, provisions, cargo and return policy.
- #107 Staging and departure.
- #108 Travel to and from the old mine.
- #109 The party works the site.
- #110 Hazards and injuries.
- #111 The iron discovery.
- #112 Return and unloading.
- #113 The Slice 3 bot playtest and hand playtest.

## 6. Controls

| Action | Default key |
|---|---|
| Switch between the village and a site | Tab |

## 7. Tuning table (provisional)

| Name | Value | Meaning |
|---|---|---|
| Old mine size | 16×16 | Cells (its layout is hand-laid in `game/sim/old_mine.gd`). |
| `MINE_TRIP` | 60 s | Walking time between the village and the old mine, each way (#108). |
| `ORE_YIELD` coal | 2 | Coal dropped by a coal ore block. |
| `ORE_YIELD` iron | 2 | Iron ore dropped by an iron ore block. |
| `TORCH_LIGHT` | 3 cells | How far a torch lights; open floor beyond every torch's light is dark. |
