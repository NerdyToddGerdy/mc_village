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

## 2. What's still to come

Each build issue carries its own rules until it's built, then adds its section here:

- #118 The road to the mine: a route strip map
- #119 Survey the route: segments, obstacles and journey estimates
- #120 Rails and minecarts
- #121 Plan the line: track blueprints along the route
- #122 Lay track: a visible track crew and the railhead
- #123 Stations at both ends, with cart loading
- #124 Ride the line: faster travel both ways, same mining
- #125 The Slice 4 playtests

## 3. Tuning table (provisional)

Starting values from the issues. Rows marked "set by #N" get their value when that issue is built.

| Name | Value | Meaning |
|---|---|---|
| Route map size | 48×7 | Cells, village end to mine end. Its length is re-tuned so walking it takes about `MINE_TRIP` (60 s). |
| Segment length | 8 cells | Each segment has its own terrain and at most one obstacle. |
| Rails recipe | 6 iron ingots + 1 stick → 16 rails | As in Minecraft. |
| Minecart recipe | 5 iron ingots → 1 minecart | |
| Rails per segment | set by #120 | |
| Cart speed | set by #120 | Riding speed over finished track. |
| Cart capacity | set by #120 | Added to the party's carrying capacity while the line is complete. |
| Station cost | planks and cobblestone, set by #123 | A 1×3 platform with a buffer stop. |
| Station loading rate | set by #123 | Items per second loaded or unloaded at a station. |
