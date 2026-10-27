# Slice 3.5 Spec — The Meadow Adventure

Companion to `block-village-design-brief.md` and the Slice 1–4 specs. Slice 3.5 builds on Slice 3's site maps, expedition board and planner. This spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table at the end.

Tracking issue: #144. Decisions settled with the owner (2026-10-21), and recorded in the brief (§5, §8, §9, §13, §14):

| Question | Decision |
|---|---|
| Placement | Its own milestone, **Slice 3.5**, after Slice 3. Slice 3 stays at one destination. |
| The meadow | An **expedition site with its own map**, replacing Slice 2's timed meadow trip. |
| Animals | **Cows, pigs and sheep**, for more meat and leather. |
| Farming | **Pens and breeding** (fed with wheat), so the herds last. Breeding comes off Slice 2's deferred list; shears stay deferred. |
| Leather armor | **Reduces injuries** from expedition hazards. Later, Protection enchantments build on it. |
| Adventures | The expedition board lists every destination. |

Every issue of the slice has its section here: the adventures list (#136), the meadow (#137), cows and pigs (#138), pens and breeding (#139), leather armor (#140), the grouped tally bar (#141) and the playtests (#142).

## 1. Scope and done criteria

From a Slice 3 village, a player can:

- [ ] Pick the meadow from the board's Location dropdown and run an expedition there.
- [ ] Hunt cows, pigs and sheep, and bring back a full party's cargo.
- [ ] Pen animals and breed them with wheat from the village farms (#139).
- [ ] Cook beef and porkchops.
- [ ] Craft leather armor, see it worn, and see it lower injury chances in the mine (#140).
- [ ] Read the growing inventory at a glance (#141).
- [ ] Understand every stall from its on-screen reason alone.

## 2. The adventures list (#136)

**The list.** Selecting the expedition board opens it on the **adventures list**: one row per known destination, in the order the sim's `ADVENTURES` names them. Each row shows the destination's name, what's there ("Coal, iron · Level 2 open" or "Cows, pigs, sheep · 21 animals"), the walk each way, its known hazards and its status:
- **Not yet visited** or **Visited**, while nothing is planned;
- **Packing to go**, **Party on the way**, **Party there now** or **Party heading home**, for the destination the party is bound for;
- **Locked: the party is at the meadow** (or "packing for the meadow") for every other row.

**The Location dropdown (#181).** The list is a dropdown in the board's header instead of a page, to save space. Closed, it shows the chosen place and its walk ("Meadow · ~30 s each way"); open, it lists each destination as one line (name, walk, status, and a flag where hazards are known; the hazards themselves stay in the site report). Choosing one shows its site report and planner at once; there is no list page and no **All adventures** button. Opening the board picks `game.adventure`, the last place chosen or the first known, and a signpost opens the board on its own. While a party is packing or out, the dropdown shows the party's place and the other lines can't be chosen ("One expedition at a time"); with nowhere known it's disabled, "Nowhere known yet". The choice is view state, so no save change.

**Built to grow.** Destinations are data: a later one (the Nether, an outpost) is a new entry in `ADVENTURES`, with a site report.

**One expedition at a time** (#25). While a party is packing or out, the rows can't be chosen. The board shows each row's status above the packing or the party.

**Signposts.** The village has a signpost per destination on the matching map edge: the meadow's on the west, the old mine's on the east. Clicking the meadow's signpost opens its adventure on the board (with no board, its panel says a board would know what's past it). The old mine's signpost keeps its route report (Slice 4) and gets a **Plan a trip to the old mine** button.

**Known destinations.** Both the old mine and the meadow become known when the expedition board is built. Each map's known and visited flags are saved.

## 3. The meadow (#137)

**A map of its own.** The meadow is a site map, `"meadow"`, named **Meadow**: 24×24, hand-laid in `game/sim/meadow.gd`. It has open grass, a pond with a muddy bank, scattered trees and a few old fences. The party arrives at the **entrance on the east edge**, the side the village is on, by a signpost pointing home. It appears on the map switcher once it's known.
- **Water** on a site map can't be walked through: the pond is walked around. Only the road's stream (Slice 4) is forded.
- **Fences** stand like rock: nobody walks through them.

**Herds.** Sheep, cows and pigs wander it (§4): 9 sheep, 6 cows and 6 pigs at the start, the most it holds of each in the wild. Pens (§5) can hold more.

**Going there.** An expedition like the old mine's: plan the party, provisions and objective at the board; pack, stage and depart. The party carries the packs to the **meadow signpost** on the village's west edge and walks off the map for `MEADOW_WALK`. They're away: not drawn, not working and not getting hungry, and their panels say "On the way to the meadow, N s". The way home is the same walk back, to the same signpost, where they unpack.

**The objective** is "Bring back N" of wool, raw mutton, leather, raw beef or raw porkchops. The planner packs no spare pickaxes for the meadow by default.

**Working it.** At the meadow, the party works by its orders, as at the mine (Slice 3 §11):
- it **marks animals** that give the objective's item, nearest the entrance first, a few at a time, until what's packed, lying about and marked will make the target;
- it **hunts** what's marked (the Hunt order works there too), follows an animal that wanders, picks up the drops and packs them;
- once the objective is met, it packs whatever else is lying about, the other drops of the same animals.

Cargo is limited by **carrying capacity**, not by Slice 2's fixed "2 sheep's worth": a full party with packs brings back far more than the old trip did. The return policy works as at the mine; with nothing left that gives the objective, the party heads home ("nothing left to hunt").

**Hazards** are few and mild, and never serious, so they never stop the game:
- **An angry bull:** hunting a cow has a `BULL_CHANCE` of hurting the hunter.
- **A slippery pond bank:** each step onto the bank has a `SLIP_CHANCE` of a slip.

An injured resident hunts on, slower, and heals in bed at home.

**The site report.** Before anyone has been there as an expedition: "A meadow a short walk west, with sheep, cows and pigs." Once visited: what all the animals would give if hunted (wool, mutton, leather, beef, porkchops), the herds, the two hazards, and "Open grass: room for the whole party".

**Regrowth.** Each species grows back on its own, one animal every `MEADOW_REGROW` for that species, up to its starting herd. Only wild animals count toward the herd; penned ones don't. New animals wander in at the far west edge. This replaces Slice 2's "the meadow regains 1 sheep every 4 minutes" (#22). Pens and breeding (§5) are how the player gets more.

**Replacing the old trip.** "Send to the meadow" is gone from the resident panel, along with the "Meadow has no sheep left" reason. Wool for more beds comes from the clearing's sheep, then from the meadow adventure.

## 4. Cows and pigs (#138)

**Animals.** Every animal is `{kind: "animal", species, ...}`; the map's `sheep` list holds them all. Cows and pigs live at the meadow only. The clearing keeps its sheep.

| Animal | Drops when hunted | Looks |
|---|---|---|
| Sheep | 1 wool, 1 raw mutton | A woolly white block on a dark face |
| Cow | 1 leather, 2 raw beef | Tall and long, brown with a white middle and muzzle, pale horns |
| Pig | 2 raw porkchops | Low and pink, with a darker snout |

The species are told apart by shape as well as colour. An animal's panel says what it drops.

**The Hunt order** marks every kind in a drag. **Shift-drag** marks only the kind nearest where the drag starts. A queued hunt names the animal ("Hunt a cow").

**Cooking.** The fireplace cooks **cooked beef** (1 raw beef + 1 log) and **cooked porkchop** (1 raw porkchop + 1 log), like mutton, in `COOK_TIME`. Both are meals: the standing order keeps them in stock, the food tally counts them, and an expedition packs them. Hungry residents treat raw beef and porkchops like raw mutton: they're left for the fireplace and eaten only as a last resort.

**Items.** Leather, raw beef, cooked beef, raw porkchop and cooked porkchop, each with a palette colour, a drawing and a tally entry. Leather is a material.

## 5. Pens and breeding (#139)

**Painting a pen.** The **Pen** order, in the Paint menu, is for the meadow only (the Paint menu's Stockpile and Farm plot are for the village only). Dragging paints a pen, fences included: from `PEN_MIN`×`PEN_MIN` to `PEN_MAX`×`PEN_MAX`, on open grass: not on the pond or its bank, an old fence, a tree, the way in or another pen. The drag's outline goes red, with the reason, where a pen can't go; otherwise the hint gives its size, room and sticks. The **gate** is the middle of the side nearest the entrance. Starting a drag on a pen takes it down: its fences come down and its animals go free. The pen's panel shows its fences built, what's in it and how breeding works, with **Take the pen down**.

**Building it.** The pen is a blueprint of blue ghost posts round its edge. Each fence, and the gate, takes `FENCE_STICKS` sticks and `FENCE_TIME` of Build work. Only a party at the meadow builds it, with sticks from its packs: a member takes as many sticks as they can carry at the entrance, puts up the nearest fences, and puts what's left back in the packs. A fence stands like rock; the gate lets people through but never animals. When the last one is up, "A pen is finished" and any animal inside is penned. Room is one animal for each cell inside.

**Leading animals in.** The **Lead to a pen** order, in the Gather menu once a pen is painted on the map in view, marks animals with a blue loop (a click or a drag; clicking a marked one unmarks it). Hunting a marked animal unmarks its lead, and the other way round. A party member at the meadow catches a marked animal, walks it to the gate of the nearest finished pen with room, and lets it in. Penned animals stay inside; wild ones keep out.

**Breeding.** Two grown animals of one kind in a pen, fed `FEED_WHEAT` wheat each from the packs, have a young one after `BREED_TIME` (a wheat-coloured heart shows over each until then), if the pen has room. A pair that bred can't be fed again for `BREED_COOLDOWN`. The young (lamb, calf, piglet) are drawn smaller, grow up in `GROW_TIME`, and **can't be hunted** till then. Breeding and growing go on whether or not anyone is there.

**The party's order of work** at the meadow, under any objective: pack what the objective still needs, build fences, lead marked animals in, feed pairs, hunt what's marked, then pack the rest. The objective's own hunting leaves penned animals alone.

**Tend the pens.** A second kind of meadow objective, offered once a pen is painted: **Tend the pens**, with **Keep N of each** instead of a number to bring back. The party builds, leads and feeds as above, and hunts only the penned animals over N of each kind (grown ones not waiting to breed), packing their drops. It comes home, "the pens are tended", when nothing's left to do. Tending needs no cargo room.

**Packing for the pens.** The meadow planner adds **Sticks for fences** and **Wheat to feed pairs**, filled in with what the pens need now ("the pens need 12 sticks", "1 pair can be fed now, for 2 wheat"). Sticks and wheat are packed at the board like meals, take pack room like any supplies, and are carried as the expedition's **supplies**, apart from the meals. What's left comes home and is unpacked.

**Stuck reasons** at the meadow, in the dim Waiting tier: "The pens need 12 sticks more. Pack them next time" and "No finished pen has room for the animals marked to lead".

## 6. Leather armor (#140)

**Pieces**, made at the bench from leather, as **Craft** work like anything queued by hand (in line with #134). The Toolsmith's spares don't cover armor.

| Piece | Leather | Slot | Guard |
|---|---|---|---|
| Leather cap | 5 | head | 5% |
| Leather tunic | 8 | chest | 15% |
| Leather trousers | 7 | legs | 10% |
| Leather boots | 4 | feet | 5% |

**Wearing it.** Each resident has one slot per piece. A resident in the village with a slot empty walks to the nearest piece for it lying about or stockpiled and puts it on, like picking up a tool. Each piece is one to a cell, with its uses, like a tool. The resident panel's **Armor** row gives the guard ("20% guard", ", full set") and each piece's uses; the Tools and armor dropdown (§7) lists it too. Worn armor tints the model: brown boots, trousers, a tunic over the shirt and a cap.

**What it does.** When a hazard strikes someone (a cave-in, a fall, an angry bull, a slip):
- each piece worn takes the blow and loses a use; a piece used up wears out ("Ada's leather tunic wore out.");
- the armor turns aside its guard's share of injuries (the guards add up, 35% for a full set): "Ada's armor turned aside a cave-in.";
- a **full set** also multiplies the chance an injury is serious by `FULL_SET_SERIOUS`.

**The planner** shows the party's armor against the hazards: "Armor against the hazards: Ada 15%, Tomas none. It turns aside that share of injuries."

**Later:** iron armor and Protection enchantments (brief §9) build on this.

## 7. The tally bar's groups (#141)

The tally bar shows a total per **group**, each a button: **Building** (logs, planks, sticks, cobblestone, rails, minecarts), **Food** (meals, raw meat, wheat, berries), **Tools and armor**, **Animal goods** (wool, leather) and **Ores** (coal, iron ore, iron). Each item names its group in `defs.gd`. A group shows once one of its items has turned up (or a building or recipe waits for one); Tools and armor always shows.
- **Food** reads "Food  6 meals · 2 raw": meals on hand (bread and every cooked meat) and raw meat to cook, apart. It's yellow when there are fewer meals than residents.
- **Hovering or clicking a group** opens its dropdown under it, listing each item with its count and how many lie loose, and a **Pin** button. Food's adds meals on hand, raw meat to cook and berries on bushes. Tools and armor's is Slice 1's Tools dropdown, with what each resident wears and spare armor. The dropdowns open and close like Slice 1's Tools list (#90): a click pins one open; a click elsewhere or Esc closes it.
- **Pinned items** (up to `MAX_PINNED`) show in the bar on their own, before the groups. Pins are a view preference, kept with the key bindings, not in game saves.

## 8. The playtests (#142)

**The bot**, `tests/playtest_slice35.gd`, plays from a Slice 3 village (`tests/fixtures/slice3_village.save`) through pushed input: it opens each tally group's dropdown and checks its counts, pins logs, paints a pen at the meadow and marks two cows to lead, picks the meadow from the adventures list, plans a trip for beef with the pen's sticks and 2 wheat, packs and departs. At the meadow it marks a pig to hunt; the party builds the pen, leads the cows in, feeds them and hunts; a calf is born. Home, it unloads, cooks beef, crafts a leather tunic and sees it worn, then plans a mine trip, checks the planner's protection line, and runs it. Every stall must name its fix.

**The hand playtest** is a checklist like #51's, on #142: every item of §1 by hand, and every stall understood from its on-screen reason alone.

## 9. Saving

Save format **v20** (shared with Slice 3's deeper levels, #132):
- **Animals** carry their species. Older saves' animals are all sheep.
- **The meadow** is a map of its own, with its animals and each species' regrowth time. An older save gets the meadow when it loads, known if the old mine is. What was left of Slice 2's off-map meadow carries over: the new map keeps that many sheep.
- **Anyone away on Slice 2's timed meadow trip** is home at the meadow signpost, with the wool and raw mutton they'd have brought back set down beside it.

Save format **v21** (#139, #140):
- **Pens** are saved with their map: each pen's edge, gate and the fences built, and the map's fences and gates. Penned animals carry their pen; fed ones when they were fed; those resting from breeding when they can be fed again; the young when they grow up. Who's leading which animal isn't saved: the party catches it again.
- **Armor** each resident wears, with its uses; armor lying about keeps its uses, like tools.
- **An expedition** carries the sticks and wheat it planned and its supplies.
- **Older saves:** no pens, nobody wears armor, and an expedition already planned or out packs no sticks or wheat.

## 10. Tuning table (provisional)

| Name | Value | Meaning |
|---|---|---|
| Meadow size | 24×24 | Cells (its layout is hand-laid in `game/sim/meadow.gd`). |
| Herds | 9 sheep, 6 cows, 6 pigs | At the start, and the most the meadow holds of each. |
| `MEADOW_WALK` | 30 s | The walk between the west signpost and the meadow, each way. |
| `MEADOW_REGROW` | sheep 240 s, cows 300 s, pigs 180 s | Seconds for a species to regain one animal. |
| `BULL_CHANCE` | 0.15 | Chance hunting a cow hurts the hunter (never seriously). |
| `SLIP_CHANCE` | 0.03 | Chance of a slip each step onto the pond's bank (never serious). |
| `ANIMAL_DROPS` | sheep 1 wool + 1 mutton; cow 1 leather + 2 beef; pig 2 porkchops | What each animal drops when hunted. |
| `FOOD_VALUE` | raw beef 20, raw porkchop 20, cooked beef 60, cooked porkchop 60 | Hunger a food restores. |
| Cooked beef, cooked porkchop | 1 raw meat + 1 log | At the fireplace, in `COOK_TIME` (3 s). |
| `PEN_MIN`, `PEN_MAX` | 4, 8 | A pen's smallest and largest side, fences included. |
| `FENCE_STICKS` | 1 | Sticks for each fence or the gate. |
| `FENCE_TIME` | 2 s | Build work to put one up. |
| `FEED_WHEAT` | 1 | Wheat each animal of a pair eats when fed. |
| `FEED_TIME` | 2 s | To feed a pair. |
| `BREED_TIME` | 30 s | From feeding a pair to its young one. |
| `BREED_COOLDOWN` | 300 s | Before a pair that bred can be fed again. |
| `GROW_TIME` | 240 s | For a young animal to grow up. |
| Leather armor | cap 5, tunic 8, trousers 7, boots 4 leather | At the bench, as Craft work. |
| `ARMOR_GUARD` | head 0.05, chest 0.15, legs 0.1, feet 0.05 | Share of hazard injuries each piece turns aside. |
| `FULL_SET_SERIOUS` | 0.5 | A full set multiplies the chance an injury is serious by this. |
| `ARMOR_USES` | 8 | Hazards a piece takes before it wears out. |
| `MAX_PINNED` | 4 | Items pinned to the tally bar. |


## The cargo priority list (#185)

A plan carries a **ranked list** of what to bring back (`plan.list`: rows `{item, on, n}`, `n` 0 for "as much as fits"), instead of one target. `plan.target` stays, kept in step by `Sim.sync_target`, as the first row that's on with an amount, for what shows only one item. Tending the pens (§ pens) has no list.
- **Defaults and memory.** A place with no remembered list starts from `Tuning.CARGO_DEFAULTS` (the old mine: iron, coal, then cobblestone as much as fits; the meadow: wool 6, leather, then meat), kept to the items the village knows the place gives. Confirming a plan stores its list in `sim.cargo_lists[dest]`; the next plan starts from it, and an item newly known joins at the bottom with `new` set. Per level filtering and a toast for a newly found item aren't built yet.
- **The planner.** The Bring back section is the list: a tick (off is left behind), the name, − amount + (Max at 0), ▲ ▼. The packs' bar shows the wanted amounts against the room.
- **Packing.** The party stows only items that are on, best row first; the room the packs keep for the rows above an item is respected. A better item turning up when the packs are full **swaps out** the lowest-priority cargo, which is set down at the entrance as a stack (`Sim.swap_candidate`), and "packs full" waits while a swap is possible.
- **Marking.** `_mark_objective` goes down the list: the first row that wants more gets its nearest blocks (or animals) marked, up to the party's size. A row with an amount that isn't packed yet holds the rows below it back, as the old single target did; once it's packed (or for a row set to Max) the marking moves down.
- **Coming home.** "Target reached" is every row with an amount packed; at least one such row is needed, and Max rows never block it.
- **Saving:** v34 keeps `cargo_lists`; a trip in progress turns its old target into a one-row list with the rest of its place's items at Max.

## Clear the level (#188)

A mine plan can be a **clearing** one (`plan.clear`, a toggle above the cargo list, off by default; not offered at the meadow or for tending the pens). While it's on, `cargo_rows` makes every row "as much as fits", so there's no target and "Target reached" can't happen.
- **Marking.** The party works every block of what the list asks for, nearest the entrance first, never a block under a known loose ceiling, and the packs fill by the list (§ cargo priority list).
- **A cleared level** is one where `_nothing_left()` holds: nobody busy, nothing marked or worth marking that can be reached, nothing lying about to pack. Then, after the packs, food and injuries have had their say, `_clear_step` takes over: with the door reached the party goes down (`go_down`, the objective carried over); otherwise it marks the way to the door (never through a loose ceiling) and someone goes to look. Reaching the door in a clearing trip goes straight down with no `_ask("door")`. A way down blocked by a loose ceiling sends the party home, "the level is cleared".
- **Report.** The party panel shows "Clearing the level: N blocks left" (`Sim.level_left`).
- **Saving:** v35 adds `clear` to a trip in progress, false for every older one.
