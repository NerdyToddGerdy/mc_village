# Slice 8: the Steam Deck

Desktop, the web build and the Steam Deck are the targets (#16, #287); consoles are out. This slice only describes what's new since Slice 7. Issues: #421 controller input, #422 a UI readable at 1280x800, #423 a Linux export, #424 a Deck play check.

## Controller input (#421)

`Controller` (`view/controller.gd`, owned by `Game`) turns joypad events into the keys and clicks the game already handles, so there is one set of rules, not a second input path:

- **A, X, B** are the left click, the right click and Esc, at the cursor (`KeyBindings.PAD_FIXED`, not rebindable).
- **Buttons for actions** are `KeyBindings.pads` (action → buttons), with `PAD_DEFAULTS`; a pressed button becomes the action's first key through `Input.parse_input_event`. They are saved in the keys file (`[pads]`), shown on the Controls page next to the keys, and rebound with its Button column (B cancels).
- **Sticks and triggers** (each frame, `Controller.update`): the right stick moves the mouse cursor, the left stick pans (`Game._pan_screen`), a trigger zooms once per press.
- Held actions (`KeyBindings.is_down`) also count a held button, so the D-pad pans.

The click and pointer events are pushed straight into the window's viewport (`Viewport.push_input`), like a mouse click; keys go through `Input.parse_input_event` so held keys (`Input.is_key_pressed`) still work for panning. `Controller` keeps its own cursor: the mouse's last position, or where the stick took it.

## The Deck bot (#424)

`tests/playtest_deck.gd` plays the opening at 1280x800 with controller events only: the cursor moved as the stick would (a pointer motion), A to click Play and Chop trees and to drag-mark trees, Start and B for the menu, Y and LB for the Gather and Build menus, the D-pad to pan. It runs in CI (`tests.yml`) and prints "deck bot done" with no FAIL lines (it doesn't use the usual PLAYTEST PASSED line).

Every order is on a menu a click reaches, so the controller reaches every order. The keyboard stays as it was; tests that set `game.keys_path` still get default keys.
