# The game in ten chapters

Kept from issue #320. A map of the whole game in ten chapters, for tracking where it is and where it needs to get. Each chapter is a stretch of play with one theme, drawn from what is **built** (the specs and the code), what is **prepared** (decided, with an open issue), and what is **still to design**. It follows the core loop in the brief: gather, build, recruit, equip, explore, unlock, expand, go further.

Chapters 1 to 3 are also the opening's three book chapters decided in #318 (Shelter, Food, Expanding). The rest are play after the founding. A slice is how it was built; a chapter is how it plays, so one chapter can draw on several slices. Chapter 5 was the meadow; it is now part of chapter 3, and chapter 5 is the Cartographer (owner).

## At a glance

| # | Chapter | Theme | State | Built in | Open work |
|---|---|---|---|---|---|
| 1 | Shelter | A first day alone: tools, stone, a bed | Built, reorder planned | Slice 1 | #318 |
| 2 | Food | A farm and a fire, so a trip can be fed | Built, rework planned | Slice 2 | #319 |
| 3 | Expanding | A storehouse, a board, the meadow, the first neighbours | Built; houses in tiers with entrances | Slices 1–2, 3.5 | #318 |
| 4 | A working village | Jobs, skills, workstations, hunters | Built; hunters lead animals home, torches at night | Slice 2 | #275, #272 |
| 5 | The Cartographer | Surveys that find the cave, the ruined portal and more | Part 1 built (table, surveys, world map) | New | #321 |
| 6 | The cave | The first real expedition (today's old mine), found by the Cartographer | Built, to be reworked | Slices 3, 3.5 | #238, #241, #186, #188 |
| 7 | Roads and rails | A road, a bridge, the line and the cart | Built | Slice 4 | #210 (the meadow's road) |
| 8 | The Nether | A ruined portal, then guards, scouting, trading, a fortress | Built, a new gate planned | Slice 5 | #321, #286, #19, #20 |
| 9 | Enchanting and automation | Books, a workshop, freight and devices | Built | Slice 6 | #286 |
| 10 | Beyond | The End, the Sift, structures, the coast | Prepared, not built | Slice 7 and later | #289, #290, #242–#268, #271 |

## 1. Shelter

*A first day: chop, craft, break a boulder, hunt for wool, build a house.*
- **Built:** the founding checklist (trees, the crafting bench, tools, boulders, sheep, Ada's house with its bed). Residents work through designations and jobs; nothing teleports.
- **Prepared:** #318 reorders it (tools, boulder, sheep, house) and swaps "Paint a stockpile" out.
- **Needs to get to:** a first hour that teaches by doing, with the book explaining why.

## 2. Food

*A farm and a fire, so a party can be fed.*
- **Built:** wheat, bread, cooking at the fireplace, hunger and meals, meat from sheep.
- **Prepared:** #319 builds the farm from the composter, and moves it into the opening before the expedition.
- **Needs to get to:** food that is steady and visible: farms that grow, cooks that keep stock.

## 3. Expanding

*A storehouse, the first board, a second house, the first neighbour.*
- **Built:** the expedition board, the second bed and a traveler's arrival, storehouse and chests, the founding's later goals.
- **The meadow trip is here:** adventures as data (`Sim.ADVENTURES`), the expedition board, planning and packing, the meadow map, cows and pigs, pens, breeding, hunting, leather armor and the tally bar groups. The meadow is known from the start, by its signpost.
- **Prepared:** #210 (a road to the meadow like the mine's), #181 (a location dropdown), #185 (a cargo priority list), #318 (a storehouse that grows by painting, 3 to 7 wide), #285 (houses in tiers: a tent, a 3×3 house, a 5×5 building; #270 settled the 3×3).
- **Needs to get to:** a village that grows in place, with room reserved for what is next.

## 4. A working village

*Jobs, skills, workstations and a living village.*
- **Built since:** a night with mobs, the golem and village combat (Slice 2.5), torches at each new house's door that keep night work at full speed (#367), houses with entrances and an Update for old ones (#285, #356), and a book that unlocks Build and Craft entries (#370–#372).
- **Built:** the Jobs board, workstations claimed one per resident (#184), skills with levels, which carry on past 5 (#236), tools and their wear, hunters and the herd floor, worn paths, claiming new land, and a farmer's, lumberjack's, mason's, toolsmith's and cook's own work.
- **Prepared:** #275 (what the hunter's lodge does), #234 (move a building), #272 (how workstations upgrade), #269.
- **Needs to get to:** every workstation useful all game, upgrading in place, with clear stuck reasons.

## 5. The Cartographer

*Knowing the world around the village.*
- **Built (part 1, #321, #347):** a cartographer's table, surveys by sector and ring, the caves and a ruined portal found rather than given, a corner map and a full-screen world map with the parties on their way. Nothing of its own before that. Scouting for the Nether routes (#153) is the nearest thing, and adventures are already data.
- **Decided (owner):** the player sends the Cartographer out and sees how long the survey takes; the ruined portal is required for the Nether; the cave starts hidden.
- **Prepared:** #321 (a cartographer's table, surveys, a map), #298 (a minimap), #243 (the ruined portal), #242 (the structures to find).
- **Needs to get to:** a village that learns its surroundings as it grows, with each new place a reason to build, pack and go.

## 6. The cave

*The first real expedition, and what is under the village. Today's old mine; the Cartographer finds it first.*
- **Built:** the mine map and its deeper levels, ore, coal, iron, gold, obsidian, hazards, injuries, armor, the discovery pause, mining by the party from its packs.
- **Prepared:** #204 (decided: once every boulder is gone, the mason's bench becomes a mineshaft), #238 (the old mine becomes a cave with a biome per layer), #241 (cave mobs), #186 (diamonds), #188 (clear a level first), #256 (an abandoned mineshaft as its own adventure).
- **Needs to get to:** an underground with variety and a reason to go deeper.

## 7. Roads and rails

*Making the journey cheaper.*
- **Built:** the road map to the mine, the bridge, the cut, stations, the line, the cart, riding it, building it from the village end.
- **Built since:** the road to the mine is 88 cells (about 30 s), the meadow's strip 46 (#377).
- **Prepared:** #210 (a road for the meadow), decided in #29: custom redstone never, separate lines that meet at shared stations.
- **Needs to get to:** every adventure with a road, and a line that visibly saves time.

## 8. The Nether

*A foothold in another world, reached through the ruined portal the Cartographer finds.*
- **Built:** the portal, the landing, guards and visible auto-combat, the shelter and supply cache, three scouted routes, mission types, the quartz site, piglin trading, the fortress delve, stranding and rescue instead of death, the Nether line.
- **Prepared:** #286 (unstaffed outposts, camps and depots), #20 and #19 (difficulty, village combat), #30 (final names).
- **Needs to get to:** a second realm with its own supply chain and a reason to stay.

## 9. Enchanting and automation

*Discovering things, then letting the village run them.*
- **Built:** lapis and redstone in the deep mine, enchanted books found and traded, the enchanting workshop and its Enchanter, four enchantments, the portal line, unmanned freight carts with approval, sensors, conditions, loaders, dispatchers and dust lines.
- **Decided:** ready-made devices only (#29), a staffed outpost with one resident, food and repairs by cart, falling back to a cache (#26).
- **Prepared:** #286 (outposts, camps and depots in other dimensions, supplied from home).
- **Needs to get to:** an automated village where the player decides, not carries.

## 10. Beyond

*Everything past the Nether.*
- **Built:** nothing in the sim yet.
- **Built (Slice 7, started):** nine mine-kind structures (#244 to #252: the desert well, desert temple, jungle temple, fossil site, trail ruins, geode, and on the new coast buried treasure, a shipwreck and ocean ruins), found by the Cartographer's surveys, and the village's coast with its dock (#271); the Nether has a fourth route to a fossil ridge (#254). See `slice-7-spec.md`.
- **Prepared:** #289 (the End: a stronghold portal, the dragon's platform, bridging out), #290 (the Sift, parked), #242 and #243–#268 (Slice 7: 26 structures as adventures), #271 (a coast, a dock and underwater adventures), #66 (night and mobs).
- **Needs to get to:** a late game of long, planned journeys, each different.

## Cross-cutting (not a chapter)

These touch every chapter and are tracked on their own:
- **Playing it:** #295 (autosave), #296 (the stuck list), #297 (a message log), #298 (a minimap), #299 (fast-forward), #300 (a roster), #301 (repeat a trip), #304 (trees hide things), #302 (colour is not the only cue).
- **The web build and platforms:** #276 (favicon), #306 (arrows), #307 (a drop-down off-screen), #315 (saves in the browser), #287 (Steam Deck), #16 (title and platforms).
- **Look and sound:** #206 (pixel textures), #237 (see-through characters), #30 (own names and art).
- **Health:** #305 (split `sim.gd` and `hud.gd`), #313 and #309 (flaky tests), #303 (the player guide's scope).

## How to use this

When a chapter's built work changes, update its state in the table. When an issue is filed, add it to the chapter it serves. The "Needs to get to" line is the goal that issue work moves toward, so a chapter is done when that line is true, not when its slice closes.


