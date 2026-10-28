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

## 5. The portal (#147)

A **Nether portal** is a village building, 4×1, of an obsidian frame (`PORTAL_OBSIDIAN`, 10). The Build menu lists it once obsidian has come home from the deep mine (`stats.obsidian_home`) or a portal stands. It never turns, and it reserves a 6×3 **portal hall** plot, whose two rows in front of the frame are the **staging area** where Nether parties pack and gather (`Sim.staging_cells`, the same cells as an expedition board's; #148 sends the Nether slot's party there).

- **Building:** staged like any building. Residents with Build on carry obsidian from the stockpile, and build once it's all there. Short of obsidian the stuck list says "Portal frame needs 6 more obsidian".
- **Lighting:** a finished frame is dark until a resident carries flint and steel to it (`PORTAL_LIGHT_TIME`, 4 s). They fetch it from the stockpile, strike it, and set it back with a use fewer, or it's spent at none. A finished, unlit frame counts as Build work, so "No one is a builder" shows if no one builds. With no flint and steel, the stuck list says "Portal: Needs flint and steel to light".
- **Seen:** an obsidian frame with violet specks; once lit, a violet plane pulses in it.
- **Saving:** v39. The portal is an ordinary site with a `lit` flag.

## 6. The portal landing (#148)

A small Nether map, `nether_landing` (24×24), shown in the map switcher as **Nether: portal landing** once the portal has been lit. It is the hub: route strips (#153) will leave from its edges. A map's id starting with "nether" puts its parties in the Nether slot.

- **Look:** red netherrack, nearly black rock, lava pools sunk in the rock (rock nobody walks into), a ruined pillar at each of three landmarks, and the obsidian arch on the west edge with a violet glow. Its blocks are graded warm and dark (`Palette.NETHER_GRADE`), with the mine's stronger texture.
- **Planning:** the board's Location dropdown lists the landing once it's known. A Nether plan goes in the Nether slot, is **to survey the landing** (a plan with `target.item == "survey"`, no cargo list and no pickaxes), and needs the portal built and lit ("Build the portal first", "The portal isn't lit"). The planner shows the realm of the chosen destination (`game.plan_slot()`), so a Nether and an Overworld party can be planned, packed and sent in turn.
- **Packing and crossing:** the party packs at the **portal's staging area**, not the board (`expedition.board` is the portal). At Depart they walk to the cell in front of the portal and step through (`_cross_portal`): moving between maps happens only there. They arrive on the landing's west edge, which makes it known and visited.
- **The first crossing:** the party walks to each landmark (`mark_seen`); when all three are seen the landing is **surveyed** and the return policy brings them home through the portal. The objective shows in the expedition panel. The shelter (#152) comes later.
- **Relighting:** the portal can go out while a party is through it (`PORTAL_GUTTER_CHANCE`, as the party starts home). A Nether party carries a flint and steel from the village if there is one (`expedition.lighter`); it relights the portal on the way back, using a use, and the flint and steel comes home with them. Without one the party waits at the dark portal ("The portal has gone out and no one has flint and steel") until the village lights it again. Stranding and rescue are #158's.
- **Saving:** v40. The landing is added to a save when it loads, unknown. A parties' `lighter` and the landing's `landmarks_seen` and `surveyed` are saved.

## 7. Nether hazards: fire, lava and falls (#149)

Hazards go through the same system as Slice 3's (`_hazard`, `injure`): an injury is slower walking and work with no mining, a serious one stops the game for the retreat, armor turns some aside, and the PC is never seriously hurt. The hazards are cells of the map, so they work on any map that has them: the landing's, and the deep mine's lava.

| Hazard | Where | What happens |
|---|---|---|
| **Lava** | Cells of rock that are lava pools. Nobody walks into them or mines them. | Stepping onto a cell beside one risks a burn (`LAVA_CHANCE`, serious `LAVA_SERIOUS`). |
| **Fire** | Patches of burning netherrack (`SimMap.fire`), walkable. | Stepping onto one sets someone alight: they step off at once, burn for `FIRE_BURN_TIME` more seconds, and each second risks a burn (`FIRE_CHANCE`, serious `FIRE_SERIOUS`). Standing clear of fire stops it. |
| **Falls** | Ledges (`SimMap.ledges`). On the Nether's maps they need no dark. | Stepping onto one risks a fall (`FALL_CHANCE`, serious `FALL_SERIOUS`). |

- **Paths** go round: a step onto a cell beside lava or on fire costs `HEAT_STEP_COST` against 100, so the weighted path search (the one worn paths use) takes a longer way when there is one. It still goes through when there's no other.
- **Injuries** remember their cause (`hurt_cause`), so the stuck list says "Ada: Burned: can't mine, and works slower" (or "Seriously burned: waiting at the entrance"). The shelter's own rest, "resting at the shelter", comes with #152.
- **Site reports** list a map's known hazards once someone has been there: for the landing, lava, fire and ledges; for a deep mine level with lava pools, the lava.
- **Saving:** `fire` is a map field, saved with the map (the v40 format).

## 8. The Guard, iron swords and iron armor (#150)

- **Guard job:** a tenth job, `guard`, levelled like the others (experience from practice, five levels), with the Jobs board's on/off and priority. It needs **no workstation**. A guard hauls in the village; the work of the job is fighting on expeditions (#151). Ada does everything, so she fights too, though she's never seriously hurt. A higher level means quicker, more accurate blows (`HIT_TIME`, `HIT_CHANCE`). No traveler arrives skilled as a Guard (`Defs.SKILL_POOL`): they're made from the Jobs board.
- **Iron sword:** a tool of kind `sword` (tier 3, `SWORD_USES`): 2 iron ingots and a stick at the bench. A guard with none takes one lying about and keeps it, like a tool. A blow with it does `SWORD_DAMAGE` against `BARE_DAMAGE`. It wears with every blow.
- **Iron chestplate:** the only piece in Slice 5: 8 iron ingots at the bench, worn in the chest slot. It turns aside `IRON_GUARD` of injuries (a leather tunic: 15%) and wears out after `IRON_ARMOR_USES` blows taken. Armor already lowers hazard injuries; fights use the same rule (#151).
- **Toolsmith:** with a toolsmith, a guard's sword gets a spare when iron and a stick are on hand, like a spare pickaxe.
- **Planner:** a guard going with no sword to hand shows "No sword for Bram". It warns; it doesn't stop the plan. Guards carry their sword and armor with them; spare swords in the packs are not built yet.
- **Saving:** v41. Every resident has a `sword` slot and Guard at no experience.

## 9. Tuning table (provisional)

Each build issue adds its rows.

| Name | Value | Meaning |
|---|---|---|
| `ORE_YIELD` gold | 2 | Gold ore dropped by a gold ore block. |
| `ORE_YIELD` obsidian | 1 | Obsidian dropped by an obsidian block. |
| `GRAVEL_FLINT_CHANCE` | 50% | Chance a broken gravel block drops a flint. |
| `ORE_PICK_TIER` | diamond 3, obsidian 4 | The pickaxe tier an ore needs. |
| `FLINT_STEEL_USES` | 8 | Times a flint and steel lights something. |
| Gold ore, gravel, obsidian | levels 2, 3, 5 | First level of each, with 2 / 2 / 4 blocks, more further down. |
| `PORTAL_OBSIDIAN` | 10 | Obsidian in the portal's frame. |
| `PORTAL_LIGHT_TIME` | 4 s | Lighting a finished portal. |
| Landing size | 24×24 | Cells (hand-laid in `game/sim/nether_landing.gd`). |
| `PORTAL_GUTTER_CHANCE` | 20% | Chance the portal goes out as a party starts home. |
| `LAVA_CHANCE` | 4% | A burn each time someone steps beside lava. |
| `LAVA_SERIOUS` | 25% | A lava burn is serious. |
| `FIRE_BURN_TIME` | 2 s | Burning goes on this long after leaving a fire. |
| `FIRE_CHANCE` | 40% | A burn each second someone is alight. |
| `FIRE_SERIOUS` | 20% | A fire burn is serious. |
| `HEAT_STEP_COST` | 250 | Path cost of a step beside lava or on fire (open ground is 100). |
| `SWORD_USES` | 40 | Blows an iron sword lands before it breaks. |
| `IRON_ARMOR_USES` | 20 | Blows an iron chestplate takes before it wears out. |
| `IRON_GUARD` | 35% | Share of injuries an iron chestplate turns aside. |
| `BARE_DAMAGE` / `SWORD_DAMAGE` | 1 / 4 | A blow without and with a sword. |
| `HIT_TIME` | 1.2 s | Between a guard's blows at Guard level 1. |
| `HIT_CHANCE` | 60% | A blow lands at Guard level 1, 8% more a level. |
