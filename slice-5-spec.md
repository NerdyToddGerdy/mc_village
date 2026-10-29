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

## 9. Visible auto-combat (#151)

Creatures live on a Nether map (`SimMap.creatures`, each with health) and never leave it: a creature is data of one map, and only residents cross the portal. There's no village combat. Fights are decided by the sim's seeded random numbers, so a game replays the same.

| Creature | Health | Where | Behaviour | Drops |
|---|---|---|---|---|
| Magma cube | 8 | Routes | Hostile: notices someone within 5 cells, closes in, strikes next to them. | Magma cream |
| Zombified piglin | 10 | Routes | Neutral: only fights back once it's been hit. | A gold ingot |
| Skeleton | 6 | Fortress | Hostile, ranged (strikes from 4 cells). | A bone |
| Blaze | 10 | Fortress | Hostile, ranged (strikes from 5 cells), notices from 7. | A blaze rod |

The landing is a hub with none; the route and fortress maps (#153, #157) place them.

- **A creature's blow** is a hazard roll (`_hazard`): armor wears and turns some aside, an injury is slower walking and work, and a **knock-down** is a serious injury, which stops the game for the retreat as any serious injury does. There's no death. Ada is never seriously hurt.
- **Guards** (and Ada) go for a creature that's after the party, wherever it is; or one within `SELF_DEFENSE_RANGE` of anyone. A blow lands by chance (`HIT_CHANCE`, 8% more a level), takes `HIT_TIME` (quicker the higher the level), does `SWORD_DAMAGE` with a sword and `BARE_DAMAGE` without, and wears the sword. A creature brought down gives the guard a point of Guard practice.
- **Everyone else** moves away from a dangerous creature within `AVOID_RANGE`, and goes back to work.
- **Return policy:** a plan's `fight` is false by default: the party **avoids combat except in self-defense**, so guards don't go looking for a neutral piglin. With `fight` set, guards go after any creature within `ENGAGE_RANGE`.
- **Drops** lie where the creature fell, and join the level's cargo list once seen (the landing's report lists them), so the party packs them like any find.
- **Seen:** each creature has a model; it swells for a moment on a blow either way. The stuck list says "Nether party: fighting" while a guard fights or someone moves away.
- **Saving:** v42. A map keeps its `creatures` and `drops_known`; an older trip avoids combat.

## 10. The shelter and supply cache (#152)

