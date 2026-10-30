# Slice 6 Spec — Specialization and Automation

Companion to `block-village-design-brief.md` and the Slice 1–5 specs. Slice 6 builds on everything in Slices 1–5 (and 3.5); this spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table at the end. Issues not built yet carry their own rules on GitHub; each adds its section here when it's built.

Tracking issue: #15. Decisions settled with the owner (2026-10-21), and recorded in the brief (§6, §9, §10, §13, §14):

| Question | Decision |
|---|---|
| Discovery (#28) | **Enchanted books from expeditions.** Rare salvage (the fortress delve, deep mine chests) and the piglin trade table. Bringing a book home teaches the workshop its recipe permanently. |
| Cost (#28) | **Lapis plus one ingredient per recipe.** Lapis from a deep mine level. Ingredients (provisional): Efficiency takes quartz, Unbreaking iron, Protection iron, Fire protection magma cream. |
| Enchantments | **Efficiency, Unbreaking, Protection, Fire protection.** One slot per item, no rerolls. |
| Workshop | A **new enchanting workshop** with an **Enchanter job**, built from obsidian and diamonds. It reserves a plot for a later library upgrade. |
| The redstone chain | **Low Nether cache → supply cart.** A sensor on the shelter cache (#152) notices low provisions, a condition decides, a loader at the village prepares freight, and once the player approves, the cart delivers it. |
| Freight | **The first unmanned cart**, with **manual departure approval**. Automatic departure stays later. |
| Route | **A portal line:** village station by the portal → through the portal → a landing station by the shelter, shared with the Nether line (#159). Two lines meet at a station; no switch. |
| Redstone (#29) | **Ready-made devices only:** sensor, condition, loader and dispatcher, joined by visible dust lines the player draws. Each device says why it's on. Custom circuits and wider network management stay out. |

Still open: #29 (until Slice 6 has been played), #30 (terminology), #19, #20, #26, #22, #66.

## 1. Scope and done criteria

Slice 6 is done when, from a Slice 5 village, a player can:

- [ ] Bring back lapis, redstone and an enchanted book.
- [ ] Build the enchanting workshop and learn the book's recipe.
- [ ] Enchant a pickaxe with Efficiency and see it mine faster, while rail still doesn't speed mining.
- [ ] Enchant armor and send it with a Nether party, leaving the village without it.
- [ ] Build the portal line and a freight cart.
- [ ] Place a cache sensor, a condition, a loader and a dispatcher, and wire them with dust.
- [ ] See a low cache start the loading, approve the departure, and watch the unmanned cart deliver and return.
- [ ] Understand every stall and every powered device from its on-screen reason alone.

## 2. Build order

#163 lapis and redstone in the deep mine; #164 enchanted books; #165 the enchanting workshop and the Enchanter; #166 enchant an item; #167 the four enchantments; #168 the portal line; #169 unmanned freight carts; #170 redstone devices and dust; #171 the cache sensor and condition; #172 the freight loader; #173 the dispatcher and departure approval; #174 the bot and hand playtest.

## 3. Lapis and redstone in the deep mine (#163)

Two more ores from the deep levels' stream of finds (`MineLevels.DEEP_ORES`), placed last so every other level is as it was: **lapis ore** and **redstone ore**, from level 3 (2 blocks, more the deeper, 5 at most each), in plain sight in the rock beside the floor, or in the level's edge wall where a wide level has no other. Each takes an **iron pickaxe or better** (`ORE_PICK_TIER` 3): with less, the stuck list says "Lapis ore needs an iron pickaxe". A block drops **3** `lapis` (lapis lazuli, the common cost of every enchantment) or **3** `redstone` (dust, for the devices, #170). Both are cargo targets once a level has been seen, and the tally bar groups them with the other ores. As with the other finds, a level already made in an older save keeps its layout.

- **Saving:** v50.

## 4. Enchanted books (#164)

An **enchanted book** is an item that names one enchantment: `book_efficiency`, `book_unbreaking`, `book_protection` and `book_fire_protection` (`Defs.ENCHANTS` holds each enchantment's data). The same number always gives the same book, from the game's seed.

| Source | Books | Weighted |
|---|---|---|
| **Fortress salvage** (#157) | One in the chest, on top of the rest | Protection and Fire protection 3, Efficiency and Unbreaking 1 |
| **Deep mine chests** | A chest block in the rock, from level 3 (one, then one more every 4 levels, 2 at most), broken with any pickaxe, drops its book | Efficiency and Unbreaking 3, Protection and Fire protection 1 |
| **The piglin table** (#156) | Efficiency for 8 gold ingots, Unbreaking for 6: the first two rows of the table, shown before departure | Fixed |

- **A level's chests** show in its report (once seen) and the planner as cargo targets, one row for each book.
- **Carried home** as cargo and stored in the stockpile like anything else.
- **The discovery pause:** the first book found, from any source, stops the game once, says what it teaches ("... would teach that recipe for good"), and is carried on.
- **Saving:** v51. Book items, chest blocks with their `book`, and `stats.book_found`.

## 5. Tuning table (provisional)

Each build issue adds its rows.

| Name | Value | Meaning |
|---|---|---|
| `ORE_YIELD` lapis / redstone | 3 / 3 | Items a block drops. |
| `ORE_PICK_TIER` lapis / redstone | 3 / 3 | An iron pickaxe or better. |
| Lapis and redstone | from level 3 | 2 blocks each, more the deeper, 5 at most. |
