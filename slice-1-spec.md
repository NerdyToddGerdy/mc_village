# Slice 1 Spec — The Founding Moment

Companion to `block-village-design-brief.md`. The brief says *what* was decided; this spec says *how* Slice 1 works. Every number here is **provisional** and lives in the tuning table (§11) so it can be changed in one place.

## 1. Scope and done criteria

Slice 1 is done when a player can, from a fresh start and without debug tools:

- [ ] Chop trees bare-handed and see logs drop.
- [ ] Place and build a crafting bench from logs.
- [ ] Queue crafts at the bench: planks, sticks, wooden and stone axe/pickaxe.
- [ ] Break boulders once a pickaxe exists; see "Needs a pickaxe" before then.
- [ ] Paint a stockpile zone and watch items get hauled to it.
- [ ] Place two houses and watch them fill in stage by stage as materials arrive.
- [ ] See a traveler arrive after the second house is finished and claim it.
- [ ] Craft tools for the traveler and see the two residents work different jobs at once.
- [ ] Understand every stall from its on-screen reason alone.
- [ ] Pause, run at 1× and 3×, and issue orders while paused.

Out of scope: see §13.

## 2. Architecture

Godot 4, GDScript with static typing.

```
project/
  sim/        Plain data + tick logic. RefCounted classes, no Nodes, no rendering.
  view/       3D world rendering, camera, world marks, HUD. Reads sim, sends commands.
  data/       Templates, recipes, tuning values (Resources).
  scenes/     main.tscn wires one Sim host node to the views.
  tests/      Headless sim tests (framework TBD; GUT is the default candidate).
```

**Rules**
- `sim/` never references a Node, scene, or `view/` class. It must run headless.
- The sim advances in fixed ticks (20 ticks/s). A single host node accumulates frame time and steps the sim `speed × elapsed` worth of ticks; speed is 0 (paused), 1, 2, or 3.
- Views never mutate sim state. They submit **commands** (`DesignateMine(target_ids)`, `PlaceBlueprint(template, pos, rotation)`, `QueueCraft(bench_id, recipe)`, `PaintStockpile(rect)`, `DirectOrder(resident_id, order)`, …). Commands are applied immediately, outside the tick, so designations and blueprints appear at once even while paused; their effects on residents play out on later ticks.
- The sim emits a per-tick **event list** (`ItemDropped`, `StageCompleted`, `JobBlocked`, `ResidentArrived`, …). Views use events for one-off effects and read state for everything else.
- All randomness uses a seeded RNG owned by the sim.

**Saving.** A save is the serialized sim state plus the camera position, in one of 5 slots. Each slot also records a one-line summary (the next goal), time played and when it was saved.
- **Saved:** world, items, stockpile zones, sites and their delivered materials, bench queues, residents' positions, tools and broken flags, queued orders, stats and the arrival timer.
- **Not saved, rebuilt on load:**
  - In-progress jobs, paths and reservations (claims, incoming deliveries, stockpile cell holds). Residents simply re-claim work on the next tick.
  - Carried items, which are dropped where the resident stands.
  - A traveler who's still walking in, who restarts the walk.
- So job and step logic never needs to be serializable.
- The prototype saves through the artifact's private per-player storage and falls back to the browser's local storage. The Godot game writes `user://saves/slot_N.save` (text, via `var_to_str`), one file per slot.

**Main menu.** Opens on launch and with the Menu button or Esc. It has Play/Resume, Save game, Load game and Start over, and the game pauses while it's open. Overwriting a slot, loading and starting over each ask for confirmation on the page.

## 3. World model

- Block grid, 64 × 64 columns, discrete height layers (Slice 1 uses roughly 0–4). Rendered with a `GridMap` + `MeshLibrary`.
- Block types: grass, dirt, stone, log, leaves, plank, cobblestone.
- **Trees** and **boulders** are entities that own a set of blocks. Felling or breaking removes their blocks and drops items at the base.
- The map is one handmade clearing: about 20 trees and 8 boulders, gentle elevation, one walkable edge where the traveler enters.
- Pathfinding: `AStarGrid2D` over walkable columns with step-height ≤ 1.

## 4. Items and inventories

| Item | Source |
|---|---|
| Log | Trees |
| Cobblestone | Boulders |
| Plank | Bench: log → planks |
| Stick | Bench: planks → sticks |
| Wooden axe, wooden pickaxe | Bench |
| Stone axe, stone pickaxe | Bench |

- Items exist as discrete stacks on a cell: on the ground, in a stockpile cell, in a construction site, or carried.
- A resident carries up to `carry_capacity` items of one type, plus one equipped tool per kind (axe, pickaxe).
- **Stockpile zones** are painted rectangles. Each cell holds one stack up to `stack_size`. Haul jobs are created for ground items only when a zone with free space exists.
- The HUD's tallies count every item that isn't carried. Items outside a stockpile also show as a dim "N loose" line. Counting stockpiles only would read 0 for the whole opening, before any zone exists.

