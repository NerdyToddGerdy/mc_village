# Block Village

*Working title.*

An isometric settlement game inspired by Minecraft. You start with one person in a clearing. Ada gathers wood and stone, crafts tools, and builds the first houses. Then a traveler arrives, work becomes shared, and the village grows. Later, groups set out on expeditions and bring back supplies and discoveries. You don't control anyone's every swing: you mark work and place blueprints, and residents take on the jobs themselves. When anything stalls, the game tells you why.

The game is built in slices, each a playable step:

| Slice | What it adds | Status |
|---|---|---|
| 1. The founding moment | One founder, bare hands, a crafting bench, tools, stockpiles, two houses, the first traveler | **Done** |
| 2. A functioning village | Jobs and skills, food, sheep and beds, a toolsmith, more residents | **Done** |
| 3. The first expedition | A small party, provisions, a trip to an old mine, and iron | In progress |
| 4. Route investment | Minecart tracks that speed up repeated trips | Planned |
| 5. Nether foothold | A portal, scouting, trading, an outpost | Planned |
| 6. Specialization and automation | Enchantments and a redstone supply chain | Planned |

## Running the game

You need **Godot 4.7** (the standard edition, not .NET).

On a Mac with Homebrew:

```sh
brew install --cask godot
```

Elsewhere, download Godot 4.7 from <https://godotengine.org/download>.

Then run the game from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path game   # macOS
godot --path game                                          # Linux or Windows, with godot on your PATH
```

You can also open `game/project.godot` in the Godot editor and press **Play** (F5). The first launch takes a few seconds while Godot imports the project.

## Playing

**[How to play](docs/how-to-play.md)** is the full guide: the screen, the founding step by step, orders, residents and the jobs board, crafting, building, food and the controls.

In short: choose **Play** on the main menu, and the goals panel at the top left walks you through the founding.

1. **Chop trees** (X, or Gather → Mine). Ada fells them by hand, slowly.
2. **Build a crafting bench** (T, or Build → Crafting bench).
3. **Make Ada the toolsmith** on the jobs board (J), then queue planks, sticks and a wooden pickaxe at the bench (C).
4. **Paint a stockpile** (Z, then 1) and **break boulders** for cobblestone.
5. **Hunt sheep** (G) for the wool the beds need, then **build two houses** (H).
6. A traveler, **Tomas**, arrives for the spare bed. From there, keep the village fed with farms, the fireplace and trips to the sheep meadow, and give each resident the jobs they're best at.

If something is stuck, a yellow flag appears over it and in the **Stuck** list at the top right, with the reason. Click an entry to go there.

### Controls

All keys can be changed on the menu's **Controls** page. Esc and the mouse can't be changed. The [guide](docs/how-to-play.md#controls) has the full list.

| Key or mouse | Action |
|---|---|
| E / Z / B / C | Gather, Paint and Build menus, and the Craft panel (1 to 9 pick a menu row) |
| X / G / P | Mine, Hunt, Farm plot, directly |
| T / H / K | Place a crafting bench, a house or a fireplace (R turns it) |
| J | Village jobs board |
| Click / Shift-drag | Select / select several residents |
| Right-click / Shift + right-click | Order the selected residents / queue the order |
| Drag, W A S D, arrows / mouse wheel | Pan / zoom |
| Space / 1 2 3 | Pause or resume / game speed |
| F / N | Next resident / next stuck item |
| Esc or M / ? | Menu / Controls |

### Saves and settings

The menu has five save slots and an **Interface size** setting (90 to 130%). Saves, key bindings and the interface size are kept in Godot's user folder:

- macOS: `~/Library/Application Support/Godot/app_userdata/Block Village/`
- Windows: `%APPDATA%\Godot\app_userdata\Block Village\`
- Linux: `~/.local/share/godot/app_userdata/Block Village/`

Older saves keep loading as the game changes: each save is upgraded step by step when it's loaded.

## Tests

Run these from `game/`. CI runs them all on every push and pull request.

```sh
godot --headless --path . --import                          # once, or after adding a script with a class_name
godot --headless --path . -s res://tests/run_tests.gd       # game rules, no graphics
godot --headless --path . -s res://tests/game_test.gd       # the real game scene: menu, saves, input, drawing
godot --headless --path . -s res://tests/playtest.gd        # a bot plays the opening through real input (~1 min)
godot --headless --path . -s res://tests/playtest_village.gd  # a bot plays Slice 2's village through real input
```

On macOS, `godot` is `/Applications/Godot.app/Contents/MacOS/Godot`.

## What's in the repository

| Path | What it is |
|---|---|
| `docs/how-to-play.md` | The player's guide to the game as it plays now |
| `block-village-design-brief.md` | The vision and the design decisions |
| `slice-1-spec.md`, `slice-2-spec.md` | How each slice works, in detail |
| `game/` | The Godot project. `sim/` holds the game rules, `view/` draws them, `scenes/` connects them, and `tests/` tests them |
| `prototype/founding.html` | The single-file browser prototype of Slice 1, where rules were tried before the Godot build. Open it in a browser. |
| `CLAUDE.md` | Notes for working on the code with Claude Code |

Work is tracked in [GitHub issues](https://github.com/NerdyToddGerdy/mc_village/issues), with a milestone per slice.

The HUD font is Bricolage Grotesque, used under the SIL Open Font License (`game/assets/fonts/OFL.txt`).