An **unstaffed** shelter on the landing: nobody lives there, and staffing stays open (#26).

- **The blueprint** goes down at `NetherLanding.SHELTER_AT` the first time a party crosses. It isn't a village building. A first-crossing plan carries its materials, `SHELTER_COST` (4 cobblestone, 6 planks), as **supplies** packed at the portal with the meals (`Sim.SUPPLY_KINDS` now covers cobblestone and planks as well as the pens' wheat and sticks; they take room in the packs like any item).
- **Building:** once the party holds all of it, one member builds the shelter in `SHELTER_BUILD_TIME` and the supplies are used up. The first crossing's objective is now **survey the landing and build the shelter**: the party comes home once both are done. A later plan carries no materials.
- **The cache** is the shelter's store. A plan can set aside **meals for the cache** (`stock`, from the meals taken, past the walk home); the party leaves them there. A later party that has run down its own food takes a meal from the cache and eats it, staying on instead of heading home, and the cache counts toward what a party can still spend.
- **Fallback:** an injured resident at the landing rests in the shelter, at the slow rate of a resident with no bed (`HEAL_NO_BED`): "Ada: Burned, resting at the shelter". Stranded parties shelter there (#158).
- **The site report** shows "Shelter built. Cache: 2 meals" (or empty). Stuck reasons: "Shelter: needs 2 more planks", "Cache: empty".
- **Saving:** v43. The landing's sites may hold the shelter, with its cache in the site's store; a trip carries `shelter`, `cobble`, `planks` and `stock`, none for an older trip.

## 11. Scouting and the Nether routes (#153)

Three **route strips** leave gaps in the landing's edge wall (`NetherRoute.ROUTES`): east to the **quartz site**, north to the **piglin camp**, south to the **fortress entrance**. Each is a 48×7 map of kind `route` that shares the road's geometry (six segments of eight columns, the line along row 3), so the road's fog hides what nobody has walked. Beyond each is a small stub map for its site, to be filled in by #155–#157.

| Route | Terrain, west to east | Creatures |
|---|---|---|
| Quartz | The landing's edge, netherrack flats, a **lava channel**, scorched flats (fire), a **broken ledge**, below the quartz | A zombified piglin, a magma cube |
| Piglin | The landing's edge, a **lava pool**, open flats, a **ruined bridge** (a drop), netherrack hills, the camp's approach | A magma cube, a zombified piglin |
| Fortress | The landing's edge, open flats, **basalt cliffs** (a cut), ash flats, a **lava lake** (fire), the fortress wall | Two magma cubes |

The obstacles that need a bridge (lava, gaps) or a cut are named in each segment's data, for the line (#159) to deal with. A scout passes by a narrow way beside the lava, with the burns and falls of #149 and the creatures of #151.

- **Scouting:** a plan with `target = {item: "scout", route}` (`Sim.scout_plan`). The party crosses to the landing, walks to the route's gap, steps onto the strip and walks east segment by segment: each segment reached is **revealed** (`SimMap.seen`), with its terrain, obstacle and dangers. At the far end the route is **scouted** (`surveyed`) and the site beyond it is **known**; the party then heads home by the same way. A seriously hurt scout turns back. Guards deal with creatures on the way.
- **Unknown routes** show as grey posts at the landing's edge, yellow when part-scouted, blue when scouted. Each route that's been entered appears in the map switcher, and so does its site once it's known.
- **Reports** (`site_report`): for a route, every segment as far as it's been seen, its dangers (including the creatures about in scouted segments), and the travel time once scouted; the landing's report lists the three routes' states. A site's report waits for the issues that build it.
- **Gating:** an unscouted site can't be a destination ("Nobody has scouted the way there yet"), and a scouted route can't be scouted again. A party can't be sent to a scouted site until it's built ("The way to the quartz site isn't built yet", #155–#157).
- **Saving:** v44. The routes and sites are added to a save when it loads, unknown. A route keeps `seen` and `surveyed`.

## 12. Mission types at the expedition board (#154)

A Nether plan has an **objective**, picked in the planner (`Sim.OBJECTIVES`): **Survey** (the first crossing, until the landing is surveyed and the shelter built), **Scout**, **Gather**, **Trade**, **Build**, **Fortress** and **Rescue**. The destination list shows only the places an objective can use now (`Sim.objective_destinations`), and an objective with none is greyed out with its reason (`objective_why_none`).

| Objective | Destinations | Defaults | Comes home when |
|---|---|---|---|
| Survey | The landing, until surveyed | The shelter's materials | the landing is surveyed and the shelter built |
| Scout | Each unscouted route (the party picks one) | No cargo, avoids combat | the route is scouted |
| Gather | The quartz site, once its route is scouted | A cargo list (its items come with #155) | the cargo target is reached |
| Trade | The piglin camp, once scouted | The trade table, shown before they commit (#156) | the trades are made |
| Build | The landing, while the shelter isn't built | The shelter's materials | the building is done |
| Fortress | The fortress entrance, once scouted | Avoids combat | the delve is done, or the party is hurt |
| Rescue | A stranded party (#158) | May set out with both slots taken | the stranded party is reached |

- **Explained before commitment:** `Sim.plan_briefing` lists what's known of the dangers where the party is going, the creatures about, the risk of a dark portal with no flint and steel to carry, and a party that can't fight, and says when they come home. The planner shows it under the objective, in yellow for the risks.
- **Overworld plans** keep their form: a gather at the old mine or the meadow, with no objective.
- **A plan with no valid destination** isn't offered: its button is disabled, and `nether_plan` returns nothing. Sites a party can't reach yet refuse at Depart ("The way to the quartz site isn't built yet"), until #155–#157 build them.
- **Saving:** a plan's `objective` is saved with a trip in progress; nothing else changes shape, so no new version.

## 13. The quartz site (#155)

The scouted quartz route now leads to a hand-laid **quartz site** (`NetherRoute.QUARTZ_LAYOUT`, 20×14): eight blocks of **nether quartz ore** and five of **glowstone** among rock, with a lava pool. Quartz needs a pickaxe; **glowstone breaks by hand** (`GLOWSTONE_TIME`) and needs none. Both are ores, a quartz block yields 2 and a glowstone block 2 (`ORE_YIELD`). They're stockpiled for Slice 6's redstone and workshops; nothing in the village needs them to survive. The site keeps the far side clear (`QUARTZ_STATION_PLOT`) for the Nether line's station (#159).

- **Getting there** is a journey across the Nether, now general (`_nether_transit_job`): through the portal onto the landing, out by the route's gap, east along the strip, onto the site; home the same way. Every step is walked, so lava, fire, ledges and creatures on the way apply (#149, #151). An older save's empty room at the end of the quartz route becomes the site on loading.
- **The gather mission** works like the old mine's (#109): the party mines from its packs by its cargo list (the site's quartz and glowstone, best first), packs what it mines, eats from its provisions and comes home by its return policy. A gather plan wants 8 quartz and a spare pickaxe by default.
- **Depletion:** the site report lists each find's reserve (blocks left times the yield) once someone's been there, and it runs down as the party mines. Deposits don't come back (#22).
- **Saving:** v45. The mined-out blocks and `visited` are saved with the map.

## 14. Piglin trading (#156)

The scouted piglin route leads to a hand-laid **piglin camp** (`NetherRoute.PIGLIN_LAYOUT`, 20×14) with three piglins standing about. A **piglin** is a creature that never goes for anyone (`notice` 0) and only fights back once it's been hit.

- **The trade table** is fixed, shown before a party commits, and never rolls (`Defs.TRADES`): 2 gold ingots for 1 obsidian; 2 gold ingots for 3 string; 1 gold ingot for 2 flint; 4 gold ingots for 1 fire-resistance supply. A trading party works down it in that order, taking the first row its gold pays for, and trading until it can pay for none. It's in the site report (`trades`) and the planner's briefing, which also shows the rule.
- **The rule**, shown up front: **"Piglins turn hostile if anyone in the party strikes one."** Breaking it turns the whole camp hostile (`SimMap.hostile`): the piglins go for the party, auto-combat applies (#151), no more trading is done there, the report lists "The piglins are hostile", and the party heads home. A trade plan never sets the party to fight, so a guard doesn't attack a peaceful piglin.
- **The mission** (objective **Trade**): the party carries **gold ingots** from the village as supplies (the planner's "Gold to trade", up to 6 by default, as much as the village has), which take room in the packs like any item. At the camp one member walks up to a piglin and makes every trade the gold pays for; the goods go into the packs (as long as they fit) and come home as cargo. It returns when the trades are made.
- **The report** says what was traded: "Traded: 2 gold ingots for 1 obsidian ×3".
- **Saving:** v46. A camp keeps `hostile`, and its piglins their health. An older save's empty room becomes the camp when it loads.

## 15. The fortress entrance and the first delve (#157)

The scouted fortress route leads to a hand-laid **fortress** (`NetherRoute.FORTRESS_LAYOUT`, 24×16): nether brick halls with two **blazes** and two **skeletons**, a **salvage chest** at the far end, and a **sealed way deeper** beside it. Going deeper waits for a later slice; the sealed way is marked as a future objective in the report and is not opened.

- **The mission** (objective **Fortress**): a party walks the halls to the chest. The planner warns without a guard ("No guard in the party: a fortress has blazes and skeletons"). Blazes and skeletons are hostile and come for the party; guards fight them (#151), and a knock-down stops the game for the retreat as always. Blaze rods and bones drop where creatures fall and are packed like any find; the plan's list names both.
- **The discovery pause** fires once, when the party reaches the chest: take the salvage and **return**, or take it and **press on** (the guards go after what's left, for more rods, and the party returns once the halls are clear). The text names the salvage (`Defs.FORTRESS_SALVAGE`, provisional: a diamond, 4 iron ingots, 3 gold ingots and a blaze rod) and the sealed way.
- **The salvage is taken once** (`SimMap.salvage_taken`); what doesn't fit in the packs is left on the chest's cell. A later delve finds it empty, and the report says so. The creatures killed stay dead.
- **Saving:** v47. The fortress keeps its creatures, `salvage_taken` and what they've dropped. An older save's empty room becomes the fortress when it loads.

## 16. Stranding and rescue (#158)

**No death.** A Nether party that can't go on is **stranded**, and a rescue can bring it home inside a window.

- **Stranded** (`_check_stranded`, from `STRAND_WAIT` and the party's state): its provisions are gone and someone's hungry (the cache counts), or everyone is seriously hurt, or the portal is dark with no flint and steel and the party has waited `STRAND_WAIT` at it. The party shelters in the shelter if it's on the landing and one stands, else where it stands, and stops working. **The game pauses** with the costs shown: the window (`RESCUE_WINDOW`, 240 s), the cargo it would leave, and two choices: **Shelter and wait**, or **Set out on their own** now.
- **The window** is a visible countdown in the expedition panel, with the party's remaining supplies ("Stranded: the provisions are gone. Rescue window 3:52. Supplies: 0 meals, no flint and steel."), and "Nether party: stranded" in the stuck list. The panel's **Plan a rescue** button opens the plan.
- **A rescue** is a plan with the **Rescue** objective: a **third slot**, `rescue`, a Nether expedition of its own that sets out even when the Overworld and Nether parties are both out. It's planned at the board and packs at the portal like any Nether party (6 meals by default; flint and steel is carried automatically). Its destination is the place the stranded party is; it walks there like any Nether party and **reaches** them: the stranded party gets the meals past the rescue's own walk home, and a flint and steel if it had none, and everyone heads home, the stranded party **with its cargo**. Only one rescue at a time.
- **A missed window** (or the choice to walk): the party sets off on its own, **slowly and hurt** (an ordinary injury; the PC is protected as ever), and leaves its **cargo and spare tools** where it stood as **abandoned cargo**, lying on that map (`SimMap.abandoned`), which a later mission recovers like any find (a site lists the types in its report). The report says "Left behind: ...". Nobody dies.
- **Saving:** v48. A trip carries `stranded` (why, where, the window's end) and what it `abandoned`; there's a third, empty `rescue` slot in every older save.

## 17. The Nether line: portal station to the quartz site (#159)

A line along the scouted **quartz route**, built by **Build parties** from what they carry, in the spirit of Slice 4's: bridges, track, a station at each end and a cart. The village line stays a single point-to-point line (#29). It is not built the way Slice 4's is (a crew of residents on a map of their own, with the rail pile and track sites): the Nether has no village labor to spare, so each trip is a Build expedition that lays what its packs hold.

- **State** (`SimMap.line` on the quartz route): the rails laid in each of its six segments, the bridged segments, the two stations (`landing` and `site`) and whether the cart is parked. `Sim.nline_remaining()` is the cost left: 12 rails (`RAILS_PER_SEGMENT`, 2 a segment), two **bridges** over the lava channel and the gap (`NETHER_BRIDGE_PLANKS`, 8 planks each), two **stations** (Slice 4's station cost: 6 planks and 4 cobblestone each), and a **minecart**, built at the village and carried through the portal.
- **The mission:** the **Build** objective offers "The Nether line to the quartz site" once the route is scouted. The plan carries what's left, most urgent first (bridges' planks, rails, the stations' planks and cobblestone, the cart), up to what a party of three can carry past its meals; the planner's steppers adjust it. The briefing shows what's still to build and the time the line saves. The crew packs at the portal, crosses, **builds the landing station** before setting out, **bridges** and **lays track** west to east on the route as far as its supplies go (a bridge first, since track can't go down over an obstacle), then builds the **station at the quartz site** and **parks the cart** there, and comes home when nothing is left it can do. A big line takes more than one trip. A party member who finds a piece already claimed, or done, takes the next. A bridge's missing planks show in the stuck list: "Track: needs the lava channel bridged first".
- **Away from village labor:** the crew is a Nether party; the Jobs panel says "In the Nether: laying track".
- **Riding:** once the line is complete every party on the quartz route rides it at the cart's speed (`CART_SPEED`) both ways: about 10 s saved each way on a 16 s walk. Mining at the site is unchanged (a test guards it). **Riders are safe from wandering creatures and from the lava's burns while they move**; a party that walks isn't.
- **Seen:** planks over the bridged segments, sleepers and rails as far as they're laid, the stations and the parked cart; the route's report says "Line: 4 of 6 segments laid, 1 of 2 bridges...".
- **Saving:** v49. The quartz route map keeps its `line`; a trip carries `rails` and `minecarts` in its supplies.

## 18. Tuning table (provisional)

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
| `CREATURE_SPEED` | 1.4 cells/s | How fast a creature closes in. |
| `AVOID_RANGE` | 3 | How close a hostile creature gets before a non-guard moves away. |
| `SELF_DEFENSE_RANGE` | 2 | How close a creature must be for a guard to fight it when the party avoids combat. |
| `ENGAGE_RANGE` | 8 | How far a guard goes after a creature when the party doesn't avoid combat. |
| Creature table | see §9 | Health, hit chance, serious chance, blow time, reach, notice range and drops, in `Defs.CREATURES`. |
| `SHELTER_COST` | 4 cobblestone, 6 planks | What a party carries to build the shelter. |
| `SHELTER_BUILD_TIME` | 10 s | Building it. |
| Route strip | 48×7, six segments | Cells, in `game/sim/nether_route.gd`. |
| `ORE_YIELD` quartz / glowstone | 2 / 2 | Items a block drops. |
| `GLOWSTONE_TIME` | 3 s | Breaking glowstone, by hand or with any tool. |
| Quartz site | 20×14 | Cells, 8 quartz and 5 glowstone. |
| Trade table | see §14 | `Defs.TRADES`: gold ingots for obsidian, string, flint and fire resistance. |
| Piglin camp | 20×14 | Cells, with three piglins (12 health each). |
| `FORTRESS_SALVAGE` | 1 diamond, 4 iron, 3 gold, 1 blaze rod | The chest's contents. |
| Fortress | 24×16 | Cells, with two blazes and two skeletons. |
| `RESCUE_WINDOW` | 240 s | How long a stranded party shelters before it sets off on its own. |
| `STRAND_WAIT` | 20 s | A party at a dark portal with no flint and steel waits this long before it's stranded. |
| `NETHER_BRIDGE_PLANKS` | 8 | Planks in a bridge over the lava channel or the gap. |
| `NETHER_BRIDGE_TIME` | 10 s | Building one. |
| Nether line | 12 rails, 2 bridges, 2 stations, 1 cart | What the quartz route's line takes, with Slice 4's `RAILS_PER_SEGMENT`, station cost and `CART_SPEED`. |