## 5. Job system

A **designation** or **request** creates a job. Job types: `chop`, `break`, `haul`, `deliver` (to a construction site), `build`, `craft`.

Each job has: target, required tool (if any), required items (if any), priority, `claimed_by`, and `blocked_reason` (nullable).

**Claiming.** An idle resident scans unclaimed, unblocked jobs and picks the highest priority, then nearest. Default priority order: craft > deliver to a bench > build > deliver to a construction site > chop/break > haul. Bench work comes before construction so that queued tools and materials aren't starved by blueprints competing for the same logs and planks.

**Direct orders.** Right-click with a resident selected creates a job claimed by that resident immediately, overriding its current job (the old job is released). After finishing, the resident returns to normal claiming. A plain right-click also clears the resident's queued orders.

**Queued orders.** Shift + right-click adds a mine or move order to the end of each selected resident's list instead of replacing what they're doing.
- Orders run one after another once the current work is done, then the resident goes back to normal claiming.
- An order is skipped if its tree or boulder is gone or another resident has claimed it. A boulder order is also skipped when no pickaxe exists, with a "Needs a pickaxe" note.
- The resident panel lists queued orders, with a Clear orders button.
- Queued orders are saved; save format v3 added them.

**Blocking.** A job that can't proceed sets a `blocked_reason` and is released. The reason drives the stuck flag, the stuck list, and the resident's status line. Reasons are re-checked on relevant events (items arrive, tool crafted, zone painted) rather than every tick.

| Reason | Shown as |
|---|---|
| `needs_tool` | "Needs a pickaxe" / "Needs an axe" |
| `missing_materials` | "Walls need 6 more planks" |
| `unreachable` | "Can't reach the stockpile" / "Can't reach this tree" |
| `no_worker` | "No one is free to build" |
| `no_storage` | "Stockpile is full" |
| `tool_broke` | "Axe broke — needs a new axe" |

## 6. Crafting

The crafting bench is a 1-block structure built from logs. Selecting it opens its panel, where the player queues recipes, one at a time with **Queue** or five at a time with **Queue 5**. A house's 28 planks take two Queue 5 clicks. A resident claims a `craft` job, fetches inputs, works for `craft_time`, and drops outputs at the bench (to be hauled).

**Queue order.** The queue isn't strictly first-in-first-out:
- Residents feed and craft the first queued recipe whose inputs exist somewhere: already at the bench, on the way, or lying loose or in a stockpile. Blocked recipes are skipped, not waited on. So "Wooden axe, Planks, Sticks" makes the planks and sticks first, then the axe.
- Any recipe whose inputs are already at the bench is crafted immediately.
- Inputs delivered to the bench stay there and count for any recipe in the queue.
- The bench reports a stuck reason only when no queued recipe can make progress. The reason names the first item in the queue.
- Removing the last item from the queue drops the bench's held inputs next to it.

**Automatic ingredients (after the first house is finished).**
- Until the PC's house is finished, every recipe is queued by hand, so the opening teaches the chain from logs to planks to sticks to tools.
- Once the first house is complete, a queued recipe that's short of a bench-made ingredient automatically gets that ingredient's recipe queued ahead of it. The ingredients are planks and sticks. The new entries are marked "(auto)".
- This works through the whole chain. For example, a wooden pickaxe adds sticks, then the sticks add planks, and planks come from logs.
- Only raw materials, meaning logs and cobblestone, have to exist already.
- Auto entries can be removed like any other queue item.

| Recipe | Inputs | Output |
|---|---|---|
| Planks | 1 log | 4 planks |
| Sticks | 2 planks | 4 sticks |
| Wooden axe | 3 planks, 2 sticks | 1 |
| Wooden pickaxe | 3 planks, 2 sticks | 1 |
| Stone axe | 3 cobblestone, 2 sticks | 1 |
| Stone pickaxe | 3 cobblestone, 2 sticks | 1 |

A resident auto-equips a carried or nearby unclaimed tool when a job needs one and it's better than what they hold.

## 7. Tools

| Tool | Chop time | Break time | Durability (uses) |
|---|---|---|---|
| Bare hands | 20 s | can't | — |
| Wooden | 8 s | 10 s | 10 |
| Stone | 5 s | 6 s | 25 |

One use is one tree felled or one boulder broken. When durability reaches 0, the tool is destroyed, the job is released with `tool_broke`, and the resident stops and reports. There's no auto-replacement in Slice 1; a fresh tool in storage is equipped only when the player orders it or when the resident next claims a job needing that tool. (The Slice 2 toolsmith job takes this over.)

