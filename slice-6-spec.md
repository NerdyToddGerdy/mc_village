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

## 5. The enchanting workshop and the Enchanter (#165)

A village building, 1×1, of an **obsidian table with a lectern**: `4 obsidian, 2 diamonds and 6 planks` (stage "Workshop"). The Build menu lists it once an enchanted book has been found (`stats.book_found`) or a workshop stands. It reserves a plot for a later **library**.

- **Enchanter** is a job like Slice 2's: levelled from practice (a point for each task finished), on the Jobs board with its on/off and priority, and with the workshop as its workstation (`JOB_STATIONS`), one resident to a workshop. Ada does everything. No traveler arrives as one (`SKILL_POOL`). Every resident starts at the first level.
- **Learning:** an Enchanter (or Ada) carries a loose enchanted book from the stockpile to the workshop, where it **learns that recipe permanently** (`site.known`) and the book is **used up**. Only a book that teaches an unknown recipe is carried: a second copy stays where it is. The workshop's panel lists each recipe, known or "unknown: needs its book", with its cost and what it does.
- **Stuck reasons:** "Workshop needs 4 more obsidian" while it's being built; "Enchanter: No one is an enchanter" when a book or an order waits and no one has the job; "Book: waiting to be carried to the workshop" beside the book itself.
- **Saving:** v52. Every resident gets `enchant` at no experience; the workshop site keeps `known` and `orders`.

## 6. Enchanting an item (#166)

At the workshop an **Enchanter** puts a **known** enchantment on a tool, a sword or a piece of armor lying in the stockpile. Select the workshop: each known recipe lists the item types in the stockpile it can go on, and a click orders it. Unknown recipes are listed with "unknown: needs its book".

| Enchantment | Cost | Goes on |
|---|---|---|
| Efficiency | 2 lapis, 1 quartz | Axes and pickaxes |
| Unbreaking | 2 lapis, 1 iron ingot | Tools, swords and armor |
| Protection | 3 lapis, 2 iron ingots | Armor |
| Fire protection | 3 lapis, 1 magma cream | Armor |

- **An enchanted item is an item type of its own** (`Defs.ITEMS`, built from `BASE_ITEMS`): "iron_pick+efficiency" is the iron pickaxe with `ench` set, named "iron pickaxe of Efficiency". So wear, carrying, dropping, packing for a party and saving all work as they always have, and **an item can hold only one enchantment**: a variant can't be enchanted again, and no variant has two. It's drawn with a violet spark, and the tally bar groups it with the other tools and armor.
- **The work:** the Enchanter fetches what the first order needs (the item, the lapis, the ingredient), one delivery at a time, then works it (`ENCHANT_TIME`, quicker at higher Enchanter levels). The item comes out where the workshop stands, keeping its wear, and haulers take it to the stockpile. A queue of orders is worked in turn, and each can be cancelled.
- **Stuck reasons:** "Enchant: needs 2 lapis" (or whatever's missing), the workshop's "No one is an enchanter", and a refusal at the order: "Enchant: recipe unknown", "Enchant: item already enchanted", "Enchant: Efficiency can't go on that".
- **Competition for the best gear** (brief §9): enchanted gear is ordinary gear in the stockpile, so a resident takes an enchanted tool over a plain one of the same tier, a party's packs take enchanted spare pickaxes, and the planner and the Equip lists show its name. What a party carries leaves the village.
- **Saving:** v53. An enchanted item saves as its type; the workshop keeps its `orders` and what it holds.

## 7. Tuning table (provisional)

Each build issue adds its rows.

| Name | Value | Meaning |
|---|---|---|
| `ORE_YIELD` lapis / redstone | 3 / 3 | Items a block drops. |
| `ORE_PICK_TIER` lapis / redstone | 3 / 3 | An iron pickaxe or better. |
| Lapis and redstone | from level 3 | 2 blocks each, more the deeper, 5 at most. |
| `ENCHANT_TIME` | 12 s | Working one enchantment at Enchanter level 1. |
| Costs | see §6 | In `Defs.ENCHANTS`: lapis plus one ingredient. |
