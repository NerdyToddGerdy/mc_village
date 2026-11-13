# Slice 7: structures as adventures

Slice 7 turns Minecraft-style structures into expedition destinations (#242, issues #243 to #271). It only describes what's new since Slice 6. The adventure registry (`Adventures.DEFS`, #242) and the Cartographer's surveys (#321) already exist; this slice fills them.

**Status of the decisions.** The choices below are **provisional**, made to get the first adventure built (the owner asked to start the slice). #242 listed them as open, and #30 (names and art) still is: names are working titles, and nothing here settles terminology.

## How an adventure is added

A mine-kind structure is **one entry in `Structures.DEFS`** (`structures.gd`) plus its Bring-back defaults in `Tuning.CARGO_DEFAULTS` (keyed by its id), and its id in `Structures.IDS`. Everything else reads that table:

1. **A site map**, hand-laid in ASCII like `old_mine.gd` (provisional: hand-laid one-offs read as places; templates like `mine_levels.gd` can come later for families such as caves). The party arrives at `E`.
2. **Its adventure entry** (`Adventures.def`): mine kind, the signpost (`west`, the meadow's strip, or `east`, the road to the mine), what it gives and its plan defaults, and what the village is `told` before anyone goes.
3. **Found by the Cartographer:** `Survey.FINDS` is the caves, the portal, then `Structures.IDS` in order. `Survey.reveal` makes its map and road known. A found place gets a pin on the world map.
4. **A site report:** the old mine's report without its levels, with the table's `told`, `access` and the ores it `gives`, and the walk time of its road.
5. **Tests:** `test_every_structure` checks each one is well-formed, every block can be dug to, and that it's found, listed, planned and reported; a full trip is tested for the desert well (the strip) and the jungle temple (the road to the mine). The map is added to a loaded save by `Sim._add_site_maps`, so no save step is needed.

## Boats (#407)

A **boatyard** (`Defs.TEMPLATES.boatyard`, a 1x1 station, unlocked by "coast") and a **sea road** (`sea_road.gd`, kind "walk", `Tuning.SEA_ROAD_LEN` cells, no trees so adding it moves no ids). A coastal structure that names `"road": SeaRoad.ID` is sailed to: `RoadWork`, `Travel.trip_time` and the view treat the sea road as they do the meadow's strip, and `Packing.plan_problems` asks for a boatyard (`Sim.boatyard()`). The older coastal places keep the meadow's strip. Old saves get the map on load: no save bump.

## The coast (#271)

Provisional decisions, made to build it (#271 listed them as open):
- **A sea on the south edge of every new game**, three rows deep across the whole edge. Old villages keep their land (`SimMap.coast` is `""` in them; save v70 says so). The edge can't be claimed, and nothing is built, farmed or stockpiled in water.
- **One dock**, from the beach out over the water (`Defs.TEMPLATES.dock`, `walk`). Built, it opens the water under it to walking. Its sea end is the signpost for coastal adventures (`"sign": "dock"`).
- **Coastal structures** (`"coast": true` in `Structures.DEFS`) are found only by surveying the coast's sectors (`Survey.COAST`), which needs a dock; land surveys never find them.
- **No boats yet.** The trip is the meadow's strip, a placeholder for a boat ride. Underwater diving and fishing are not built.

## The Nether fossil (#254)

Not a structure-table entry: the Nether's sites are routes, so it is a **fourth Nether route** (`NetherRoute.ROUTES.fossil`) with a hand-laid site at its end. It leaves the landing by a gap in the west wall (`Landing.LAYOUT` row 20; older saves' landings get it opened on load). Its ore, `fossil`, gives bone. The **Gather** objective lists every scouted site that gives something (quartz, fossil) rather than one fixed site.

## The bastion remnant (#264)

A **fifth Nether route** (`NetherRoute.ROUTES.bastion`), fight only, decided with the owner: no trade yet. Its site (`BASTION_LAYOUT`) holds five **piglin brutes** (`R`, species `piglin_brute`: 20 hp, always hostile, notice 6) and gold ore (`G`), chests (`K`). The landing's gap is at (0, 16). It joins the Gather objective. The piglin camp stays the only place that trades; if a trade system for bastions comes later, it builds on this site. Older saves add the maps on load.

## Structures with creatures (group B of #242)

A structure whose layout has `Z` (zombie), `S` (skeleton) or `X` (spider) puts that creature in the map, hunting anyone who comes in (`hunt`), and its entry says `fight`: the plan fights by default (`plan.fight`, which makes the party engage creatures in range), the planner warns when no Guard (or Ada) is going, and the site report lists what's inside. The Slice 5 auto-combat does the rest. Provisional: the creatures are the village's night mobs (zombie, skeleton, spider), standing in for pillagers and the rest until #30 settles names and art. The **abandoned mineshaft (#256)** is built as its own place (spiders, a ledge in the dark) even though the old caves are one too. The **stronghold** has a portal (#411): see below.

## Kinds

- **mine:** the party digs boulders and ores from its packs, with the mine's cave-ins and (where a map has them) ledges and darkness. Structures with loot and traps use it.
- **meadow, nether:** as before. Structures that need combat (group B in #242) wait for a kind that uses the Slice 5 guards.

## Roads

A structure uses an existing road until it needs its own: the meadow's strip (a plain walk, `walk_time()`) for places to the west. A shared strip means the walk time is the meadow's; per-place strips are a later change if the distance should differ.

## Built so far

| Adventure | Issue | Signpost | Gives | What can go wrong |
|---|---|---|---|---|
| Desert well | #247 | west | gold ore, stone, a chest's book | old stone comes down |
| Desert temple | #248 | west | gold ore, two chests behind stone | old stone comes down |
| Jungle temple | #249 | east | redstone, lapis, a chest's book (needs iron pickaxes) | trap rooms: old stone and ledges in the dark |
| Fossil site | #250 | west | coal, flint | old stone comes down |
| Trail ruins | #251 | west | flint, four chests' books | old stone comes down |
| Geode | #252 | east | lapis, gold ore (needs iron pickaxes) | old stone comes down |
| Dungeon | #255 | west | coal, two chests | 2 zombies and a skeleton hunt the party |
| Igloo cellar | #258 | east | flint, coal, two chests | a zombie |
| Swamp hut | #257 | west | coal, a chest | 2 spiders |
| Pillager outpost | #259 | east | gold ore, three chests | 3 skeletons |
| Trial chambers | #260 | west | gold, lapis, redstone, chests (iron pickaxes) | zombies, skeletons, a spider |
| Woodland mansion | #261 | east | gold, lapis, redstone, chests (iron pickaxes) | zombies, skeletons, a spider |
| Stronghold | #262 | east | gold ore, three chests | skeletons and zombies |
| Abandoned mineshaft | #256 | west | coal, flint, three chests | 3 spiders, loose stone and a ledge in the dark |
| Buried treasure | #244 | dock | gold ore, a chest's book | old stone comes down |
| Shipwreck | #245 | dock | gold ore, flint, two chests | old stone comes down |
| Ocean ruins | #246 | dock | lapis (needs iron pickaxes), gold ore, a chest | old stone comes down |

`Survey.FINDS` is an ordered list: each successful survey reveals the next place, so the order is the order places are found in. The two on the road to the mine take its longer walk.

## Another village (#253)

A `folk` entry in `Structures.DEFS` (`another_village`, found after the geode), friendly: four villagers (`V`, species `villager`, named, no hostility) and a little coal. The new `visits.gd` does the rest: a party member walks up to the nearest villager and **invites** them (`invite` job and op), up to `Tuning.INVITES_PER_VISIT` (1) per visit; on the party's return the names go into `stats.guests`, and `_arrive` takes the next guest by name, after `Tuning.GUEST_DELAY` instead of the usual delay, when a house has a free bed. **Provisional rules, decided by default, to be confirmed:** no trade and no currency (still open, with #264's trade); recruiting adds to the free-bed arrivals rather than replacing them (#24); the folk are finite. No save bump: `guests` is a key of `stats` and `invited` one of the expedition.

## Decisions on the remaining adventures

- **Ruined portal (#243):** a survey find that unlocks the village's own portal recipe; it is not an adventure map. Done.
- **Ocean monument (#265):** reached **by boat from the dock**. It needs a boat building at the dock and a sea-travel mode, then the monument as a coastal fight structure.
- **Ancient city (#266):** the bottom of the **deepest mine biome (#238)**, with quiet-and-dark rules. The Sift (#290) stays parked behind it.
- **The End (#289, #267, #268):** a late chapter. The stronghold gains a portal; the dragon platform is its own fight-only map (health persisting over trips, as decided); End city and End ship are structures on the islands, reached by the bridging stage.
- **Outposts (#286):** deferred until something needs one.

## The stronghold's portal (#411)

`Structures.DEFS.stronghold.portal` is the cell of a **portal frame** block (`ore` "end_portal", gives one `end_stone`), added by `Structures.add_portal` when the map is built and, for a save from before, on loading. It is **hidden until every creature in the stronghold is down** (`Structures.reveal_portal`, called from `Creatures._down`), then it is an ordinary block the plan can ask for (the stronghold's list has an "End stone" row). Mining it sets `stats.end_open`, which the End adventure (#412) reads. **Provisional:** there is no key item yet (an eye crafted from the Nether's blaze rod and quartz is the likely one); clearing the place is the clue. No save bump: the frame is added on load, `end_open` is a key of `stats`.

## The deep dark (#409)

`MineLevels.biome` gives **"sculk"** (shown as "Deep dark") from `MineLevels.SCULK_FROM` (level 9) down: no torches (`torch_count` is 0), the darkest rock, and the **quiet rule**: `Creatures.on_break` counts blocks broken on the level (`regrow.noise`, saved with the map) and each `Tuning.NOISE_PER_WAKE` wakes the sleeper nearest the sound (`angry`, which makes it come). Its sleepers are zombies (`CAVE_SPECIES.sculk`), standing in until #30. This is the biome the ancient city (#410) sits at the bottom of. No save bump: biomes follow the level number and the counter is in the existing `regrow`.

## The ancient city (#410)

`MineLevels.CITY_LEVEL` (11) is hand-laid (`CITY_LAYOUT`, family "city") instead of generated: level 10's door leads to it, it is in the deep-dark biome (so the quiet rule and no torches apply), and its `door_state` is **"sealed"**: no door down, so `dig_to_door` and the cleared-level step stop there. Sleepers are `Z` zombies placed by the layout. It is the place the Sift (#290, parked) would be reached from. No save bump: the map is built when the door above is opened, as every level is.

## Next

What's left of group A of #242 needs a trade system and currency (open). Then the structures that need combat (group B), then the late ones. The ruined portal (#243) is already a survey find that unlocks the village's own portal rather than an adventure map.
