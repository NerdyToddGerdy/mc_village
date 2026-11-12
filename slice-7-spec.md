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

## The coast (#271)

Provisional decisions, made to build it (#271 listed them as open):
- **A sea on the south edge of every new game**, three rows deep across the whole edge. Old villages keep their land (`SimMap.coast` is `""` in them; save v70 says so). The edge can't be claimed, and nothing is built, farmed or stockpiled in water.
- **One dock**, from the beach out over the water (`Defs.TEMPLATES.dock`, `walk`). Built, it opens the water under it to walking. Its sea end is the signpost for coastal adventures (`"sign": "dock"`).
- **Coastal structures** (`"coast": true` in `Structures.DEFS`) are found only by surveying the coast's sectors (`Survey.COAST`), which needs a dock; land surveys never find them.
- **No boats yet.** The trip is the meadow's strip, a placeholder for a boat ride. Underwater diving and fishing are not built.

## The Nether fossil (#254)

Not a structure-table entry: the Nether's sites are routes, so it is a **fourth Nether route** (`NetherRoute.ROUTES.fossil`) with a hand-laid site at its end. It leaves the landing by a gap in the west wall (`Landing.LAYOUT` row 20; older saves' landings get it opened on load). Its ore, `fossil`, gives bone. The **Gather** objective lists every scouted site that gives something (quartz, fossil) rather than one fixed site.

## Structures with creatures (group B of #242)

A structure whose layout has `Z` (zombie), `S` (skeleton) or `X` (spider) puts that creature in the map, hunting anyone who comes in (`hunt`), and its entry says `fight`: the plan fights by default (`plan.fight`, which makes the party engage creatures in range), the planner warns when no Guard (or Ada) is going, and the site report lists what's inside. The Slice 5 auto-combat does the rest. Provisional: the creatures are the village's night mobs (zombie, skeleton, spider), standing in for pillagers and the rest until #30 settles names and art. The **abandoned mineshaft (#256)** is not built: the old caves are one already, and #256 says as much. The **stronghold** is only a stone fortress to dig here; it is not the way to the End (#289 is open).

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
| Buried treasure | #244 | dock | gold ore, a chest's book | old stone comes down |
| Shipwreck | #245 | dock | gold ore, flint, two chests | old stone comes down |
| Ocean ruins | #246 | dock | lapis (needs iron pickaxes), gold ore, a chest | old stone comes down |

`Survey.FINDS` is an ordered list: each successful survey reveals the next place, so the order is the order places are found in. The two on the road to the mine take its longer walk.

## Next

The rest of group A of #242 need something the mine kind lacks: **another village** (friendly: trading and recruiting, #253). Then the structures that need combat (group B), then the late ones. The ruined portal (#243) is already a survey find that unlocks the village's own portal rather than an adventure map.
