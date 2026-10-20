# Block Village

*Working title.*

An isometric settlement game inspired by Minecraft. You start with one person in a clearing. Ada gathers wood and stone, crafts tools, and builds the first houses. Then a traveler arrives, work becomes shared, and the village grows. Later, groups set out on expeditions and bring back supplies and discoveries. You don't control anyone's every swing: you mark work and place blueprints, and residents take on the jobs themselves. When anything stalls, the game tells you why.

The game is built in slices, each a playable step:

| Slice | What it adds | Status |
|---|---|---|
| 1. The founding moment | One founder, bare hands, a crafting bench, tools, stockpiles, two houses, the first traveler | **Done** |
| 2. A functioning village | Jobs and skills, food, sheep and beds, a toolsmith, more residents | In progress |
| 3. The first expedition | A small party, provisions, a trip and a return | Planned |
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

The game opens on the main menu. Choose **Play**. The goals panel at the top left walks you through the founding, one step at a time.

1. **Mine trees** (X, then click or drag over them). Ada fells them by hand, slowly.
2. **Build a crafting bench** (B, then Crafting bench, or press T). Select it and queue planks, sticks and a wooden pickaxe.
3. **Paint a stockpile** (Z, then drag) so materials get carried somewhere tidy.
4. **Mine boulders** for cobblestone once there's a pickaxe.
5. **Build a house** for Ada (H), then a second one. **Queue 5** on the bench saves clicks on planks.
6. A traveler, **Tomas**, arrives and moves into the spare house.

If something is stuck, a yellow flag appears over it and in the **Stuck** list at the top right, with the reason. Click an entry to go there.

### Controls

All keys can be changed on the menu's **Controls** page. Esc and the mouse can't be changed.

| Key or mouse | Action |
|---|---|
| X / Z / B | Mine, Stockpile, Build |
| G / P | Hunt sheep, paint a farm plot |
| T / H / K | Place a crafting bench, a house or a fireplace (R turns the house door, or the plot a bench or fireplace reserves to grow into) |
| Shift-drag / Alt-drag with Mine | Mark trees only, or boulders only (Alt is Option on a Mac) |
| Click | Select a resident, tree, boulder or building |
| Shift-drag | Select several residents |
| Right-click | Order the selected residents to mine or walk |
| Shift + right-click | Queue an order after their current one |
| Drag, W A S D, arrows | Pan |
| Mouse wheel, pinch, + / − | Zoom |
| Space / ~ | Pause or resume / pause |
| 1 / 2 / 3 | Game speed |
| F / N | Next resident / next stuck item |
| Esc or M / ? | Menu / Controls |

### Saves and settings

The menu has five save slots. Saves and key bindings are kept in Godot's user folder:

- macOS: `~/Library/Application Support/Godot/app_userdata/Block Village/`
- Windows: `%APPDATA%\Godot\app_userdata\Block Village\`
- Linux: `~/.local/share/godot/app_userdata/Block Village/`

Older saves keep loading as the game changes: each save is upgraded step by step when it's loaded.

## Tests

Run these from `game/`. CI runs all three on every push and pull request.

```sh
godot --headless --path . --import                          # once, or after adding a script with a class_name
godot --headless --path . -s res://tests/run_tests.gd       # game rules, no graphics
godot --headless --path . -s res://tests/game_test.gd       # the real game scene: menu, saves, input, drawing
godot --headless --path . -s res://tests/playtest.gd        # a bot plays the opening through real input (~1 min)
```

On macOS, `godot` is `/Applications/Godot.app/Contents/MacOS/Godot`.

## What's in the repository

| Path | What it is |
|---|---|
| `block-village-design-brief.md` | The vision and the design decisions |
| `slice-1-spec.md`, `slice-2-spec.md` | How each slice works, in detail |
| `game/` | The Godot project. `sim/` holds the game rules, `view/` draws them, `scenes/` connects them, and `tests/` tests them |
| `prototype/founding.html` | The single-file browser prototype of Slice 1, where rules were tried before the Godot build. Open it in a browser. |
| `CLAUDE.md` | Notes for working on the code with Claude Code |

Work is tracked in [GitHub issues](https://github.com/NerdyToddGerdy/mc_village/issues), with a milestone per slice.

The HUD font is Bricolage Grotesque, used under the SIL Open Font License (`game/assets/fonts/OFL.txt`).
