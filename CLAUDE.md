# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**Block Village** (working title) is an isometric settlement simulation inspired by Minecraft. The repo holds:
- `block-village-design-brief.md`: the vision and decisions document.
- `slice-4-spec.md`: the Slice 4 spec, the current slice (#13). It only describes what's new or changed since Slice 3. Issues not built yet carry their own rules; each adds its section to the spec when it's built.
- `slice-3.5-spec.md`: the Slice 3.5 spec, the meadow adventure (#144), built after Slice 4. It only describes what's new or changed since Slice 3. Issues not built yet carry their own rules; each adds its section when it's built.
- `slice-3-spec.md`: the Slice 3 spec (done, plus the deeper mine levels, #132). It only describes what's new or changed since Slice 2.
- `slice-2-spec.md`: the Slice 2 spec (done). It only describes what's new or changed since Slice 1.
- `slice-1-spec.md`: the Slice 1 spec, still the reference for everything Slice 2 doesn't change. It covers architecture, the job system, recipes, construction, controls, saving, the tuning table, and the "carpenter's chalk" UI language.
- `prototype/founding.html`: a playable, single-file browser prototype of Slice 1.
  - It's opened directly in a browser, with no build step or dependencies beyond Google Fonts.
  - It covers **Slice 1 only** and stays frozen there. From Slice 2 on, rules live in the specs and the Godot game, which have their own tests and bot playtest. Update the prototype only for Slice 1 rule changes.
  - Its live copy is published as a claude.ai artifact.
- `game/`: the Godot 4.7 project, through Slice 4 and into Slice 3.5.
- `docs/how-to-play.md`: the player's guide. Update it when a change alters what the player sees or does.

## Commands

Godot is installed at `/Applications/Godot.app/Contents/MacOS/Godot` (via `brew install --cask godot`). Run these from `game/`:

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --path .                                              # play
$GODOT --headless --path . -s res://tests/run_tests.gd       # sim tests; exit code 1 on failure
$GODOT --headless --path . -s res://tests/game_test.gd       # real game scene: menu, save, load, start over
$GODOT --headless --path . -s res://tests/playtest.gd        # bot plays the whole opening through pushed input events (~1 min)
$GODOT --headless --path . -s res://tests/playtest_village.gd  # Slice 2 bot: founding (by command), then the village through input, with a meadow adventure for wool
$GODOT --headless --path . -s res://tests/playtest_slice3.gd   # Slice 3 bot: an expedition from a saved Slice 2 village, then a trip down to Level 2, through input
$GODOT --headless --path . -s res://tests/playtest_slice4.gd   # Slice 4 bot: survey, build and ride the line from a saved Slice 3 village
$GODOT --headless --path . --import                          # refresh the class cache after adding a class_name script
$GODOT --path . --resolution 1280x720 -- --screenshot        # scripted opening, saves user://screenshot.png, quits
$GODOT --path . --resolution 1280x720 -- --screenshot-menu   # Save game menu (--main or --keys for those pages), saves user://screenshot_menu.png
```

Screenshots and saves (`saves/slot_N.save`) live in `~/Library/Application Support/Godot/app_userdata/Block Village/`. `game_test.gd` and the playtests write to `test_saves/` and `playtest_saves/` there instead, so they never touch real saves. The playtests push input with `push_input(event, true)` (local coordinates) because the window is stretched. Their shared input helpers live in `tests/playtest_base.gd`. It's the quickest way to check view changes without clicking through the game.

There's no single-test runner. To focus on one test, temporarily trim the `tests` list in `tests/run_tests.gd`. Tests are named after the behaviour they cover.

## Godot project layout

- `game/sim/`: all game rules, as `RefCounted` classes with no Nodes.
  - `sim.gd` holds the state and does the work: ticking, claiming jobs, interpreting job steps, computing stuck reasons, commands, and save/load.
  - Entities are plain Dictionaries (cells are `Vector2i`). Compare them with `is_same()`, never `==`, because GDScript compares Dictionaries by content.
  - **Maps** (`sim_map.gd`): the village plus site maps such as the old mine (`old_mine.gd`), its deeper levels (`mine_levels.gd`, generated from the game's seed, `old_mine_2` and on) and the meadow (`meadow.gd`). The sim works on one map at a time: `trees`, `items`, `sites` and the rest are the current map's, switched with `use_map` / `on_map`. At rest it's always on the village, so the HUD, goals and tallies read the village. Residents and buildings carry their `map`, and a command about one switches to its map itself. The view switches the sim to the map in view (`game.view_map`) only while it draws or handles input.
  - **Expeditions:** `sim.expedition` is the one expedition, planned at the expedition board, packed there, then sent off with Depart. The board opens on the adventures list (`Sim.ADVENTURES`, `adventures()`), one row per destination. A party on the walk to or from the meadow is `away`, with `trip` naming where they're going. The road to the old mine is a map of its own (`road.gd`): a party walks it with `trip` naming where they're going, a site such as "old_mine" or "village" on the way home. Village residents also walk out onto it to build the bridge, the stations and the line, and to clear the cut. `sim.cart` is the line's one minecart: the party rides it when it's parked at the village station. A party bound for a deeper level walks across each level above and down through its door. At the site the party works from its packs (`provisions`, `tools`, `cargo`) without the player: mining at the old mine, hunting at the meadow. Animals of every species live in a map's `sheep` list, each with its `species`. A serious injury, the iron discovery or reaching a door down adds to `sim.pending`, a choice the game pauses for until `choose()` answers it.
  - `job.gd` is a job's step list plus its "holds", the reservations it keeps. A step that uses up a hold removes it, and whatever's left is undone when the job ends. Jobs aren't saved.
  - `tuning.gd` holds every number. `defs.gd` holds items, recipes and building templates. `goals.gd` holds the founding checklist.
- `game/view/`: drawing only.
  - `world_view.gd` rebuilds MultiMesh block geometry when `sim.rev` changes and draws residents and per-frame overlays every frame.
  - `hud.gd` builds the slate-and-chalk HUD from one code-built `Theme`. Panels rebuild only when their content changes, and never while a mouse button is held over them, so clicks aren’t lost to a rebuild.
- `game/view/key_bindings.gd`: rebindable keys. Input goes through `keys.action_for(event)`; never match raw keycodes in `game.gd`. Tests set `game.keys_path` before adding the game, so they always run with default keys.
- `game/scenes/game.gd`: ticks the sim at 20 Hz times the current speed, owns the camera and selection, and turns input into sim commands. It also saves and loads slots, storing `Sim.save_state()` with `var_to_str`. The HUD and the menu (`view/game_menu.gd`) call its public methods.
- **Changing what's saved:** follow `game/sim/save_format.gd`. **Owner rule: every save must keep loading in every newer version of the game.** A rework never breaks old saves. Its upgrade step carries the player's progress over sensibly. If a change seems to need a break, raise it with the owner first.
  - Bump `SaveFormat.VERSION`.
  - Add an upgrade step from the previous version to `SaveFormat.upgrades()`.
  - Generate the new fixture with `tests/fixtures/make_save_fixture.gd`.
  - Never regenerate or delete an old fixture: `run_tests.gd` loads every fixture, which proves players' old saves still load.
  - Keep old upgrade steps, and `make_save_fixture.gd`'s old-version branches, working as the code changes. Read fields that later versions dropped with `.get()` and a default.
- Avoid naming methods after built-in `Object`/`Script` methods. `_get` and `is_tool` both broke compilation here.

## Technical decisions

- Godot 4 with statically typed GDScript. Real 3D block geometry viewed through a fixed isometric orthographic camera.
- **The sim and the view are kept separate.** `sim/` is plain data and fixed-tick logic: no Nodes, and it must run headless. `view/` only reads sim state and submits commands. It never mutates the sim directly. The sim reports one-off happenings through a per-tick event list.
- Every tunable number goes in the spec's tuning table and in data resources, never hardcoded in logic.

## The design docs are the source of truth

- The brief separates **core decisions** from **proposed** details. Treat core decisions as fixed. Treat proposed mechanics and all numbers as provisional, not final balance.
- Section 14 ("Open Decisions") lists questions that are deliberately still open, including platforms beyond desktop, combat, needs depth, and party sizes. Don't quietly settle any of them in code or docs. Raise the choice with the user.
- Minecraft-derived content (Nether, End, the Sift, enchantments, redstone, minecarts) is an adaptation and doesn't have to match Minecraft's exact rules. How much original versus directly referenced terminology to use is still an open decision.

## Core loop and principles

Gather locally → build and support the village → recruit residents → equip an expedition → explore and recover supplies → unlock improvements → expand infrastructure → take on more ambitious expeditions.

Cross-cutting principles that design and implementation work should keep:
- Work and material movement are visible in the world. Resources are gathered, hauled, stored, processed, and consumed. Nothing teleports into a stockpile.
- Direct orders to characters gradually give way to delegation. Designations (chop, break, haul, build) create jobs that eligible residents claim. Direct orders override priorities only for a while.
- Idle or stalled work always reports an actionable reason: missing materials, no tool, unreachable stockpile, unavailable labor, injury, or rest.
- Job buildings start simple and evolve in place (bench → workshop, fireplace → kitchen). Each reserves the plot its upgrade needs, so placement must keep that plot clear.
- Setbacks can be recovered from. The home village stays useful throughout progression.
- Residents sent on expeditions are absent from village labor.
- Minecart routes speed up travel in both directions but don't increase extraction speed.

## Development order

Section 13 defines prototype slices that are built one at a time, not as a single MVP:
1. Founding moment: bare-handed PC, crafting bench, tools, a stockpile, two houses, and the first villager's arrival (see `slice-1-spec.md`).
2. A functioning village: jobs, food, tools, more residents, and bottlenecks.
3. The first expedition.
3.5. The meadow adventure (built after Slice 4).
4. Route investment (minecarts).
5. A Nether foothold.
6. Enchantments and one redstone automation chain.

Scope new work to the current slice. Don't build ahead into later slices' systems.