**Tools keep their wear.** A tool keeps its remaining uses wherever it goes: dropped, carried to the stockpile, equipped, or saved. A resident who swaps to a better tool drops the old one with whatever it had left. The Tools list shows each spare tool's real uses. A tool fresh from the bench has full uses. Save format v2 added this. Loading a v1 save gives its loose tools full uses, which is what they effectively had before.

## 8. Construction

**Placement.** The blueprint follows the cursor. It shows its footprint, entrance, and stage costs. Placing creates a construction site, not a building. Rotation in 90° steps.
- **Never blocked by:** trees, boulders or stockpile cells. Placing over them clears them:
  - Trees and boulders in the footprint are marked to chop and break.
  - Stockpile cells under the footprint are removed.
  - Loose items are moved aside when the foundation goes down.
  - The cursor hint says what will be cleared ("Clears 2 trees and 1 boulder").
- **Blocked by (red outline, reason on hover):** another building, or the map edge.
- **While clearing:**
  - The site takes no deliveries and no build work until its footprint is clear.
  - Its panel says "Clearing the ground first: …".
  - Clearing needs no tool for trees, which can be chopped by hand, but needs a pickaxe for boulders. Until one exists, the site reports "Needs a pickaxe to clear a boulder" alongside the boulder's own flag.
  - Logs and cobblestone dropped by clearing can go straight into the building.

**Stages.** A template is an ordered list of stages. Each stage lists its blocks and material cost. Only the current stage accepts deliveries. When its materials are complete, a `build` job does `stage_build_time` of work, then that stage's blocks pop in together and the next stage opens.

| Template | Stage | Cost |
|---|---|---|
| Crafting bench | Bench | 4 logs |
| House (5 × 5) | Foundation | 8 cobblestone |
| | Walls | 16 planks, 4 logs |
| | Roof | 12 planks |

A house totals 11 logs (7 as planks) and 8 cobblestone. Bench, two houses, and wooden plus two sets of stone tools need about 30 logs and 28 cobblestone, well under the map's supply, so the opening never dead-ends.

**Ghosting.** The site shows a translucent ghost of the current stage only; finished stages are solid.

## 9. Arrival trigger

When the second house completes and has no owner, start an `arrival_delay` timer. On expiry, a traveler spawns at the map's entry edge, walks to the house, claims it, and becomes an idle resident with no tools. Event `ResidentArrived` focuses a notification. The trigger fires once.

## 10. Controls

The Slice 1 subset of brief §12.

| Input | Action |
|---|---|
| Left-click | Select resident, site, bench, tree, or boulder |
| Left-drag on the map | Pan the camera (with no order active) |
| Shift + drag | Select multiple residents |
| Right-click with selection | Contextual order (mine, move); cursor previews it |
| Shift + right-click | Queue a mine or move order after the current one |
| Toolbar → drag | Paint mine or stockpile; place a blueprint |
| R (while placing) | Rotate blueprint |
| Click empty ground | Clear selection |
| Esc | Cancel the active order; with none, open the menu |
| M | Open or close the menu |
| X / Z | Mine / Stockpile order |
| Shift-drag / Alt-drag (with Mine) | Mark trees only / boulders only (Alt is Option on a Mac); a plain drag marks both |
| B | Build menu |
| T / H | Place crafting bench (table) / house |
| F | Select the next resident and centre on them |
| N | Go to the next stuck item |
| 1 / 2 / 3 | Speed 1× / 2× / 3× |
| ~ | Pause (backtick works too) |
| WASD, arrows / middle-drag | Pan (as well as left-drag) |
| Mouse wheel, trackpad pinch, + / − | Zoom (orthographic size) |
| Space | Pause / resume |
| ? | Controls list |

Order letters avoid W, A, S and D, which pan the camera. Key combinations using Ctrl, ⌘ or Alt are left to the browser or OS. Each toolbar button shows its key, and the menu has a Controls page listing every binding.

## 11. Tuning table (provisional)

| Key | Value |
|---|---|
| `tick_rate` | 20 /s |
| `speeds` | 0, 1, 2, 3 |
| `walk_speed` | 3 blocks/s |
| `carry_capacity` | 4 items |
| `stack_size` | 16 |
| `tree_logs` | 4–6 |
| `boulder_cobblestone` | 6 |
| `craft_time` | 3 s |
| `stage_build_time` | 10 s |
| `arrival_delay` | 45 s |
| Tool times and durability | §7 |
| Recipe and stage costs | §6, §8 |

## 12. Interface and visual language — "carpenter's chalk"

The world is a building site; the player is the foreman. Orders are chalk marks on the blocks. The HUD is slate boards at the screen edges; the centre stays clear.

