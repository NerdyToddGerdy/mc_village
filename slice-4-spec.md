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

**Laying.** Rails go out from the village with Build work, like the bridge's planks, and a segment is laid in one go once its rails are there. #122 adds the railhead pile, rail-by-rail laying and the crew's own stuck reasons.

**Cancel.** Cancelling a track segment sets down any rails delivered to it as a stack beside the line.

**Saving.** Track segments are sites on the road map, each with its segment number.

## 6. What's still to come

Each build issue carries its own rules until it's built, then adds its section here:

- #122 Lay track: a visible track crew and the railhead
- #123 Stations at both ends, with cart loading
- #124 Ride the line: faster travel both ways, same mining
- #125 The Slice 4 playtests

## 7. Controls

| Action | Default key |
|---|---|
| Switch between the village, the old mine and the road | Tab |

## 8. Tuning table (provisional)

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
| `CART_SPEED` | 8 cells/s | Riding speed over finished track, for the route's estimate. #124 uses it for riding. |
| `CART_CAPACITY` | 20 | Items a minecart carries. Used from #123. |
| Station cost | planks and cobblestone, set by #123 | A 1×3 platform with a buffer stop. |
| Station loading rate | set by #123 | Items per second loaded or unloaded at a station. |
