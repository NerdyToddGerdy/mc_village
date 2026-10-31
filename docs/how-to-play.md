# How to play Block Village

You start with one person, Ada, in a forest clearing. She gathers wood and stone, crafts tools and builds the first houses. Travelers arrive when there's a bed for them, and the village grows from there.

You don't steer anyone's every swing. You **mark work** (trees to chop, sheep to hunt, ground to farm) and **place blueprints**, and residents take the jobs on themselves. When anything stalls, the game says why.

This guide covers the game as it plays today: the founding (Slice 1) and the working village (Slice 2). Every number in it is provisional and may change as the game is balanced.

## Starting the game

You need Godot 4.7 to run the game; the README's [Running the game](../README.md#running-the-game) section says how to install it and launch the game. It opens on the main menu: choose **Play** to start a new village, or **Load game** to carry on with a saved one.

## The screen

```
┌──────────────────────────────────────────────────────────────┐
│ Building 54 ▾  Food 6 meals ▾  Tools and armor 3 ▾  Jobs  ‖ 1× │
│ The founding  3 of 11                         Stuck (2) ▴    │
│ Next step and a hint                          ⚑ House …      │
│                                                              │
│                     the clearing                             │
│                                                              │
│ ┌ Selected ──────┐                       ┌ Craft panel ────┐ │
│ │ Ada            │                       └─────────────────┘ │
│ └────────────────┘     Gather ▸  Paint ▸  Build ▸  Craft     │
└──────────────────────────────────────────────────────────────┘
```

- **Top left:** what's in the village, in groups: **Building**, **Food**, **Tools and armor**, **Animal goods** and **Ores**. A group shows up once one of its items has. **Food** counts meals on hand and raw meat still to cook, and turns yellow when there are fewer meals than residents. Hover over a group, or click it to keep it open, for a list of each item with how much is lying loose; **Tools and armor** lists everyone's tools, armor and the spares. **Pin** an item there (up to 4) to keep its count in the bar on its own; pins are saved with your key bindings. **Jobs** opens the village jobs board.
- **Below that:** the **goals panel**, which walks you through the founding one step at a time. Once the founding is done, it folds to a small "Founding ✓".
- **Top right:** pause and speed, and the **stuck list**, which shows anything that can't go on and why.
- **Bottom left:** whatever you've selected: a resident, a building, a tree, a farm plot.
- **Bottom right:** the **orders toolbar**, and the Craft panel when it's open.

**Other maps.** Expeditions go to places off the map, such as an old mine and a meadow. Once the village knows of one, a switcher in the top bar shows **Village**, **Old mine** and the rest (Tab switches), and a dim line under it says what a party there is doing, or how long until it gets there. Each map keeps its own view. Stockpiles, farms and buildings stay in the village.

Marks drawn on the world show what's been ordered. Chalk-white means selected, red means mine or hunt, green hatching is a stockpile, wheat rows are a farm, a blue dashed outline is a blueprint, and a yellow flag means something is stuck.

## The founding, step by step

The goals panel leads you through these steps. Each one unlocks the next.

1. **Chop a tree.** Choose **Gather → Mine** (or press **X**) and click a tree. Ada fells it by hand, slowly. A tree drops 4 to 6 logs.
2. **Paint a stockpile.** The logs are lying loose. Choose **Paint → Stockpile** (Z, then 1) and drag over open ground. Residents carry what they gather there.
3. **Build a crafting bench.** Choose **Build → Crafting bench** (or press **T**) and click open ground. It takes 4 logs.
4. **Craft an axe and a pickaxe.** Open the bench (click it, or press **C**) and queue a wooden axe and a wooden pickaxe. The bench queues their planks and sticks first by itself, marked **A**. An axe chops 2.5× faster than bare hands.
5. **Break a boulder.** With a pickaxe, Ada can mine boulders for cobblestone. Each one gives 6.
6. **Hunt sheep for wool.** Choose **Gather → Hunt** (or press **G**) and mark sheep. Each one gives 1 wool and 1 raw mutton. The clearing's 3 sheep give the 3 wool a bed needs.
7. **Build Ada's house.** Choose **Build → House** (or press **H**), and press **R** to turn the door. The house goes up in stages as materials arrive, and its bed is the last stage.
8. **Build a fireplace.** Choose **Build → Fireplace** (or press **K**). It costs 6 cobblestone, and cooks the mutton into meals: a trip off the map needs one for the walk home.
9. **Build an expedition board.** It's in the Build menu once Ada's house is up. The second bed needs more wool than the clearing has, and the board plans trips off the map.
10. **Fetch wool from the meadow.** Click the meadow's signpost on the west edge, or the board. Send Ada for wool, take as many meals as the fireplace has made, click **Start packing**, then **Depart**. The village waits while she's away.
11. **Build a second house.** Its bed is what brings a traveler.
12. **Welcome a traveler.** Tomas, a lumberjack, arrives a little while after the second bed is ready.
13. **Build Tomas a chopping block.** Choose **Build → Chopping block** near trees. Tomas fells the trees around it on his own, while Ada does everything else.

Each step shows a line under its hint saying **why** it matters.

### The village

When the founding is done, a second chapter of goals follows in the same panel, each with a hint and a why:

