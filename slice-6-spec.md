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

## 7. The four enchantments (#167)

Each enchantment changes only its own number, by the item's type (`Defs.ITEMS[type].ench`):

| Enchantment | Effect | Where |
|---|---|---|
| **Efficiency** | Work **×1.3** (`EFFICIENCY_SPEED`): chopping, breaking and extraction at sites. | The tool in the worker's hand (axes, pickaxes) |
| **Unbreaking** | Wear **×0.5** (`UNBREAKING_WEAR`): the item loses a use every other time, counted in the item's own running tally so a game replays the same. | Tools, swords and armor |
| **Protection** | **−30%** chance of a creature injury (`PROTECTION_CUT`), for each piece worn (they multiply). | Armor, on creature blows (#151) |
| **Fire protection** | **−50%** chance of harm from fire and lava (`FIRE_PROTECTION_CUT`), for each piece worn. | Armor, on burns and lava (#149) |

- They **stack with everything else** as the numbers say: Efficiency divides the work time before the resident's skill does (so a level 3 Mason with an Efficiency pickaxe is 1.3× the speed of the same Mason with a plain one); armor's own guard share, and a full set's lower chance of a serious injury, apply as before after a hazard lands.
- **Rail stays rail:** a finished line changes only travel; Efficiency is the item's effect, not the route's, and a test guards both.
- **Shown** on the item's name wherever a tool is listed: "Iron pickaxe · Efficiency (mines 30% faster)", "Leather tunic · Protection (30% fewer creature injuries)", and on the workshop's panel, with each recipe's effect.
- **No save change:** an enchanted item is an item type, and the effects read it.

## 8. The portal line (#168)

- **Village side:** a **portal station** (Build menu, once the portal stands) planned **beside the portal**, within `PORTAL_STATION_REACH` (6) cells of the frame and not on its staging area. 6 planks and 4 cobblestone, built by residents like any station. It **reserves a 3×3 plot** for the freight loader (#172). One only.
- **Nether side:** a Build objective, **The portal line from the landing**, once the station is planned. The party carries what's left: `PORTAL_LINE_RAILS` (6) rails, laid along `NetherLanding.TRACK` from the portal's far side to the landing station, and the **landing station** if there isn't one (6 planks, 4 cobblestone). Up to what three can carry past their meals.
- **Shared station:** the landing station sits **beside the shelter** (`NetherLanding.STATION_AT`) and is the Nether line's landing station too: whichever line builds it, the other finds it built. Two lines meet there, with no switch; a cart stays on its own line.
- **Complete** when the village station is built, all six rails are laid and the landing station stands (`pline_complete()`). A party then **rides** the rails on the landing at the cart's speed.
- **Saving:** `portal_line: {laid}` (v54). The village station is a site; the landing station is the Nether line's flag.

## 9. The freight cart (#169)

- **Ordering:** once the portal line is complete (§8), the portal station's panel offers **Order a freight cart**. A hauler carries a minecart from the stockpile to the station and parks it (`freight.state` "ordered" → "home"). One cart.
- **State:** `freight` = {state: ordered / home / going / unloading / returning, pos (0 at the village station, 1 at the landing station), load, approved, acc}. It carries goods and no riders.
- **Approval:** the cart **never departs on its own**. **Approve departure** (the station panel) sets `approved`; it leaves once the portal is lit, and the approval is used up with the trip. Cancel approval takes it back. (The dispatcher, #173, will give the same go-ahead from a device.)
- **The trip:** `FREIGHT_TRIP_TIME` (14 s) one way, the portal `FREIGHT_CROSS` (0.3) of the way along; drawn moving along the village side and then the landing's rails with its load stacked on it. At the landing it unloads into the **shelter's cache** at `LOAD_RATE`, up to `CACHE_CAPACITY` (60) items in all, then returns empty. Nobody needs to be in the Nether.
- **Stuck reasons:** "Freight cart: waiting for approval" (loaded, at the station); "the portal is unlit" (at the station approved, or held at the crossing); "the cache is full" (or "there's no shelter to unload into"); "needs a minecart from the village".
- **Saving:** `freight` (v55). Until the loader (#172) there's no way to put goods on it in play; tests load it directly.

## 10. Redstone devices and dust (#170)

- **Devices** are small buildings on the village map, ready-made, each costing redstone dust, quartz and stone (provisional): the **cache sensor** and **condition** (2 redstone, 1 quartz, 2 cobblestone each); the loader (§12) and the dispatcher (#173) join them. Place from the Build menu once the portal station is planned. Residents build them like any building.
- **Dust lines** are drawn from a device's panel (**Wire to the …**, the Wire order): one device's output to another's input. A sensor has no input; a device can't feed itself; one line per pair and direction. The line takes a path of cells (along the first device's row, then down the second's column, skipping built cells). A resident with Build on fetches `ceil(cells / DUST_PER_REDSTONE)` redstone dust from the stockpile and lays the cells one at a time (`DUST_TIME` each), visibly. **Cut** in either device's panel takes the line up; so does demolishing a device.
- **Signal:** on or off, instantly along a *fully laid* line (`wires`: `{id, from, to, cells, laid}`). A device's input is on when any line into it is on. Evaluated every half second; a few passes settle a chain (no custom circuits, no gates or timers; #29 stays open).
- **Inspector:** a device's panel says **On** or **Off** and **why**, tracing back through its inputs: "On: Cache food 6 < 10, and the portal is lit". Powered devices and dust glow bright red, unpowered ones dark.
- **Redstone overlay** (key `O`, rebindable): dims the village and lifts the devices and dust above it, with a beacon on each device and the unlaid cells of a planned line shown faintly.
- **Saving:** devices are sites with `cfg`, `out` and `why`; `wires` is saved (v56).

## 11. The cache sensor and the condition (#171)

- **Cache sensor:** reads the shelter's cache from the village (a remote reading, nothing moves). It watches one item (`SENSOR_ITEMS`: meals ("food"), iron ingots, planks, cobblestone) and is **on while the count is below its threshold** (starts at `SENSOR_BELOW`, 10; set with − / + in its panel). Its panel shows the cache's current value. No shelter yet: off, "no shelter on the landing to read".
- **Condition:** passes its input only while a chosen fact holds: **the portal is lit**, **the freight cart is home**, **the loader is idle** (cycled from its panel). With nothing wired in: "Off: nothing wired in"; input off: "Off: its input is off (…)"; fact false: "Off: the portal isn't lit".

## 12. The freight loader (#172)

- **The upgrade:** the **freight loader** (Build menu) is built on the plot the portal station reserved (§8): anywhere on that 3×3 not under the station, one only, once the station stands. 3 redstone dust, 1 quartz, 4 cobblestone. It is a device (§10) whose output means **loaded**.
- **Freight list:** what a full load is, `cfg.list`, starting at `FREIGHT_LIST` (10 bread, 2 iron ingots; provisional) and changed with − / + in its panel (bread, iron ingots, planks, cobblestone), up to `FREIGHT_CAPACITY` (30) items in all.
- **When powered** (an input on) and a freight cart is **home** at the station, residents carry what the cart lacks from the stockpile and set it on the cart (visible: carried and stacked on it, up to six boxes). A load is never conjured. When the cart holds the whole list, the loader is **on**: "On: loaded, 10 bread, 2 iron ingots; powered because …". Unpowered: "Off: unpowered, nothing wired in" / "its input is off (…)". Nothing to load onto: "Off: no freight cart at the station".
- **Stuck reasons:** "Loader: needs 6 more bread" (the stockpile and hands together fall short), "Loader: no freight cart at the station", "Loader: no one with Haul on" (no one in the village free to carry).
- **The condition's "the loader is idle"** is false while a powered loader still has the cart to fill.
- **Saving:** v57 (the list is in the loader's `cfg`, the progress is the cart's `freight.load`).

## 13. The dispatcher and departure approval (#173)

- **Dispatcher:** a device (2 redstone dust, 1 quartz, 2 cobblestone) that stands **within `DISPATCHER_REACH` (4) cells of the portal station**; one only. Wire the loader into it: it is on while its input ("loaded") is on.
- **The request:** with the dispatcher powered and a loaded cart at the station, it raises a **departure request** (`freight.request`): a toast, "Supply cart ready for the Nether cache. Approve?", that focuses the station, and "Freight cart: waiting for approval: the dispatcher asks you to approve" in the stuck list. **It does not pause the game** and isn't in `sim.pending`.
- **Approve** (station panel) sends the cart as in §9; **Decline: unload it** puts the load back in the stockpile and stops the loader and the dispatcher until the chain's signal drops (the cache recovers) and rises again. Approval stays manual: nothing leaves on its own.
- **The chain:** cache sensor (food < 10) → condition (the portal is lit) → loader → dispatcher; low cache, load, approve, deliver, unload, return. Without a dispatcher the station's Approve button still works.
- **Saving:** `freight.request` and `freight.declined` (v58).

## 14. Tuning table (provisional)

Each build issue adds its rows.

| Name | Value | Meaning |
|---|---|---|
| `ORE_YIELD` lapis / redstone | 3 / 3 | Items a block drops. |
| `ORE_PICK_TIER` lapis / redstone | 3 / 3 | An iron pickaxe or better. |
| Lapis and redstone | from level 3 | 2 blocks each, more the deeper, 5 at most. |
| `ENCHANT_TIME` | 12 s | Working one enchantment at Enchanter level 1. |
| Costs | see §6 | In `Defs.ENCHANTS`: lapis plus one ingredient. |
| `EFFICIENCY_SPEED` | ×1.3 | Work speed with an Efficiency tool. |
| `UNBREAKING_WEAR` | ×0.5 | Wear an Unbreaking item takes. |
| `PROTECTION_CUT` | −30% | Chance of a creature injury, per Protection piece. |
| `FIRE_PROTECTION_CUT` | −50% | Chance of harm from fire and lava, per Fire protection piece. |
| `PORTAL_LINE_RAILS` | 6 | Rails on the landing side of the portal line. |
| `PORTAL_STATION_REACH` | 6 | Cells from the portal frame the village station may stand. |
| `FREIGHT_TRIP_TIME` | 14 s | One way along the portal line. |
| `FREIGHT_CROSS` | 0.3 | How far along the trip the portal is. |
| `CACHE_CAPACITY` | 60 | Items the shelter's cache holds in all. |
| `DUST_PER_REDSTONE` | 4 | Cells of dust one redstone dust lays. |
| `DUST_TIME` | 1.5 s | Laying one cell of dust. |
| `SENSOR_ITEMS` | food, iron ingot, plank, cobble | What a cache sensor can watch. |
| `SENSOR_BELOW` | 10 | A new sensor's threshold. |
| `FREIGHT_LIST` | 10 bread, 2 iron ingots | A new loader's freight list. |
| `FREIGHT_CAPACITY` | 30 | Items a freight cart carries. |
| `DISPATCHER_REACH` | 4 | Cells from the portal station the dispatcher may stand. |
| Loader cost | 3 redstone, 1 quartz, 4 cobble | In `Defs.TEMPLATES`. |
| Device costs | 2 redstone, 1 quartz, 2 cobble | Sensor and condition, in `Defs.TEMPLATES`. |
