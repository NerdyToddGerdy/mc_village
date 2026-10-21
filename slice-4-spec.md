# Slice 4 Spec — Route Investment

Companion to `block-village-design-brief.md` and the Slice 1–3 specs. Slice 4 builds on everything in Slices 1–3; this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table at the end.

Tracking issue: #13. Decisions settled with the owner (2026-10-21), and recorded in the brief (§6, §13, §14):

| Question | Decision |
|---|---|
| The connection | **Village ↔ old mine**, one point-to-point line. No switches, branches, signals or timetables (#29). |
| How the route is shown | A **route strip map**: a long, narrow map between the village and the mine, in segments. Parties walk it visibly, and track is laid on it section by section. |
| Materials | **Iron.** Rails from iron ingots and sticks; carts from iron. The mine's iron pays for the line. |
| Loading | **Simple stations at both ends.** Carts load and unload faster there, and cart capacity adds to the party's carrying capacity. Each station reserves the plot for a later loading-station upgrade. |
| What rides | **The party and its cargo together.** No unmanned freight; automation stays in Slice 6. |
| Extraction | Track speeds up travel both ways only. Mining at the site is unchanged, and a test guards this. |

Still open: #29 (custom redstone and wider railway management), #26 (outpost staffing).

## 1. Scope and done criteria

Slice 4 is done when, from a Slice 3 village with iron on hand, a player can:

- [ ] Walk the road to the mine and see its segments, obstacles and journey estimate.
- [ ] Build the bridge and clear the cut.
- [ ] Craft rails and a minecart.
- [ ] Plan the line, see its cost and the time it saves, and watch the crew lay it section by section.
- [ ] Build a station at each end and park the cart.
- [ ] Run an expedition by cart and see it come back faster, with mining at the site no faster.
- [ ] See cargo unloaded at the station and hauled to the stockpile.
- [ ] Understand every stall from its on-screen reason alone.

## 2. The road to the mine (#118)

**A map of its own.** The road between the village and the old mine is a route map, `"road"`, named **Road to the mine**: a 48×7 strip, the village end on the west and the mine end on the east. It's laid out by hand in `game/sim/road.gd`. It becomes known with the old mine, when the expedition board is built, and appears in the map switcher. Tab cycles through the village, the old mine and the road.

**The line row** runs along the middle (row 3), end to end. It's drawn as a trodden path, and the line is laid along it (§5).

**Linking.** The village's route signpost leads onto the road's village end, and the road's mine end leads to the mine's entrance. Moving between maps happens only at these ends.

**Walking replaces the timed walk.** Slice 3's off-map timer (`MINE_TRIP`, 60 s) is gone. A party walks the road at the normal walking speed. They're drawn and can be selected, take no work on the way, and can eat from the packs. Their panel, the signpost and the party line say "On the road to the old mine, about N s" or "On the road home, about N s".

**The trip is shorter than before.** The road is about 16 s on foot. Matching the old 60 s at the same walking speed would need a road about 180 cells long, and that would also need far more rails. So the issue's 48-cell length was kept, and the Slice 3 trip got shorter. This is provisional.

**Saving.** Save format **v18** adds the road map (with its water cells and how much of it has been walked). Older saves get the road when they load, known if the old mine is. A party saved on the road in a v17 save, away with a time left, is placed at the matching point along the road, still heading the same way.

## 3. Surveying the route (#119)

**Segments.** The road has six segments of 8 cells: the village edge, open grass, the stream, the long field, the rocky cut, and the slope below the mine.

**Fog.** Only the first segment is known at first, and the rest is drawn as fog, with nothing shown on it. Anyone walking the road lifts the fog off each segment they reach, so the first trip surveys it. A toast says when the whole road is surveyed, with the walking time.

**Obstacles**, shown in the route report and never as surprises:
- **The stream** (segment 3). People wade across at `FORD_SPEED`. **Build the bridge** places a plank bridge (12 planks, one stage) over it, along the line. Once it's built, there's no more wading, and it's walked over like ground.
- **The rocky cut** (segment 5). Rock walls on both sides, and boulders, three of them on the line. **Clear the cut** marks those three to be mined. Unlike other blueprints, track never marks the cut's boulders by itself.

**Work on the road.** Village residents walk out to do this work. When someone has nothing of a kind to do in the village, they look at the road:
- **Build** deliveries are picked up in the village and carried out along the road.
- **Mine** targets are marked boulders and trees there. A better tool is fetched in the village first.

Out on the road, they keep taking road work of those kinds. With none left, or when they're hungry, they walk back to the village. The stuck list counts the village's materials for what the road needs.

**The route report**, on the village signpost and on the signposts at both ends of the road:
- each segment's name, length and terrain, or "Not walked yet";
- the state of its obstacle ("Bridged", "Cleared") and of its track;
- the walk's estimate on foot, and the ride's once the line is laid (`CART_SPEED`).

The planner's site report shows the walking estimate once the road is surveyed, and "the road isn't walked yet" before.

**Saving.** Segments walked, the bridge (a site on the road map) and the cut's boulders are saved with the road map.

## 4. Rails and minecarts (#120)

**Recipes** at the bench, both **Craft** work. Neither is a tool a resident carries, so the toolsmith's standing orders leave them alone.
- **Rails:** 6 iron ingots and 1 stick make 16 rails.
- **Minecart:** 5 iron ingots make 1 minecart.

**Items.** Rails stack like other materials. A minecart is one big item: one to a cell, and hauled like a tool, but it isn't a tool. Both appear in the tally bar's Materials group, with their own colours, stack drawings and Craft panel icons.

**Saving.** New items only, with no format change.

## 5. Planning the line (#121)

**Plan the line**, on the route panel, is enabled once the road has been walked. It shows the cost before anything is placed:
- the rails still needed, and how many are on hand;
- the iron ingots to craft the rest;
- the time a round trip would save by cart.

**Lay track** confirms it. **Not now** closes the preview.

**Segments as blueprints.** Each segment gets a **Track** blueprint along the line, one stage of `RAILS_PER_SEGMENT` rails. Track is walked over and never blocks the road. It's one point-to-point line, with no switches, branches or signals (#29). Planning again only fills segments that have no blueprint.

**Built from the village end.** Only the first unbuilt segment takes rails and work. A segment whose obstacle is still there waits, and its stuck reason says what it needs: "Track: needs the bridge first", "Track: needs the cut cleared first".

**Laying** is the track crew's work (§6).

**Cancel.** Cancelling a track segment sets down any rails delivered to it as a stack beside the line.

**Saving.** Track segments are sites on the road map, each with its segment number.

## 6. Laying track (#122)

**The track crew** are residents with Build on. Track work is on the road map, so they walk out from the village for it and back when it's done or they're hungry. The Jobs board marks them "(on the road)", and their status reads "On the road: laying track".

**The railhead.** Rails for the line go first from the village to a **railhead pile** at the road's village end, as much as the planned line still needs. From there the crew carries them to the segment being laid, so trips along the line don't start back in the village.

**Rail by rail.** A segment fills in as its rails are laid, `LAY_TIME` each, drawn as rails on sleepers over its share of the segment. It's usable once every rail is down. Segments are still laid from the village end, and a blocked one waits (§5).

**Stuck reasons** on the segment being laid:
- "Track: needs 12 more rails": rails the line still needs that don't exist anywhere, counting the village, the railhead and those on their way.
- "Track: needs the bridge first", "Track: needs the cut cleared first".
- "Track: no one with Build on".

**Saving.** Save format **v19**: each segment's rails laid. The railhead pile is ordinary stacks on the road map.

## 7. Stations and the cart (#123)

**Stations.** **Build the village station** and **Build the mine station**, on the route panel, place a **Station** at that end of the road: a 1×3 plank platform on a stone kerb beside the line, with a buffer stop. It costs 6 planks and 4 cobblestone, and is built from the village like the bridge. The mine's station needs the road walked. It's walked on, and reserves a 3×3 plot for a later **loading station**.

**The cart.** Once the village station is built, a minecart in the village is hauled out and parked there (Haul work). There's one cart for the line.

**Loading.** Carts load and unload at a station at `LOAD_RATE` items a second. By hand, a party unpacks at the village signpost at `HAND_RATE` an item a second each, so a station is faster. Riding home, the party's cargo is loaded into the cart at the mine station, and unloaded onto the village platform. Haulers then carry it along the road to the village stockpile, before other hauling. The rest of the packs (meals and spare pickaxes) are unpacked at the signpost as before.

**Room.** With the whole line laid and the cart ready, the cart's `CART_CAPACITY` is added to the party's packs in the planner. The planner says so.

**The station's panel** shows how much of the line is laid, where the cart is, and what's on the platform.

**Saving.** v19 adds the cart: where it is, what's in it, and who's riding.

## 8. Riding the line (#124)

**When the party rides.** A party rides if, when it departs, the cart is parked at the village station, both stations are built, and the cut is clear. The line doesn't have to be finished.

**Riding.** At the road's end, each member walks to the cart and gets in. When the whole party is aboard, the cart rides to the far station:
- at `CART_SPEED` over laid segments;
- pushed at walking pace (slower still wading the stream) where there's no track yet.

There they get out and walk to the end of the road. Coming home, the cart waits at the mine station, is loaded, and rides back. The party and the cargo ride together: there's no unmanned freight.

**Shown.** The cart is drawn moving along the line, with its riders side by side in it and the cargo heaped on top. Riders' status reads "Riding to the old mine by cart" or "Riding home by cart". The route report gives the walk and the ride as the line stands now: "On foot about 16 s, by cart about 7 s as the line stands."

**Extraction unchanged.** Mining at the site is the same with or without the line, and a test guards this.

**The report** adds the time on the road and the time saved: "By cart: 15 s on the road there and back, about 17 s saved."

**Saving.** The cart's position, state, load and riders are saved, so a game saved mid-ride carries on.

## 9. The Slice 4 playtests (#125)

**Fixture.** `tests/fixtures/slice3_village.save`, made by `tests/fixtures/make_slice3_fixture.gd` from the Slice 2 village: the expedition board built, the old mine visited and its iron vein mined out, 13 iron ingots in the stockpile, and Ada with an iron pickaxe. The road is known but not walked.

**The bot** (`tests/playtest_slice4.gd`) plays through input:
1. A first trip on foot surveys the road.
2. From the signpost: Build the bridge, Clear the cut, and build both stations.
3. Rails and a minecart are queued at the bench.
4. Plan the line, then Lay track. The bot waits for the crew to lay it and the cart to be parked.
5. A second trip rides the cart.

It checks:
- the second round trip spends less time on the road;
- Ada's mining time a block is the same on both trips, normalised for her Mine level, hunger and the dark;
- the cargo comes off at the village platform and is hauled to the stockpile;
- every stall names its fix.

It runs in CI.

**Hand playtest:** a checklist mirroring #51 and #113, in #125. Every stall must be understood from its on-screen reason alone.

**Iron.** The line and a cart take 11 iron ingots, more than the old mine's vein yielded at 2 ore a block. So `ORE_YIELD` is raised to 4 iron ore and 3 coal a block: 16 iron ore, and coal enough to smelt it. That leaves room for an iron pickaxe as well.

## 10. Controls

| Action | Default key |
|---|---|
| Switch between the village, the old mine and the road | Tab |

## 11. Tuning table (provisional)

Starting values from the issues. Rows marked "set by #N" get their value when that issue is built.

| Name | Value | Meaning |
|---|---|---|
| Road size | 48×7 | Cells, village end to mine end (laid out in `game/sim/road.gd`). |
| Segment length | 8 cells | Six segments, each with at most one obstacle. |
| `WALK` | 3 cells/s | Unchanged. The road is about 16 s on foot, replacing Slice 3's 60 s `MINE_TRIP`. |
| `FORD_SPEED` | 0.4 | Walking speed wading the stream, before the bridge. |
| Bridge cost | 12 planks | One stage, 4×3 over the stream. |
| Rails recipe | 6 iron ingots + 1 stick → 16 rails | As in Minecraft. |
| Minecart recipe | 5 iron ingots → 1 minecart | |
| `RAILS_PER_SEGMENT` | 2 | The whole line takes 12 rails, one craft's worth. |
| `LAY_TIME` | 4 s | Laying one rail. |
| `CART_SPEED` | 8 cells/s | Riding over laid track. Where there's none, the cart is pushed at `WALK`. |
| `CART_CAPACITY` | 20 | Items the cart adds to the packs, with the whole line laid. |
| Station cost | 6 planks, 4 cobblestone | A 1×3 platform with a buffer stop. |
| `LOAD_RATE` | 10 items/s | Loading or unloading a cart at a station. |
| `HAND_RATE` | 2 items/s | Each party member unpacking by hand at the village signpost. |
| `ORE_YIELD` | coal 3, iron 4 | Raised from Slice 3's 2 and 2, so the vein's 16 iron ore pays for the line, the cart and an iron pickaxe. |