1. **Paint a farm plot.** **Paint → Farm plot**, on open grass. A farmer plants and harvests it: the village's steady food. Farmers stop once the village has 20 wheat, so it doesn't crowd the stockpiles: change that with − and + on the composter's panel or the jobs board. The stuck list shows "Farm: enough wheat" as a waiting reason, and the crop waits ripe on its plot.
2. **Cook a meal.** Queue bread or cooked mutton at the fireplace. Cooked food fills a resident for much longer.
3. **Give a second resident a workstation.** Build another workstation (a mason's bench, composter and so on) and give someone that job from the Jobs board. Tomas's chopping block was the first.
4. **Bring iron ore home from the old mine.** Plan a trip at the expedition board. Smelted with coal at the fireplace's furnace, iron makes tools that last more than twice as long as stone.

When both chapters are done the panel folds to a green **The village ✓** chip.

### The village book

The goals panel's **Book** button (or the chip, once the chapters are done) opens the village book in its place. Its **Goals** page lists every step with its why. Every other page is a building or zone: what it's for, who works it, what it grows into and what goes wrong without it. A page shows once its building can be built (the expedition board once Ada's house is up, the pen once the board is built, the road once a party has been to the old mine). Select a building and click **? About the…** to jump to its page. Esc or **Close** shuts the book.

## Paths

The ground wears where residents walk. Busy routes turn to worn grass, then a dirt path, then a darker packed path, and residents walk faster on paths and choose them when they're not much longer. A path that nobody walks any more slowly grows back to grass. Buildings, stockpiles and farms don't wear, and putting one on a path clears it. Only the village has paths, not the mine or the road.

## Giving orders

There are two ways to get work done.

**Mark work for anyone.** The toolbar's orders mark the world, and a resident whose job it is takes the work, or Ada, who does everything. Click to mark one thing, or drag a rectangle to mark many. Clicking something that's already marked unmarks it.

| Toolbar | Order | What it does |
|---|---|---|
| **Gather** (E) | Mine (X) | Fell trees and break boulders. Shift-drag marks only trees, Alt-drag (Option on a Mac) only boulders |
| | Chop trees | Trees only |
| | Break boulders | Boulders only. Breaking them needs a pickaxe |
| | Keep | Trees and boulders lumberjacks and stonemasons leave alone on their own rounds (a green ring). They're still worked if you mark them |
| | Hunt (G) | Sheep, cows and pigs. Shift-drag marks only the kind you start on. Shows while there are animals about |
| **Paint** (Z) | Stockpile | Ground where residents store what they gather |
| | Farm plot (P) | Open grass where residents grow wheat |
| **Build** (B) | Crafting bench (T), House (H), Fireplace (K), and each job's workstation | Place a blueprint. R turns it |
| **Craft** (C) | | Opens the Craft panel for your benches and fireplace |

While a toolbar menu is open, **1 to 9** pick its rows, so Z then 1 paints a stockpile. The Gather and Paint buttons show the order that's on, such as "Gather: Hunt". Esc puts the order away.

**To erase** stockpile cells or farm plots, switch that Paint order on and start a drag on a painted cell. The cells that will go show in red. Items on an erased stockpile cell stay where they are and get carried to the rest of the stockpile. Wheat growing on an erased farm plot is lost.

**Right-click a tree, boulder or animal** for a ring of its orders, with or without anyone selected:
- **Chop**, **Break** or **Hunt** marks it for anyone (**Cancel** once it's marked).
- **Chop now**, **Break now** or **Hunt now** sends the residents you've selected straight to it. It only shows with someone selected, and it's greyed when they can't, with the reason below the ring ("Break now: Tomas has no pickaxe").
- **Chop all trees nearby** or **Break all nearby** marks everything of its kind within 4 cells.

Click a wedge, press 1 to 4, or hold the right button, drag to a wedge and let go. The middle names it and what it drops; click it to select it. Esc or a click outside closes the ring.

**Order someone directly.** Select a resident and right-click the ground to send them there. **Shift + right-click** a tree, boulder or animal skips the ring and adds that order to the end of their list. Direct orders come before everything else, whatever their job. They still work while a Gather or Paint order is on.

## Residents

**Selecting.** Click a resident, or press **F** for the next one. Shift-drag a box to select several. Each resident wears their own tunic colour, and hovering over one or selecting them shows their name above their head.

**The resident panel** shows:
- what they're doing;
- their axe and pickaxe, with uses left;
- what they're carrying;
- how hungry they are;
- any orders you've queued for them;
- their **Job**, with a dropdown to change it, and a button to the jobs board.

**Jobs.** Every resident has **one job**: Lumberjack, Stonemason, Haul, Build, Craft, Toolsmith, Farm, Cook or Hunt, or none. They do that job's work, and when there's none they carry loose things to the stockpile. A lumberjack chops trees, and a stonemason breaks boulders and mines ore. **Ada does everything**: whatever's waiting, bench and fireplace work first, then building, then farming, then marked trees, boulders and animals, then hauling. She covers any job nobody has, but she only fells what you've marked.

**Each job needs its workstation.** A resident works their job only from a workstation of their own, one resident to each, so two farmers need two composters. Until there's a free one they haul, and their job reads "Farmer (no composter)". Ada needs none.

| Job | Workstation | Cost |
|---|---|---|
| Lumberjack | Chopping block | 4 planks |
| Stonemason | Mason's bench | 2 planks, 4 cobblestone |
| Build | Builder's table | 4 planks, 2 logs |
| Craft | Crafting bench | 4 logs |
| Toolsmith | Toolsmith's bench | 4 planks, 3 cobblestone (tools are still made at the crafting bench) |
| Farm | Composter | 4 planks |
| Cook | Fireplace | 6 cobblestone |
| Hunt | Hunter's lodge | 6 logs, 2 planks |

A workstation's panel names who works from it ("Tomas's composter"). Giving someone a new job frees their old workstation.

**The village jobs board** (press **J**, or click **Jobs** in the top bar) lists every resident.
- Click a resident's job (for example "Farmer, level 3 ▾") for the **job dropdown**. It lists each job with their level in it, best first, how many residents already have it, and whether a workstation for it is free. Choose one to give them that job.
- The board shows each resident's **level** in every job, with a thin bar of progress to the next. Their own job is lit.
- A column's header counts the residents with that job, and reads "nobody" in yellow when no one has it. When Ada is away, work of a job nobody has waits, and the stuck list says "No one is a farmer".
- **Hunters leave** sets how many wild animals of each kind in the village hunters spare, 2 to start, with − and +. A hunter with a lodge hunts on their own until only that many are left, and the stuck list then says "Hunter: herd at its floor". Animals you mark are hunted anyway, and penned ones are never hunted on a hunter's own.

New residents arrive in the job they're skilled at, and haul until its workstation is built.

**Skills** grow with practice. Every finished task earns a point in its job, and levels 2 to 5 come at 8, 25, 50 and 90 points. There is no top level: the curve goes on (level 6 at 123 points, level 10 at 335), and each level costs more than the last. Each level up to 5 works 15% faster; after that each adds a little less, so speed levels off at about 1.9 times. Some jobs also get better results:

| Job | Better result |
|---|---|
| Lumberjack | An extra log per tree, at levels 3 and 5, and one more at every fifth level from 10 |
| Stonemason | An extra cobblestone or ore per boulder or ore block, at levels 3 and 5 |
| Farm | An extra wheat per harvest, at levels 3 and 5 |
| Haul | Carries one more, at levels 3 and 5 |
| Craft | 5 planks from a log instead of 4, at level 4 and up |
| Cook | Bread from 2 wheat instead of 3, at level 4 and up |
| Toolsmith | Tools last 20% longer per level above 1 |

**New residents** arrive skilled in one job, at level 3, and the toast that announces them says which.

## Lumberjacks, stonemasons and their workstations

A lumberjack or stonemason works whatever you've marked first. With nothing marked, they find their own work around their **workstation**:
- **Chopping block** (4 planks) for lumberjacks, and **mason's bench** (2 planks, 4 cobblestone) for stonemasons. Build them from the Build menu. Each reserves room for a later upgrade.
- **Work area:** the ground it works, painted. A new one starts with the 8 cells around it, shown as a wash of colour while you place it or select it. Select it and choose **Paint area** to change it: drag to add ground, start a drag on painted ground to erase. Ground more than 12 cells from the workstation can't be painted, and two chopping blocks (or two mason's benches) can't share a cell: painting one takes it from the other.
- **The pile:** the cells beside it hold up to 20 logs or cobblestone. Gatherers carry what they cut there first, which saves the walk to the stockpile. Builders and crafters take from it like a stockpile, and anything over 20 goes to the stockpile.
- **Keep-stock target:** set in the workstation's panel ("Keep 20 logs", with − and +). Once the village has that many, its gatherers stop cutting so they don't strip the area for nothing.
- **Left alone:** trees and boulders marked **Keep**, and anything on a building or its reserved plot, a stockpile, farm or pen, or beside a house's door.
- **Processing:** a chopping block also saws planks, 5 from a log (the bench makes 4), and a mason's bench cuts cobblestone into **stone bricks**, 2 for 2. Each keeps a stock, set in its panel ("Keep 20 planks", with − and +), and its gatherer makes more while the village is short. Each also has a tab in the Craft panel, where you can queue more by hand. Stone bricks are for buildings still to come.
- **Replanting:** a felled tree drops a sapling, sometimes two. Lumberjacks plant saplings on open grass in their chopping block's area. A sapling grows into a full tree in about 5 minutes. Until then it can't be chopped.

The workstation's panel and the stuck list say what's holding it up: "No trees in the chopping block's area", "Target reached", "Full", or a stonemason with no pickaxe.

**The mineshaft.** Boulders never come back. Once every boulder on the map is gone, select a **mason's bench** and choose **Dig out a mineshaft** (the button says what's still missing: the boulders, or 6 stone bricks to cut at the bench first). Builders rebuild it with 8 planks and 6 stone bricks, and it keeps its stonemason, queue and work area. From then on the stonemason digs cobblestone from where it stands, slowly (1 every 12 seconds), until the village has as much as the bench is set to keep. It never gives coal or iron: for those, and for stone by the cartload, go to the old mine.

## Materials and stockpiles

Everything is carried. Felled trees drop logs where they stood, and broken boulders drop cobblestone. Residents carry up to 4 of one thing at a time.

Until you paint a stockpile, items stay where they fell, and builders fetch them from the ground. Once there's a stockpile, residents with **Haul** on carry loose items to it. Each cell holds up to 16. If the stockpile is full, the stuck list says so.

**The storehouse** (Build menu: 6 cobblestone, 12 planks and 4 logs) is the main storage once you have one. It holds nothing until you add chests. Craft a **chest** at the bench (8 planks) and a hauler carries it in. Each chest holds 9 stacks of anything, up to 4 chests. Haulers fill the nearest storehouse with room first, and stockpiles take what doesn't fit. Residents fetch what's stored at its door, and its panel lists what's inside. The squares on each chest's lid show what it holds.

**Growing the village.** The map isn't fixed: every 2 residents past the first two earn a **land claim**, and the top bar shows "1 land claim". Choose **Build → Claim land**, and the outline of a strip, 8 cells deep, shows along each edge; the one nearest the cursor is on offer, even with the cursor off the map. Click to stake it. A builder plants boundary stakes (4 sticks), and then the strip joins the village, with its own trees, boulders, berries and a few sheep. Claiming north or west moves everything with it, and the view stays put. The village stops at 64 cells a side.

The top bar counts what you have, with how much of it is still lying loose.

## Crafting and tools

Click a bench or fireplace, or press **C**, to open the **Craft panel**. With more than one, there's a tab for each.

The panel is laid out like a crafting table:
- **Recipe book** (left): one slot per recipe. A dimmed slot with a yellow corner means there isn't enough on hand for one.
- **Grid** (middle): the chosen recipe's ingredients in its pattern. A slot outlined in yellow is something the village is short of. The grid only shows the recipe; residents fetch the ingredients themselves.
- **Result** (right): what it makes. **− Queue n +** sets how many to queue.
- **Queue** (below): what's waiting to be made, first to last. Click a slot to remove it. **T** marks a toolsmith's spare and **A** an automatic ingredient.
- **On hand:** how many of each ingredient the village has.

| Recipe | Takes | Makes |
|---|---|---|
| Planks | 1 log | 4 planks |
| Sticks | 2 planks | 4 sticks |
| Wooden axe or pickaxe | 3 planks, 2 sticks | 1 tool, 10 uses |
| Stone axe or pickaxe | 3 cobblestone, 2 sticks | 1 tool, 25 uses |
| Iron axe or pickaxe | 3 iron ingots, 2 sticks | 1 tool, 60 uses |
| Leather cap, tunic, trousers or boots | 5, 8, 7 or 4 leather | 1 piece of armor, 8 uses |

Once Ada's house is finished, a bench queues the planks and sticks a recipe needs on its own.

**Tools.** Bare hands chop slowly and can't break stone. A wooden tool is faster, a stone one faster again, and an iron one fastest. Each use wears a tool down, and it breaks when it runs out.
- **With a toolsmith** (a resident whose job is Toolsmith; Ada doesn't count), the bench keeps one spare of each tool someone uses, made from the best material on hand: iron, then stone, then wood. A resident whose tool breaks walks over and picks up the spare.
- **Without one,** a resident whose tool breaks stops and says so. Queue a new one at the bench (Ada makes it), or make someone the toolsmith.
- **Equip** in the resident panel lists the tools lying about. Choose one, and the resident goes to fetch it and keeps it until it breaks.

**Leather armor.** A cap, a tunic, trousers and boots, made from the meadow's leather by anyone who crafts. A resident in the village puts on any piece lying about for a slot they haven't filled, and you can see it on them in brown. Armor turns aside a share of the injuries from hazards: 5% for the cap or the boots, 10% for the trousers, 15% for the tunic, 35% for all four. A full set also makes an injury half as likely to be serious. Each piece loses a use every time a hazard strikes, and wears out after 8. The resident panel's **Armor** row shows the guard and the uses left, and the expedition planner shows the party's armor.

## Building

Place a blueprint from the **Build** menu, and residents with **Build** on bring materials and put it up in stages. The site panel shows what the current stage still needs.

**Clearing the ground.** Whatever lies where a building goes is cleared first. Trees are felled and boulders broken, berry bushes are dug up, and loose items are carried off to a stockpile by haulers; nothing is built until the ground is bare. The hint while placing says what it will clear ("Clears 2 trees, 6 logs and a bush"), and the blueprint's panel and the stuck list say what's left, including "no room in a stockpile" if there's nowhere to put it. With no stockpile yet, loose items are carried to open ground beside the building.

| Building | Stages and costs |
|---|---|
| Crafting bench | 4 logs |
| House (5×5) | Foundation: 8 cobblestone. Walls: 16 planks and 4 logs. Roof: 12 planks. Bed: 3 wool and 3 planks |
| Fireplace | 6 cobblestone |
| Expedition board | 6 planks, 4 sticks. In the Build menu once the founding is done |

**R** turns a house's door while you're placing it. Trees, boulders, stockpile cells and farm plots in the way are cleared first.

The bench, the fireplace and the expedition board will grow into a workshop, a kitchen and a map room in a later version. Each one keeps a 3×3 plot around itself clear for that, shown as a faint dashed outline. You can't build, farm or stockpile on the plot, though residents walk across it. **R** turns which side of the building the plot sits on.

## Food

Residents get hungry. A full resident empties in about 6 minutes of game time.
- Below 40, their next job is to fetch the nearest food and eat it.
- Below 25 they're **Hungry** and work 25% slower.
- At 0 they're **Starving** and stop working until there's food.

| Food | Fills | Where it comes from |
|---|---|---|
| Berries | 15 | Six berry bushes around the clearing. Each holds 3 berries, and a berry grows back every 45 seconds |
| Raw mutton, beef or porkchop | 20 | Hunting sheep, cows and pigs. Residents eat raw meat only when there's nothing else |
| Bread | 50 | The fireplace, from 3 wheat |
| Cooked mutton, beef or porkchop | 60 | The fireplace, from 1 raw meat and 1 log of fuel |

**Farming.** Paint farm plots over open grass. Residents with **Farm** on plant each cell, the wheat ripens in 2 minutes, and a harvest gives 2 wheat. A plot is replanted only after its wheat has been carried away, so a farm needs a stockpile.

**The fireplace** cooks whatever you queue. It also smelts: **Smelt iron** turns 1 iron ore and 1 coal into an iron ingot, for iron tools. It also has a standing order, **Keep 6 meals in stock**, which is on by default: while fewer than 6 bread and cooked meats are stored, cooks make whatever the wheat, raw meat and logs allow.

**Animals.** Six sheep roam the clearing at the start, enough wool for the first two beds. Each gives 1 wool and 1 raw mutton. After that, there are more at the **meadow**, off the map past the signpost on the left edge, with **cows** (1 leather and 2 raw beef each) and **pigs** (2 raw porkchops each) too. Getting there is an adventure: build an expedition board and plan a trip (see Expeditions).

## Expeditions

The **expedition board** is where expeditions are planned. Once it's built, the village has word of an **old mine** a short walk east, with stone and coal, and a **meadow** a short walk west, with sheep, cows and pigs.

**The Location dropdown.** Select the board and it opens on the place you last planned for (the first one the first time), with a **Location** dropdown in its header showing it and its walk, such as "Meadow · ~28 s each way". Open the dropdown to see everywhere the village knows of, one line each with its walk and whether anyone has been, and a flag where hazards are known; choose one to see its site report and planner. Each place also has a signpost on the village's edge facing it: click the meadow's signpost to open the board on it, or the old mine's for **Plan a trip to the old mine**. Only one expedition goes at a time, so while one is packing or out, the dropdown shows where the party is and the other places are listed but can't be chosen.

**The site report** (left) says what the village knows about the place: what it has been told, the walk there, and what can be gathered. Until someone has been, there are no estimates and no known hazards.

**Planning:**
- **Party:** choose 1 to 3 residents. Each shows their Stonemason level, pickaxe and hunger. Anyone who can't go, such as someone still walking in, says why.
- **Bring back, best first:** a ranked list of what this place can give. Each row has a tick (an item that's off is left behind), its name, how many you want (**Max** takes as much as fits), and ▲ ▼ to move it up or down. The party fills its packs in that order, marks the blocks (or animals) of the top row that still wants more, and when the packs are full and something better turns up, swaps out the lowest-priority cargo, which stays at the site as a stack. A place you have planned for remembers its list, and an item you learn it gives later joins at the bottom marked **New**. The old mine starts with coal then cobblestone, the meadow with wool, leather, then meat. "Target reached" means every row with an amount is packed; a row set to Max never blocks it.
- **Clear the level:** a toggle above the list, for the old mine. The party works every block of what's ticked, nearest the entrance first (never one under a known loose ceiling), whatever the amounts say. Once the level is cleared it digs to the door itself and goes down with no choice to make, and carries on down until the packs are full, the food runs low, or someone is badly hurt. The party panel shows how many blocks are left on the level.
- **Diamonds.** From level 4 down the old mine hides a few blocks of **diamond ore**, found only when someone mines next to one (the game stops to tell you). Diamond ore can only be mined with an **iron pickaxe**; with less the stuck list says so. Once found, diamonds join the Bring back list (at the bottom, marked New) so you can rank them. Three diamonds and two sticks make a **diamond pickaxe** or **axe** at the bench, the best tools there are, and the toolsmith keeps a diamond spare when there are enough.
- **Gold, gravel and obsidian.** Deeper still, the old mine has **gold ore** (from level 2), **gravel** (from level 3) and **obsidian** (from level 5, beside a glowing lava pool nobody can walk into). Gold smelts at the fireplace with coal into gold ingots. Gravel sometimes gives a **flint**; a flint and an iron ingot make **flint and steel** at the bench. Obsidian can only be mined with a **diamond pickaxe**. All of them show up on the level's report and the Bring back list once someone has seen them.
- **The Nether portal.** Once obsidian has come home, the Build menu offers a **Nether portal**: a frame of 10 obsidian, with room in front for a party to gather. Builders carry the obsidian in and build it. A finished frame stays dark until someone lights it with **flint and steel**, which is put back with a use fewer. A lit portal shimmers violet. If it's stuck, the list says what it needs: "Portal frame needs 6 more obsidian" or "Needs flint and steel to light".
- **The Nether landing.** Once the portal is lit, the expedition board lists **Nether: portal landing**. Plan a trip to it like any other: the party packs on the staging area in front of the portal, walks through it, surveys the landing's three landmarks and comes home the same way. The board can plan one Overworld trip and one Nether trip at once. If the portal goes out while the party is through, a flint and steel in their packs relights it; without one they wait for the village to light it from this side. The landing is hot and red, with lava pools nobody walks into. It has **hazards**: stepping beside lava can burn someone, a patch of fire sets them alight (they step off it, and the burning stops a couple of seconds later), and a ledge can drop them. Residents go round the heat when there's a way. A burn is an injury like any other: they work slower and can't mine, and a serious one stops the game to ask whether to retreat. The stuck list says "Burned" when it was fire. The site report lists the hazards once someone's been there.
- **Guards.** **Guard** is a job on the Jobs board, with no workstation: a guard hauls at home and fights on expeditions. Craft an **iron sword** (2 iron ingots and a stick) and a guard takes it and keeps it; the toolsmith keeps a spare. An **iron chestplate** (8 iron ingots) turns aside more injuries than leather. If a guard is in the party with no sword to hand, the planner says "No sword for Bram".
- **Fights.** Creatures live on the Nether's maps, never in the village: **magma cubes** (hostile) and **zombified piglins** (neutral until hit) on the routes, and **skeletons** and **blazes** in the fortress. They come for people they notice. Guards (and Ada) fight them on their own and gain practice for each one brought down; everyone else moves away and goes back to work. A hit is an injury like a fall or a burn: armor turns some aside, and a knock-down stops the game to ask about the retreat. Nobody dies. By default the party avoids combat except in self-defense. What a creature drops (magma cream, bones, blaze rods) joins the Bring back list. The stuck list says "Nether party: fighting" while it goes on.
- **The shelter and cache.** The first Nether trip carries cobblestone and planks as well as meals, and the party builds a **shelter** on the landing before it comes home. Nobody lives there. Injured residents at the landing rest in it (slowly, like a resident with no bed). The planner's **Meals for the cache** sets aside meals the party leaves in the shelter; a later party that has run down its food eats from the cache and stays on instead of heading home. The site report shows what's in the cache, and the stuck list says "Shelter: needs 2 more planks" or "Cache: empty".
- **Scouting.** Three ways lead out of the landing, marked by posts at its edges: to the quartz site, the piglin camp and the fortress. They show as unknown until a party **scouts** one: plan a scouting trip, and the party walks the route to its far end, revealing it segment by segment with its lava, ledges and creatures. A scouted route's site becomes known. Posts turn yellow part-way and blue when done.
- **Objectives.** A Nether plan has an **objective**, picked in the planner: **Survey** (the first crossing), **Scout**, **Gather**, **Trade**, **Build**, **Fortress** or **Rescue**. Only places an objective can use are offered, and one with nowhere to go is greyed out, with the reason on hover ("No site to gather from: scout the route to the quartz site first"). Under the objective the planner tells you what's known of the dangers, the risks (no sword, no flint and steel for relighting the portal) and when the party comes home. Gather, Trade and Fortress each offer their site once its route is scouted; the trade and fortress sites are still to come.
- **The quartz site.** Scout the quartz route and the **Gather** objective offers the quartz site: a party crosses the landing, walks the route to the site, mines **nether quartz** (with a pickaxe) and **glowstone** (by hand), and comes home the same way. The site report shows what's left, which runs down as it's mined and doesn't come back.
- **Trading with the piglins.** Scout the piglin route and the **Trade** objective offers the piglin camp. Take **gold ingots** (from the deeper mine, smelted at the fireplace) and the party walks to the camp and trades down a **fixed table** shown in the planner and the site report: gold for obsidian, string, flint and fire resistance, the same every time. The rule is shown too: **piglins turn hostile if anyone in the party strikes one.** If it's broken they fight, and the trading stops. The report lists what was traded.
- **The fortress.** Scout the fortress route and the **Fortress** objective offers its entrance: nether brick halls with blazes and skeletons, so take guards (the planner warns without one). Blaze rods and bones they drop come home as cargo. At the far end is a **salvage chest** beside a sealed way deeper: the game stops once, and you choose to take the salvage and return, or take it and press on to clear the halls. The salvage can only be taken once; the way deeper stays sealed for later.
- **Stranded, and rescue.** Nobody dies in the Nether. A party that can't go on (its provisions gone, the portal dark with no flint and steel, or everyone seriously hurt) shelters and the game stops to tell you what's at stake. A **rescue window** of four minutes counts down in the expedition panel, with the party's supplies. Press **Plan a rescue** and send a party with provisions: it can set out even when both parties are out. If it reaches them in time, everyone comes home with their cargo. If not, the stranded party walks home on its own, slowly and hurt, and leaves its cargo and spare tools behind where they stood; a later trip can pick them up.
- **Lapis and redstone.** From level 3 down, the old mine also holds **lapis ore** and **redstone ore**, in plain sight in the rock. Both need an **iron pickaxe** or better, and a block gives 3. They show on the level's report and the Bring back list once someone has seen them. Lapis is the common cost of enchanting; redstone powers the automation devices that come later.
- **Enchanted books.** Each names one enchantment: Efficiency, Unbreaking, Protection or Fire protection. They turn up in the **fortress salvage** (Protection and Fire protection likelier), in **chests** in the deep mine from level 3 (Efficiency and Unbreaking likelier; any pickaxe breaks one open), and on the **piglins' table** (Efficiency 8 gold, Unbreaking 6). The first book you find stops the game to say what it teaches. Bring one home: an enchanting workshop learns its recipe for good.
- **The enchanting workshop.** Once a book has been found, the Build menu offers an **enchanting workshop**: 4 obsidian, 2 diamonds and 6 planks. **Enchanter** is a job on the Jobs board (Ada can do it too). An Enchanter carries a book from the stockpile to the workshop, which **learns that recipe for good** and uses the book up; a second copy of the same book isn't carried. Select the workshop to see which recipes it knows and what each costs. If no one has the job, the stuck list says so.
- **Enchanting.** Select the workshop: each recipe it knows lists the items in the stockpile it can go on. Click one to order it. An Enchanter fetches the item, the lapis and the ingredient, works it, and the enchanted item ("iron pickaxe of Efficiency", with a violet spark) comes out keeping its wear. **Efficiency** (2 lapis, 1 quartz) goes on axes and pickaxes; **Unbreaking** (2 lapis, 1 iron ingot) on tools, swords and armor; **Protection** (3 lapis, 2 iron ingots) and **Fire protection** (3 lapis, 1 magma cream) on armor. One enchantment to an item, and no rerolls. Residents prefer enchanted tools, and a party's packs can carry them. Efficiency makes a tool work 30% faster (on top of skill, and quite apart from any track), Unbreaking halves wear, Protection cuts creature injuries by 30% for each piece worn, and Fire protection halves harm from fire and lava. Each shows on the item's name: "Iron pickaxe · Efficiency (mines 30% faster)".
- **The portal line.** Once the portal stands, the Build menu offers a **portal station**: 6 planks and 4 cobblestone, within a few cells of the portal. It reserves room for a freight loader. Then plan a **Build** trip to **the portal line from the landing**: the party carries 6 rails (and 6 planks and 4 cobblestone for a landing station, if there isn't one) and lays the track from the portal's far side to the station beside the shelter. The Nether line shares that station. A finished line is ridden: parties cross the landing faster.
- **The freight cart.** With the portal line finished, select the portal station and **Order a freight cart**: a hauler brings a minecart from the stockpile and parks it there. It carries goods, never people, through the portal to the shelter's cache (60 items at most) and comes back empty. **It never leaves without your approval**: press **Approve departure** when it's loaded. The stuck list says why it waits: "waiting for approval", "the portal is unlit", "the cache is full". You can see it run along the rails with its load stacked on it.
- **Redstone devices.** Once the portal station is planned, the Build menu offers a **cache sensor** and a **condition** (2 redstone dust, 1 quartz and 2 cobblestone each). A sensor reads the Nether cache from the village and is on while an item (meals, iron ingots, planks, cobblestone) is **below** a threshold you set with − / +. A condition passes a signal along only while a fact holds: the portal is lit, the freight cart is home, or the loader is idle. Select a device to see whether it's **on or off and why**, for example "On: Cache food 6 < 10, and the portal is lit". Its panel has **Wire to the …** buttons: a resident with Build on lays redstone dust from one device to the other (4 cells to a dust), and the signal runs once every cell is laid. **Cut** takes a line up. Press **O** for the redstone overlay: the world dims and the devices and dust stand out.
- **The freight loader.** With the portal station built, the Build menu offers a **freight loader** (3 redstone dust, 1 quartz, 4 cobblestone) on the station's reserved plot. Its panel holds the **freight list** (10 bread and 2 iron ingots to begin with; − / + change it, up to 30 items). Wire a condition into it: while it is powered and a freight cart waits at the station, residents carry the list from the stockpile onto the cart, and the loader turns on to say "loaded". Then approve the cart's departure. If it can't finish, the stuck list says why: "Loader: needs 6 more bread", "no freight cart at the station", "no one with Haul on".
- **The dispatcher.** A **dispatcher** (2 redstone dust, 1 quartz, 2 cobblestone) stands within a few cells of the portal station. Wire the loader into it. When the cart is loaded it **asks you to approve** the trip: a toast, and a line in the stuck list. The game does not pause. Select the portal station and press **Approve departure** to send the cart, or **Decline: unload it** to put the goods back in the stockpile (the chain then waits for the cache to recover before asking again). A whole chain: cache sensor (meals below 10) → condition (the portal is lit) → loader → dispatcher.
- **The Nether line.** Once the quartz route is scouted, the **Build** objective offers **the Nether line to the quartz site**. A party carries rails, planks, cobblestone and a minecart (set with the planner's steppers), builds a station at the landing, bridges the lava channel and the gap, lays track east, builds a station at the quartz site and parks the cart. The planner shows what's still to build and the time it saves. It can take more than one trip. If a bridge's planks are missing the stuck list says "Track: needs the lava channel bridged first". When it's done parties ride it both ways, faster, and safe from the creatures and lava beside the way; mining at the site is no faster.
- **Meals to take** and **spare pickaxes.** One meal each is kept for the walk home, unless you choose **Spend it**.
- **Packs:** each member carries 15 items. Supplies (yellow) and cargo (blue) share that room, so more food leaves less room for what they bring back.
- **Come home when:** the target is reached, the packs are full, or food runs low. Choose one or more. A serious injury always brings them home.

**Packing.** **Start packing** doesn't send anyone yet. Residents with Haul on carry the meals and spare pickaxes to the board, where they stack up as crates. The party finishes what they're doing and waits at the board. The planner shows what's packed and who's there, and the stuck list says what it's waiting for.

**Depart** sends them off once everything is packed and everyone is at the board. From then on they're out of village work. The board can plan only one expedition at a time. **Call off the expedition** before departure unpacks everything, and the supplies are hauled back to the stockpile.

**The road.** The party carries the packs to the signpost on the east edge of the village, then walks the **road to the mine**, a long strip of a map of its own (see below). Switch to it to watch them, or click the signpost to see who's on it and how long they have left. They don't work on the way, and they can eat from the packs if they get hungry. At the far end they go into the mine.

**At the mine** the party works by itself. It marks the blocks of what it was sent for, nearest first, mines them, and carries what it mines into its packs by the entrance. It eats from the packs, leaving the food for the walk home unless you chose Spend it. A broken pickaxe is swapped for a spare from the packs. You can mark more blocks with Gather while you're looking at the mine. The panel under the party line shows each member, the packs, the meals and how close they are to the target.

**Coming home.** The party heads home by itself when its return policy is met: the target reached, the packs full, or the food running low. You can also choose **Call the party home** at any time: it's in the bar under the tallies while you're looking at the mine, and on the board and each party member's panel. Back at the signpost, they set the cargo down and it's hauled to the stockpile before anything else. A report says what came back, what it cost and who was hurt, and the board shows it until the next expedition.

**Hazards.** Once someone has been to the old mine, its report lists the dangers:
- **Loose ceilings** over a few blocks, drawn with cracks. Mining one can bring it down on the miner. The party never marks these by itself; it's your call.
- **A ledge** in the dark tunnel to the deepest part, where someone can fall.
- **Dark tunnels**, where work is slower.

**Injuries.** An injured resident wears a white bandage, walks and works slower, and can't mine. Someone **seriously hurt** can't work, and the game stops for you to choose: **Retreat** (everyone heads home now) or **Press on** (they wait at the entrance while the rest keep working). Ada can be hurt, but never seriously. At home, the hurt rest in their own bed until they've healed: 2 minutes for an injury, 5 for a serious one, and slower without a bed of their own.

**The discovery.** There's something else in the old mine. When the party finds it, the game stops with three choices, each with its cost: **Keep mining**, **Investigate** (someone spends time and pickaxe uses surveying it, and you can send parties for it from then on), or **Mark it and return later** (the party heads home now). The find is remembered either way.

**Deeper levels.** At the far end of the old mine, a heavy wooden door is set in the rock, with a block of stone in front of it. **Dig to the door**, in the party's panel, marks the way. When someone reaches it, the game stops: **Go down now** (the door opens and the party works the level below instead), **Mark it for later** (the party heads home now) or **Keep mining here**. Every level has a door at its far end to the next one, and every floor is laid out differently: a winding cave, a hall of pillars, a maze of tunnels, a cavern split by a stream, a field of rubble. Deeper levels have more coal and iron, but they're darker, and cave-ins and falls are more likely. Once there's more than one level, the planner has a **Work level** row, and the site report lists every level with what's left and its door. The party walks down through each level above to get there, and carries its cargo back up the same way. A level's ore never comes back once mined.

## The meadow

The **meadow** is a short walk west, past the signpost on the village's left edge: open grass around a pond, with trees, a few old fences, and herds of sheep, cows and pigs. Plan a trip there from the board's Location dropdown, for wool, leather or meat. No spare pickaxes are needed.

The party carries the packs to the west signpost and walks the **road to the meadow**, a plain strip of its own map, about 28 seconds each way. It shows in the map switcher once the board is up, and you can switch to it to watch them go and come back. It has no obstacles and nothing to build on it. At the meadow they hunt the animals that give what they were sent for, nearest first, follow them as they wander, and pack the drops. Once they have enough, they pack anything else lying about, such as the leather from the cows they hunted for beef. A full party brings back as much as its packs hold. You can mark more animals with Hunt while you're looking at the meadow.

**Hazards** there are mild: an **angry bull** can hurt someone hunting a cow, and the **pond bank** is slippery. Neither injury is ever serious.

Each kind of wild animal grows back on its own, a few minutes at a time, up to the herd the meadow started with.

**Pens.** While you're looking at the meadow, **Paint ▸ Pen** drags out a fenced pen, from 4×4 to 8×8 with its fences, on open grass. It holds one animal for each cell inside, and its gate faces the way in. A party builds it with sticks from its packs, one stick a fence: the planner offers **Sticks for fences** and fills in what the pens need. Start a drag on a pen, or use its panel, to take it down.
- **Gather ▸ Lead to a pen** marks animals with a blue loop. The party walks each one into a finished pen with room.
- **Breeding:** the party feeds two grown animals of a kind in a pen a wheat each, from the **Wheat to feed pairs** you packed. A heart shows over them, and half a minute later there's a lamb, calf or piglet. The pair can be fed again after 5 minutes. Young ones are smaller, grow up in 4 minutes, and can't be hunted till then. All of this goes on whether or not anyone is there.
- **Tend the pens** is an objective of its own: the party builds, leads and feeds, then hunts only the penned animals over the number you choose to keep of each kind, and packs their drops.
- On any trip to the meadow, the party builds the pens and leads and feeds before it hunts, and never hunts penned animals for its objective. Wild animals regrow apart from the pens.

## The road to the mine

The road between the village and the old mine is a map of its own: **Road to the mine** in the map switcher, once the expedition board has word of the mine. It's split into six segments, from the village edge to the slope below the mine.

**Surveying.** At first, only the segment by the village is known, and the rest is fog. The first party to walk the road reveals it as they go. After that, the **signpost** (in the village, or at either end of the road) shows the route: each segment with its length, its terrain and anything in the way, and how long the walk takes. The expedition planner uses that estimate too.

**Obstacles:**
- **The stream.** People wade across, slowly. **Build the bridge**, on the signpost's panel, places a plank bridge (12 planks). Residents with Build on carry the planks out from the village and build it. After that there's no more wading, and track can cross.
- **The rocky cut.** Three boulders stand on the line. **Clear the cut** marks them, and stonemasons (and Ada) walk out with their pickaxes to break them. You can also mark them yourself with Gather while looking at the road.

Residents who go out to work on the road walk back to the village when they're done, or when they get hungry.

**Rails and minecarts** are made at the bench from the old mine's iron: 6 iron ingots and a stick make 16 rails, and 5 iron ingots make a minecart. Both are Craft work.

**Planning the line.** Once the road has been walked, **Plan the line** on the signpost's panel shows what it would cost: the rails it takes (2 a segment), how many are on hand, the iron to craft the rest, and about how much time a round trip would save by cart. **Lay track** puts a track blueprint along every segment. Track is laid from the village end outward by the **track crew**, residents with Build on. They carry rails out to a **railhead** pile at the road's village end, then from there to the segment being laid, which fills in rail by rail. The stream's segment waits for the bridge, and the cut's for its boulders to be cleared. The stuck list says what the track needs: more rails, the bridge, the cut, or someone with Build on.

**Stations.** **Build the village station** and **Build the mine station** (6 planks and 4 cobblestone each) put a platform beside the line at each end. Once the village station is built, a minecart from the village is hauled out and parked there. Select a station to see how much of the line is laid, where the cart is and what's on its platform.

**Riding.** When the cart waits at the village station, both stations are built and the cut is clear, the next party rides. They get in at the road's end, ride the laid track fast, and push the cart at walking pace where there's no track yet. Coming home, their cargo is loaded into the cart at the mine and unloaded onto the village platform, faster than unpacking by hand at the signpost. Haulers carry it to the stockpile from there. With the whole line laid, the cart also adds 20 to the party's packs. The report says how long they spent on the road and how much time the cart saved. Mining at the old mine is no faster.

**Unpacking.** A party coming home on foot unpacks at the signpost, two items a second each, before it goes back to work.

## New residents

A traveler arrives about 45 seconds after a house with a free bed is finished, one per free bed. A house is only free once its bed is built, so wool is what lets the village grow. After Tomas come Mira, Jonas, Elsa, Bram, Ines, Otto and Lena.

## When something stalls

Anything that can't go on gets a **yellow flag** on the map and an entry in the **stuck list** at the top right, with the reason in plain words, such as "Walls need 4 more planks", "Needs a pickaxe", "No one does Build" or "Starving: no food stored".
- Click an entry, or press **N**, to go to it.
- The entry that's been stuck longest is at the top.
- A standing order that's only short of materials, like the toolsmith's spare, goes in a dim **waiting** line instead, without a flag. So does an expedition that's still packing. It's advice, not a blocker.
- Click the **Stuck** header to fold the list into a small chip. It opens again when something new gets stuck.

## Controls

Every key can be changed on the menu's **Controls** page. Esc and the mouse can't be changed.

| Key or mouse | Action |
|---|---|
| E / Z / B / C | Gather menu, Paint menu, Build menu, Craft panel |
| 1 to 9, with a menu open | Pick that row |
| Q E R Z X C V, with something selected | The selection panel's buttons, in order (see below) |
| 1 to 9, with a list open | Pick that entry (a job, a tool to equip) |
| X / G / P | Mine, Hunt, Farm plot, directly |
| T / H / K | Place a crafting bench, a house or a fireplace (the expedition board has no key, but you can set one) |
| R | Turn a building while placing it |
| Shift-drag / Alt-drag with Mine | Mark trees only, or boulders only |
| Click | Select a resident or anything else |
| Shift-drag | Select several residents |
| Right-click a tree, boulder or animal | Its orders, in a ring: click one, press 1–4, or drag to one and let go. Esc closes it |
| Right-click the ground | Walk the selected residents there |
| Shift + right-click | Queue an order after their current one, skipping the ring |
| J | Village jobs board |
| F / N | Next resident, next stuck item |
| Tab | Switch between the village, the old mine (and its levels), the road to it and the meadow, once they're known |
| Drag, W A S D, arrow keys | Pan |
| Mouse wheel, + / − | Zoom |
| Space / ~ | Pause or resume, pause |
| 1 / 2 / 3 | Game speed |
| Esc | Close whatever is open, or open the menu |
| M / ? | Menu, Controls |

The **Menu** button at the top right, beside the speed buttons, opens the same menu with a click. It shows the menu key (M unless you've changed it), and Esc always works too.

**Panel keys.** When something is selected, the first seven buttons in its panel each show a small key: **Q E R Z X C V**, in the order the buttons appear. Click a tree and press **Q** to mark it for chopping, and **Q** again to cancel. A key that opens a list, such as a resident's job, then lets **1 to 9** pick an entry (and the speed keys wait). Buttons that remove something, like a farm plot's, arm on the key and act on the same key again; any other key puts them away. The selection stays after a key, so you see the panel change. With nothing selected these keys keep their usual meanings (**E** gather, **Z** paint, **X** mine, **C** craft), **F** still cycles residents, and **Esc** clears the selection. The panel keys can be changed on the Controls page, under Selection.

You can still give orders while the game is paused.

## Saving and settings

The menu (the **Menu** button at the top right, or Esc) has five save slots. A save made during the founding is labelled with the next step. After the founding, it's labelled with facts about the village, such as "4 residents, 3 houses, 18 meals".

**Autosave.** The game also saves itself, to a file of its own that never takes one of the five slots: every 5 minutes of play, when a party sets out or comes home, when you choose **Start over** or **Quit**, and when you close the window. **Load game** lists it as **Autosave** above the slots, with when it was made. A game younger than 2 minutes isn't autosaved, so a new game never replaces your village's autosave. Pausing stops the clock, since nothing changes. (In the browser the window closing can't be caught, so the 5-minute and party saves are what you have there.)

**Interface size**, on the menu, sets how big the panels and their text are drawn: 90, 100, 115 or 130%. It's saved along with your key bindings. Older saves keep loading as the game changes.