**Tokens**

| Name | Hex | Role |
|---|---|---|
| Slate | `#2F3B37` at 92% | Panel background |
| Slate deep | `#232C29` | Insets, borders, pressed state |
| Chalk | `#ECEAE2` | Text, selection outlines |
| Chalk dim | `#B3B8AF` | Secondary text |
| Cut red | `#F25C54` | Chop and break marks |
| Build blue | `#6FA8DC` | Blueprint ghosts, build progress |
| Store green | `#8CC084` | Stockpile zones |
| Stuck yellow | `#E8C547` | Stuck flags, stuck list |

World palette (kept darker than the chalk so marks sit on top): grass `#6F8F4E`, stone `#8A8D86`, log `#7A5634`, plank `#C49A62`.

**Type.** Bricolage Grotesque (OFL), bundled. Condensed bold for names and stage headings, regular for body, tabular figures for counts. Sentence case everywhere; no all-caps labels, no monospace.

**Layout** (1280 × 720 minimum, scales via `content_scale`):

```
+---------------------------------------------------+
| Logs 12  Planks 4  Sticks 2  Stone 0   [||] 1x 3x |
|                                         Stuck (2) |
|                                         ! Walls   |
|            [ isometric diorama ]        ! Ada     |
|                                                   |
| +-----------------+                               |
| | Ada · idle      |   Mine  Stockpile  Build      |
| | Needs a pickaxe |                               |
| +-----------------+                               |
+---------------------------------------------------+
```

- Top left: material tallies, plus a Tools count. Hovering, focusing or tapping Tools opens a list:
  - Each resident's equipped axe and pickaxe, with uses left as a bar. The bar turns yellow at 3 uses or fewer.
  - A "Broke" note for any tool that broke.
  - Spare tools, with how many are in the stockpile and how many are lying loose.
- Top right: speed controls.
- Right edge: stuck list, shown only when something is stuck; clicking an entry focuses the camera.
- Bottom left: selection panel (resident, site, or bench, where crafts are queued).
- Bottom right: orders toolbar — Mine, Stockpile, Build ▸ (Crafting bench, House). Mine is one order for both trees and boulders: a drag marks every tree and boulder in it, and clicking a marked one unmarks it.

**World marks.** Shape always differs, so colour is never the only signal.

| Order | Mark |
|---|---|
| Mine (tree) | Red slash on the tree |
| Mine (boulder) | Red X on the boulder |
| Blueprint | Blue dashed outline; current stage as translucent ghost |
| Stockpile | Green hatched floor |
| Stuck | Yellow flag above the site or resident; reason on hover |

Marks render in an overlay pass (`no_depth_test`) with a dark under-stroke so trees can't hide them and they read on any block.

**Keeping work visible.**
- **Fading trees:** a tree fades to a see-through shape (about 30% opacity) when it stands between the camera and something the player is focused on. That means a selected resident, the cell under the cursor, a blueprint being placed, or a selected building, tree or boulder. The tree under the cursor stays solid, so you can see what you're about to mine.
- **Roof cutaways:** a finished house's roof is cut away while the house is selected or the cursor is inside its footprint.
- **Silhouettes:** a resident hidden by anything else shows as a chalk silhouette.
- **Clicking:** clicks go to residents first, then trunks, boulders and buildings, then canopies only when nothing else is under the cursor.

**Contrast (checked).** Against the terrain, the chalk colours alone reach only 1.1 to 2:1, so the `#232C29` under-stroke is required, not decoration. Measured against the stroke:

| Mark | Colour | Contrast with stroke |
|---|---|---|
| Chop, break | Red | 4.4:1 |
| Blueprint | Blue | 5.7:1 |
| Stockpile | Green | 6.8:1 |
| Stuck flag | Yellow | 8.6:1 |

Red was `#D2483F`, which measured 3.2:1 against the stroke and 2.6:1 on slate, so it was brightened to `#F25C54`.

On panels, text uses chalk, chalk dim, or stuck yellow only. Red and blue fall below 4.5:1 there, so they're limited to icons and bars.

**Copy rules.** One verb per action, used everywhere: the order is "Mine", the button and panels say "Mine" / "Cancel mining". A resident's status names what they're actually doing ("Chopping a tree", "Breaking a boulder"). Stuck reasons name what's missing and how much (§5 table).

**Godot.** One `Theme` resource: `StyleBoxFlat` slate panels, the bundled font as the default font, chalk as the default font colour, focus outline in chalk.

## 13. Deferred to later slices

Needs (food, rest), toolsmith and automatic tool replacement, planks for anything beyond houses and tools, more building types, procedural maps, camera rotation, save/load UI, recruitment beyond the first traveler.
