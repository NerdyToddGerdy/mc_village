# How to play Block Village

You start with one person, Ada, in a forest clearing. She gathers wood and stone, crafts tools and builds the first houses. Travelers arrive when there's a bed for them, and the village grows from there.

You don't steer anyone's every swing. You **mark work** (trees to chop, sheep to hunt, ground to farm) and **place blueprints**, and residents take the jobs on themselves. When anything stalls, the game says why.

This guide covers the game as it plays today: the founding (Slice 1) and the working village (Slice 2). Every number in it is provisional and may change as the game is balanced.

## Starting the game

You need Godot 4.7 to run the game; the README's [Running the game](../README.md#running-the-game) section says how to install it and launch the game. It opens on the main menu: choose **Play** to start a new village, or **Load game** to carry on with a saved one.

## The screen

```
┌──────────────────────────────────────────────────────────────┐
│ Logs 12 Planks 4 …   Tools ▾  Jobs            ‖  1×  2×  3×  │
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

- **Top left:** what's in the village. Materials and food are counted, with how much is still lying loose. **Tools** lists everyone's tools and the spares. **Jobs** opens the village jobs board.
- **Below that:** the **goals panel**, which walks you through the founding one step at a time. Once the founding is done, it folds to a small "Founding ✓".
- **Top right:** pause and speed, and the **stuck list**, which shows anything that can't go on and why.
- **Bottom left:** whatever you've selected: a resident, a building, a tree, a farm plot.
- **Bottom right:** the **orders toolbar**, and the Craft panel when it's open.

**Other maps.** Expeditions go to places off the map, such as an old mine. Once the village knows of one, a switcher in the top bar shows **Village** and **Old mine** (Tab switches), and a dim line under it says what a party there is doing, or how long until it gets there. Each map keeps its own view. Stockpiles, farms and buildings stay in the village.

Marks drawn on the world show what's been ordered. Chalk-white means selected, red means mine or hunt, green hatching is a stockpile, wheat rows are a farm, a blue dashed outline is a blueprint, and a yellow flag means something is stuck.

## The founding, step by step

The goals panel leads you through these steps. Each one unlocks the next.

1. **Chop a tree.** Choose **Gather → Mine** (or press **X**) and click a tree. Ada fells it by hand, slowly. A tree drops 4 to 6 logs.
2. **Build a crafting bench.** Choose **Build → Crafting bench** (or press **T**) and click open ground. It takes 4 logs.
3. **Make Ada the toolsmith.** Press **J** for the jobs board and click Ada's **Toolsmith** cell. Nobody starts as a toolsmith, and only a toolsmith makes tools.
4. **Craft a pickaxe.** Open the bench (click it, or press **C**). Queue planks, then sticks, then a wooden pickaxe.
5. **Paint a stockpile.** Choose **Paint → Stockpile** (Z, then 1) and drag over open ground. Residents carry what they gather there.
6. **Break a boulder.** With a pickaxe, Ada can mine boulders for cobblestone. Each one gives 6.
7. **Hunt sheep for wool.** Choose **Gather → Hunt** (or press **G**) and mark sheep. Each one gives 1 wool and 1 raw mutton. A house's bed needs 3 wool.
8. **Build Ada's house.** Choose **Build → House** (or press **H**), and press **R** to turn the door. The house goes up in stages as materials arrive, and its bed is the last stage.
9. **Build a second house.** From here on, the bench queues the planks and sticks a recipe needs by itself.
10. **Welcome a traveler.** Tomas arrives a little while after the second house, bed included, is finished.
11. **Two residents at work.** Keep both busy on different jobs.

## Giving orders

There are two ways to get work done.

**Mark work for anyone.** The toolbar's orders mark the world, and any resident with that job switched on takes the work. Click to mark one thing, or drag a rectangle to mark many. Clicking something that's already marked unmarks it.

| Toolbar | Order | What it does |
|---|---|---|
| **Gather** (E) | Mine (X) | Fell trees and break boulders. Shift-drag marks only trees, Alt-drag (Option on a Mac) only boulders |
| | Chop trees | Trees only |
| | Break boulders | Boulders only. Breaking them needs a pickaxe |
| | Hunt (G) | Sheep. Shows while there are sheep in the clearing |
| **Paint** (Z) | Stockpile | Ground where residents store what they gather |
| | Farm plot (P) | Open grass where residents grow wheat |
| **Build** (B) | Crafting bench (T), House (H), Fireplace (K) | Place a blueprint. R turns it |
| **Craft** (C) | | Opens the Craft panel for your benches and fireplace |

While a toolbar menu is open, **1 to 9** pick its rows, so Z then 1 paints a stockpile. The Gather and Paint buttons show the order that's on, such as "Gather: Hunt". Esc puts the order away.

**To erase** stockpile cells or farm plots, switch that Paint order on and start a drag on a painted cell. The cells that will go show in red. Items on an erased stockpile cell stay where they are and get carried to the rest of the stockpile. Wheat growing on an erased farm plot is lost.

**Order someone directly.** Select a resident and **right-click** a tree, boulder or sheep to send them to it, or right-click the ground to send them there. **Shift + right-click** adds the order to the end of their list. Direct orders come before everything else, whatever their jobs are set to. They still work while a Gather or Paint order is on.

## Residents

**Selecting.** Click a resident, or press **F** for the next one. Shift-drag a box to select several. Each resident wears their own tunic colour, and hovering over one or selecting them shows their name above their head.

**The resident panel** shows:
- what they're doing;
- their axe and pickaxe, with uses left;
- what they're carrying;
- how hungry they are;
- any orders you've queued for them;
- one line about their jobs, with a button to the jobs board.

**The village jobs board** (press **J**, or click **Jobs** in the top bar) lists every resident and every job: Mine, Haul, Build, Craft, Toolsmith, Farm, Cook and Hunt.
- Each cell shows the job's **priority** (1 goes first) or **Off**, the resident's **level** in it, and a thin bar of progress to the next level.
- **Click** an Off cell to switch the job on, and click an on cell to cycle its priority 1 → 2 → 3.
- **Shift-click** a cell to switch the job off.
- A column's header counts who does the job, and reads "nobody" in yellow when no one does.

Residents work through their switched-on jobs priority 1 first. Within the same priority, bench and fireplace work comes first, then building, then farming, then mining and hunting, then hauling.

**Skills** grow with practice. Every finished task earns a point in its job, and levels 2 to 5 come at 8, 25, 50 and 90 points. Each level works 15% faster, and some jobs also get better results:

| Job | Better result |
|---|---|
| Mine | An extra log or cobblestone per tree or boulder, at levels 3 and 5 |
| Farm | An extra wheat per harvest, at levels 3 and 5 |
| Haul | Carries one more, at levels 3 and 5 |
| Craft | 5 planks from a log instead of 4, at level 4 and up |
| Cook | Bread from 2 wheat instead of 3, at level 4 and up |
| Toolsmith | Tools last 20% longer per level above 1 |

**New residents** arrive skilled in one job, at level 3, and the toast that announces them says which.

## Materials and stockpiles

Everything is carried. Felled trees drop logs where they stood, and broken boulders drop cobblestone. Residents carry up to 4 of one thing at a time.

Until you paint a stockpile, items stay where they fell, and builders fetch them from the ground. Once there's a stockpile, residents with **Haul** on carry loose items to it. Each cell holds up to 16. If the stockpile is full, the stuck list says so.

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

Once Ada's house is finished, a bench queues the planks and sticks a recipe needs on its own.

**Tools.** Bare hands chop slowly and can't break stone. A wooden tool is faster, a stone one faster again, and an iron one fastest. Each use wears a tool down, and it breaks when it runs out.
- **With a toolsmith** (anyone with Toolsmith on), the bench keeps one spare of each tool someone uses, made from the best material on hand: iron, then stone, then wood. A resident whose tool breaks walks over and picks up the spare.
- **Without one,** a resident whose tool breaks stops and says so, and nothing makes a new one until you switch Toolsmith on for someone. Tools you queue by hand also need a toolsmith.
- **Equip** in the resident panel lists the tools lying about. Choose one, and the resident goes to fetch it and keeps it until it breaks.

## Building

Place a blueprint from the **Build** menu, and residents with **Build** on bring materials and put it up in stages. The site panel shows what the current stage still needs.

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
| Raw mutton | 20 | Hunting sheep. Residents eat it only when there's nothing else |
| Bread | 50 | The fireplace, from 3 wheat |
| Cooked mutton | 60 | The fireplace, from 1 raw mutton and 1 log of fuel |

**Farming.** Paint farm plots over open grass. Residents with **Farm** on plant each cell, the wheat ripens in 2 minutes, and a harvest gives 2 wheat. A plot is replanted only after its wheat has been carried away, so a farm needs a stockpile.

**The fireplace** cooks whatever you queue. It also smelts: **Smelt iron** turns 1 iron ore and 1 coal into an iron ingot, for iron tools. It also has a standing order, **Keep 6 meals in stock**, which is on by default: while fewer than 6 bread and cooked mutton are stored, cooks make whatever the wheat, mutton and logs allow.

**Sheep.** Six sheep roam the clearing at the start, enough wool for the first two beds. After that, there are more at the **sheep meadow**, off the map past the signpost on the left edge.
- Select one or two residents and choose **Send to the meadow**. They're away for 90 seconds, then come back with 2 wool and 2 raw mutton each.
- The meadow starts with 8 sheep and regains one every 4 minutes. Click the signpost to see how many are left.
- While residents are away, they don't work in the village and don't get hungry.

## Expeditions

The **expedition board** is where expeditions are planned. Once it's built, the village has word of an **old mine** a short walk east, with stone and coal. Select the board to open the planner.

**The site report** (left) says what the village knows about the old mine: what it has been told, the walk there, and what can be mined. Until someone has been, there are no estimates and no known hazards.

**Planning:**
- **Party:** choose 1 to 3 residents. Each shows their Mine level, pickaxe and hunger. Anyone who can't go, such as someone at the meadow, says why.
- **Bring back:** what to gather and how much.
- **Meals to take** and **spare pickaxes.** One meal each is kept for the walk home, unless you choose **Spend it**.
- **Packs:** each member carries 10 items. Supplies (yellow) and cargo (blue) share that room, so more food leaves less room for what they bring back.
- **Come home when:** the target is reached, the packs are full, or food runs low. Choose one or more. A serious injury always brings them home.

**Packing.** **Start packing** doesn't send anyone yet. Residents with Haul on carry the meals and spare pickaxes to the board, where they stack up as crates. The party finishes what they're doing and waits at the board. The planner shows what's packed and who's there, and the stuck list says what it's waiting for.

**Depart** sends them off once everything is packed and everyone is at the board. From then on they're out of village work. The board can plan only one expedition at a time. **Call off the expedition** before departure unpacks everything, and the supplies are hauled back to the stockpile.

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
| X / G / P | Mine, Hunt, Farm plot, directly |
| T / H / K | Place a crafting bench, a house or a fireplace (the expedition board has no key, but you can set one) |
| R | Turn a building while placing it |
| Shift-drag / Alt-drag with Mine | Mark trees only, or boulders only |
| Click | Select a resident or anything else |
| Shift-drag | Select several residents |
| Right-click | Order the selected residents to mine, hunt or walk |
| Shift + right-click | Queue an order after their current one |
| J | Village jobs board |
| F / N | Next resident, next stuck item |
| Tab | Switch between the village and the old mine, once it's known |
| Drag, W A S D, arrow keys | Pan |
| Mouse wheel, + / − | Zoom |
| Space / ~ | Pause or resume, pause |
| 1 / 2 / 3 | Game speed |
| Esc | Close whatever is open, or open the menu |
| M / ? | Menu, Controls |

You can still give orders while the game is paused.

## Saving and settings

The menu has five save slots. A save made during the founding is labelled with the next step. After the founding, it's labelled with facts about the village, such as "4 residents, 3 houses, 18 meals".

**Interface size**, on the menu, sets how big the panels and their text are drawn: 90, 100, 115 or 130%. It's saved along with your key bindings. Older saves keep loading as the game changes.
