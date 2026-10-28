# Slice 5 Spec — Nether Foothold

Companion to `block-village-design-brief.md` and the Slice 1–4 specs. Slice 5 builds on everything in Slices 1–4 (and 3.5); this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table at the end. Issues not built yet carry their own rules on GitHub; each adds its section here when it's built.

Tracking issue: #14. Decisions settled with the owner (2026-10-21), and recorded in the brief (§5, §8, §13, §14):

| Question | Decision |
|---|---|
| Combat (#19) | **Visible auto-combat.** Creatures exist on Nether maps and residents fight on their own. The player controls the return policy and retreat, not each blow. No village combat. |
| Fighters | A new **Guard job**, levelled like the other jobs. **Iron swords and iron armor** from the bench; armor reduces injuries. Guards engage; everyone else avoids fights and keeps working. |
| Death and rescue (#20) | **No death.** A party that can't go on shelters and waits through a visible **rescue window**. A rescue mission brings it home. Missing the window costs cargo and gear, not lives. The PC stays protected. |
| Outposts (#26) | An **unstaffed shelter and supply cache** at the portal landing: a fallback and resupply point. Staffing stays open. |
| Portal | **Built from scratch at the village.** Deeper old-mine levels give diamonds (for a diamond pickaxe), gold and obsidian, which only a diamond pickaxe breaks. Flint and steel lights it. Nothing needed comes only from the Nether. |
| Maps | **A hub plus site maps.** A small portal-landing map, linked to the quartz site, the piglin camp and the fortress entrance by Nether route strips. Scouting reveals the routes. |
| Rail | **Portal → quartz site**, a Nether-side line reusing Slice 4's crew, stations and cart. The village line stays one point-to-point line. |
| Trading | **Gold from the deeper mine**, smelted into ingots. Piglins trade from a **fixed table shown before the party commits**, never random. They turn hostile only when a rule shown up front is broken. |
| Creatures | **Few, mostly in the fortress.** Zombified piglins (neutral) and magma cubes on the routes; blazes and skeletons in the fortress. |
| Fortress | **The entrance plus one short delve:** a small hand-laid section with blaze rods and rare salvage. Deeper comes later. |
| Expeditions at once (#25) | **Two:** one Overworld and one Nether. A rescue may set out even when both slots are taken. |
| Terminology (#30) | **Minecraft names for now** (Nether, piglin, blaze, quartz) as working names. |

Still open: #19 (village combat), #20 (difficulty and permanent death), #26 (staffed outposts), #29 (custom redstone and wider railway management, now under Slice 6), #30 (final terminology), #22 (regrowth), #66 (night time).

## 1. Scope and done criteria

Slice 5 is done when, from a Slice 4 village, a player can:

- [ ] Bring back gold, diamonds and obsidian from the deep mine, and craft a diamond pickaxe and flint and steel.
- [ ] Build and light the portal at the village.
- [ ] Make the first crossing, survey the landing, build the shelter and stock the cache, and return.
- [ ] Equip guards with swords and armor, and watch them fight on their own.
- [ ] Scout the Nether routes and read each site's report.
- [ ] Gather quartz, and see the deposit's reserves fall.
- [ ] Trade gold with the piglins from a table shown before departure.
- [ ] Delve the fortress for blaze rods and decide at the discovery.
- [ ] See a party stranded, send a rescue inside the window, and bring everyone home.
- [ ] Lay and ride the Nether line, with quartz mining no faster.
- [ ] Run a Nether and an Overworld expedition at the same time.
- [ ] Understand every stall from its on-screen reason alone.

## 2. Build order

#145 two expeditions at once; #146 gold, diamonds and obsidian in the deep mine; #147 the portal; #148 the portal landing; #149 Nether hazards; #150 the Guard job; #151 auto-combat; #152 shelter and cache; #153 scouting; #154 mission types; #155 the quartz site; #156 piglin trading; #157 the fortress; #158 stranding and rescue; #159 the Nether line; #160 the bot and hand playtest.

## 3. Two expeditions at once (#145)

`sim.expeditions` holds two slots, `overworld` and `nether`; a plan's destination decides its slot (`Sim.slot_of_dest`: ids starting with "nether" are the Nether's). `sim.expedition` is the current slot's, the way `sim.m` is the current map's: the Overworld's at rest, switched by the tick to whichever party is being stepped (`use_slot`, `on_slot`, `each_expedition`). Residents step with their own party's slot (`slot_of`); each map ticks in its realm's slot.

- A taken slot refuses a plan: "An Overworld party is already out" or "A Nether party is already out". A plan with `rescue` set skips that check, so a rescue (#158) can set out when both slots are taken.
- A resident is in one party only: someone packing with a party or out with it can't join another ("Packing with a party", "Out with the party").
- A pending choice carries its `slot`, and answering it works that party.
- The Nether party's stuck reasons are named for it ("Nether party: ...").
- **Saving:** v37. The one expedition becomes the Overworld's slot and the Nether's is empty; a waiting choice belongs to the Overworld's.
- Not yet: the Nether row on the expedition board and its planner come with the landing (#148).

## 4. Gold, obsidian and flint in the deeper mine (#146)

The portal needs nothing found only in the Nether (brief §8), so its materials come from the old mine's deeper levels. They're placed last, from streams of their own (`MineLevels.DEEP_ORES`), so the rest of every level is as it was; a level already made in an older save keeps its layout.

| Material | From | Where | Needs |
|---|---|---|---|
| Gold ore | Level 2 | Rock beside the floor, in plain sight | Any pickaxe. Smelted at the fireplace with coal into a gold ingot, for the piglins (#156). |
| Gravel | Level 3 | Rock beside the floor | Any pickaxe. Each block drops a flint about half the time, else nothing. |
| Obsidian | Level 5 | Rock beside the floor, with a **lava pool** sunk in the rock behind it where there's room | A **diamond pickaxe**. |
| Diamonds | Level 4 (#186) | Hidden until someone mines beside them | An iron pickaxe or better. Three diamonds and two sticks make a diamond pickaxe. |

A wide level has little rock beside its floor, so it can hold fewer blocks than the table's count.

- **Lava** cells are rock nobody walks into and nobody mines. They glow in the view. Burning is the hazard issue's (#149).
- **Flint and steel:** a flint and an iron ingot at the bench. One to a cell, with `FLINT_STEEL_USES` uses; the portal (#147) wears it.
- **Pickaxe tiers by ore** are data (`Tuning.ORE_PICK_TIER`): diamonds 3, obsidian 4. A party without the pickaxe is told: "Obsidian: needs a diamond pickaxe", and doesn't mark that ore.
- **The planner and the report:** a level lists the gold, obsidian and flint it holds once someone has seen it, as cargo targets. The tally bar groups the new items with the other ores.
- **Saving:** v38. A level map keeps its `lava` cells; nothing else changes shape.

## 5. Tuning table (provisional)

Each build issue adds its rows.

| Name | Value | Meaning |
|---|---|---|
| `ORE_YIELD` gold | 2 | Gold ore dropped by a gold ore block. |
| `ORE_YIELD` obsidian | 1 | Obsidian dropped by an obsidian block. |
| `GRAVEL_FLINT_CHANCE` | 50% | Chance a broken gravel block drops a flint. |
| `ORE_PICK_TIER` | diamond 3, obsidian 4 | The pickaxe tier an ore needs. |
| `FLINT_STEEL_USES` | 8 | Times a flint and steel lights something. |
| Gold ore, gravel, obsidian | levels 2, 3, 5 | First level of each, with 2 / 2 / 4 blocks, more further down. |
