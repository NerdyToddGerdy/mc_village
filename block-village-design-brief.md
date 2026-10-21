# Block Village — Working Game Design Brief

Status: Concept design. Working title only.

This document consolidates the discussion so far. Core decisions are separated from proposed details: proposed mechanics and numerical examples are not final balance decisions. Minecraft-inspired resources and mechanics below describe our adaptation, not a promise to reproduce Minecraft's exact rules.

## 1. Vision

An isometric, Minecraft-inspired settlement simulation. Begin with one player character (PC), build a village, recruit residents, and send groups on adventures to bring back supplies and discoveries. The settlement visibly grows from the work of its people and the results of their expeditions.

### Core decisions

- Begin with one PC rather than an established settlement.
- Order the PC to chop trees and break stone boulders for building materials.
- Build two houses: one for the PC and one for the first villager, who wanders into town.
- Grow a village that supports groups undertaking adventures for supplies.
- Upgrade particular expedition routes with minecart tracks to speed travel in both directions.
- Include the Nether, the End, and the Sift in the wider design.
- Include enchantments and redstone.
- Use an isometric presentation.
- Job buildings start simple and evolve in place: a crafting bench grows into a workshop, a fireplace into a kitchen. Each reserves the space its upgrade needs.

### Proposed design principles

- Show work and material movement in the world.
- Let direct character orders gradually give way to delegation.
- Connect village production, expedition preparation, exploration, and infrastructure.
- Make setbacks recoverable rather than immediately ending the game.
- Keep the home village useful throughout progression.

## 2. Opening Experience

1. The PC arrives empty-handed in a clearing with trees, stone boulders and a few sheep.
2. The player designates trees for chopping; the PC fells them slowly by hand. Stone cannot be broken without a pickaxe.
3. The player places a crafting bench blueprint; the PC builds it from logs.
4. At the bench, the PC crafts planks, sticks, and a wooden axe and pickaxe.
5. The player designates boulders for breaking and paints a stockpile zone; the PC gathers and hauls.
6. Stone tools replace the wooden ones.
7. The PC hunts sheep for wool (from Slice 2). The player places the PC's house blueprint, and the PC builds it, bed included.
8. The player places and completes a second house with its bed.
9. Because a bed is free, a traveler walks into the settlement empty-handed and becomes its first villager.
10. The PC crafts tools for the villager, and two residents allow the first division of labor.

Opening decisions:

- The opening starts with bare hands. Tools are crafted at a placed crafting bench, which later grows into the Workshop.
- Slice 1 materials are logs, cobblestone, planks, and sticks. Planks and sticks are made at the bench, and houses need planks.
- Tools come in wooden and stone axes and pickaxes. They have durability, and stone tools are faster.
- When a tool breaks, the resident stops and reports what it needs. Automatic replacement comes later with a toolsmith job.
- Houses use one fixed template that can be rotated when placed. Building fills in stage by stage (foundation, walls, roof) as materials are delivered.
- From Slice 2, every house has a bed as its last stage, which needs wool from sheep. **No free bed, no arrival**: travelers come only when a finished house has a free bed, as in Minecraft.

Proposed opening rules:

- The completed spare house, with its bed, triggers a guaranteed first arrival after a short wait.
- Later arrivals can have different skills and requirements. (Slice 2: each newcomer starts skilled in one job.)
- The PC remains an individual resident who can work, build, and join expeditions, but is not mandatory for every mission.

## 3. Core Gameplay Loop

Gather locally → build and support the village → recruit residents → equip an expedition → explore and recover supplies → unlock improvements → expand infrastructure → undertake more ambitious expeditions.

The village supplies basic necessities locally. Adventures provide larger hauls, scarce materials, discoveries, and new opportunities rather than being required for every ordinary meal or building repair.

Sending a worker on an expedition temporarily removes their labor from the village.

## 4. Village Systems

### Proposed buildings

| Building | Purpose |
|---|---|
| House | Accommodation for the PC and villagers. |
| Stockpile / warehouse | Stores gathered and recovered materials. |
| Farm and kitchen | Supports residents and prepares expedition food. |
| Workshop | Produces tools, equipment, and repairs. |
| Inn | Rest and a potential recruitment venue. |
| Map room / expedition board | Reviews discoveries and plans missions. |
| Enchanting workshop | Applies discovered enchantments to equipment. |
| Expedition staging area | Collects party members, gear, and supplies. |
| Rail station / loading station | Handles expedition transport and freight. |
| Portal facility | Supports travel to another dimension. |

The two-house opening does not require all these systems. Additional buildings should appear as their associated mechanics become useful.

### Materials and work

- Resources are gathered, hauled, stored, processed, and consumed.
- Construction uses delivered materials and takes worker time.
- Layout affects travel and hauling effort.
- Workers have jobs, priorities, equipment, and basic needs.
- Unfinished work explicitly reports missing materials, unavailable labor, or access problems.

## 5. General Expeditions

### Mission types

- Gather materials at known locations.
- Scout and discover new routes or destinations.
- Explore caves, camps, ruins, or other landmarks.
- Rescue stranded groups or recover abandoned cargo.
- Establish camps, depots, and outposts.

### Mission planning

Choose a destination, objective, party, equipment, provisions, desired cargo, and return policy. The expedition proceeds automatically according to its orders, with occasional decisions at meaningful moments.

Basic phases:

Preparation → outbound travel → work / adventure → return travel → unloading and recovery.

Supply, equipment, and cargo compete for carrying capacity. Longer provisioned missions have less room available for recovered materials.

### Party composition

Proposed specialties include scout, miner, guard, builder, porter, and trader. These are skills rather than mandatory rigid classes. A party does not need every specialty.

#### Core decisions (Slice 3)

- **Party size:** 1–3 residents, and the PC is eligible. All numbers are provisional.
- **One expedition out at a time.**
- Party members are absent from village labor while they're away.

### Decisions and outcomes

A party might discover a sealed entrance while gathering stone. The player can continue its original task, spend time and tools investigating, or mark the discovery and return later.

Routine actions resolve automatically. Important choices expose known costs and risks. Scouting improves available information.

**Core decision (Slice 3):** the game pauses for the player at two moments only: **at a discovery**, and **when someone is seriously hurt** (retreat or press on). Everything else follows the party's return policy.

## 6. Routes and Minecarts

Tracks upgrade specific routes rather than applying a universal travel-speed bonus.

Proposed progression:

1. Discover a destination on foot.
2. Establish a repeatable route with an estimated journey time.
3. Construct a minecart connection to reduce travel time in both directions.
4. Add loading facilities to improve cargo handling and freight capability.
5. Extend the network as new sites become useful.

Track does not speed up mining, combat, or exploration at the destination. It improves only connected travel segments.

The player plans the route, reviews costs and obstacles, and assigns construction. Villagers deliver materials and build visible sections.

Initial scope: point-to-point lines without complex signaling or timetable simulation.

## 7. Dimensions and Progression

These are proposed roles for our game, not exact Minecraft mechanics.

| Region | Proposed role |
|---|---|
| Overworld | Village life, basic gathering, recruitment, and early exploration. |
| Nether | Advanced materials, demanding preparation, and supported supply routes. |
| End | Major late-game expeditions, exceptional discoveries, and long commitments. |
| Sift | A parallel investigation / research branch with unusual conditions and discoveries. |

The Nether is the first proposed dimensional undertaking. The End need not be followed by the Sift as a strict tier ladder.

Main settlements remain in the Overworld initially. Other dimensions support camps, depots, and specialized outposts supplied from home.

Access is a village project: discover clues, investigate, gather materials, establish a portal, scout the far side, and develop supported routes.

The End and Sift are not yet designed in detail. Their exact mechanics, resources, access requirements, and progression remain open.

## 8. Nether Expedition System

### Goal

Progress from a vulnerable first crossing to a supported foothold with shelters, tracks, depots, and specialized expeditions.

Open portal → scout → recover resources → improve equipment → secure routes → establish an outpost → reach deeper sites.

### First mission

Proposed requirements:

- A portal and staging area.
- A small party; three residents was the initial example, with the PC eligible.
- Food, serviceable tools, and basic protection.
- Building materials for shelter and repairs.
- A way to relight the portal if needed.

The introductory objective is to survey the immediate area, establish a sheltered return point, and return safely. It must not require advanced resources obtainable only through successful Nether expeditions.

### Map and sites

The portal reveals a separate block-based region. Scouting reveals connected routes and locations.

Each site reports:

- Available resources.
- Estimated remaining reserves.
- Travel time from supported infrastructure.
- Known hazards.
- Access requirements, such as bridges or tunnels.
- Space and terrain suitability for camps or loading stations.

Deposits can become depleted. Existing shelters and stations can remain useful as network junctions and staging points.

### Missions

| Mission | Purpose |
|---|---|
| Scout | Discover routes, hazards, landmarks, and resources. |
| Gather | Extract a selected material from a known site. |
| Trade | Carry gold to a known piglin group and return with goods. |
| Fortress exploration | Recover rare resources and uncover further objectives. |
| Infrastructure construction | Build shelters, crossings, depots, or tracks. |
| Rescue / recovery | Retrieve people or abandoned supplies. |

Trading rules and encounter behavior should be explained before commitment rather than becoming surprise punishments.

### Core constraints

| Constraint | Function |
|---|---|
| Provisions | Limits how long the party can remain away. |
| Equipment condition | Limits productive work and protection. |
| Party condition | Injuries and fatigue can force retreat. |
| Cargo capacity | Limits recovered supplies. |

Avoid a generic danger meter that merely duplicates these constraints. Environmental hazards and encounters affect these systems through specific events.

#### Core decisions: injuries (Slice 3)

These apply to every expedition, not only the Nether.

- **Hazards cause injuries:** cave-ins, falls and darkness. Slice 3 has no mobs and no combat.
- **An injured resident** walks and works slower, and can't mine.
- **A serious injury** triggers the retreat return policy.
- **Injuries heal over time** in the resident's own bed at home.
- **The PC is protected:** they can be hurt, but never seriously, and the party always gets them home. Death stays open (§14).

### Return policies

- Return at a target quantity or full cargo.
- Avoid combat except in self-defense.
- Retreat after serious injury.
- Preserve supplies and equipment needed for the return journey.

Return provisions are reserved by default. Spending the reserve requires an explicit decision.

### Infrastructure

| Improvement | Effect |
|---|---|
| Survey markers | Reduce navigation delays and improve estimates. |
| Protected paths / tunnels | Reduce exposure on a specific segment. |
| Shelter / supply cache | Provides fallback shelter and provisions. |
| Minecart connection | Reduces connected travel time. |
| Loading station | Supports freight handling. |
| Staffed outpost | Supports nearby sites, repairs, and resupply. |

Example route: village → railway → portal → Nether station → railway → resource site → final walk to work area.

### Proposed rewards

| Resource / reward | Village use |
|---|---|
| Quartz | Advanced redstone sensing and controls. |
| Glowstone | Specialized lighting and workshop improvements. |
| Nether wart | Brewing production chain. |
| Blaze rods | Advanced brewing and later dimensional progression. |
| Rare salvage | Exceptional equipment and research. |
| Survey knowledge | New destinations and infrastructure opportunities. |

These uses are proposed for our adaptation. Nether resources should enable advanced development without becoming necessary for basic village survival.

### Failure and recovery

Default setbacks include abandoned cargo, damaged equipment, injuries, forced retreat, temporary route closure, and a party sheltering while awaiting assistance.

Stranded parties have visible supplies and a rescue window. Previously discovered terrain remains known after an outpost is lost. Permanent death is undecided and could be difficulty-dependent.

## 9. Enchantments

Enchantments specialize individual equipment used either at home or on expeditions.

| Proposed enchantment | Function in our game |
|---|---|
| Efficiency | Faster chopping, breaking, or expedition extraction. |
| Unbreaking | Slower equipment wear. |
| Fortune | Improved yields from selected resources. |
| Protection | Reduced encounter injuries. |
| Feather Falling | Helps with height-related hazards. |
| Fire-focused protection | Mitigates relevant environmental harm. |

Village production competes with expeditions for the best equipment.

### Proposed process

1. Discover enchanting knowledge.
2. Build an enchanting workshop and assign a worker.
3. Supply equipment and required materials.
4. Choose a known enchantment.
5. Assign the resulting item to a resident.

Prefer explicit known recipes to repeated random rerolls. Begin with one enchantment slot per item; combinations can come later.

## 10. Redstone

Redstone automates responses and logistics rather than acting only as a blanket production bonus.

Basic model:

Trigger → optional condition → action.

Examples:

- Low outpost provisions request a supply cart.
- A completed expedition loadout generates a ready signal.
- Full quarry storage requests collection.
- A returning cart is routed to an appropriate warehouse.
- An unsafe route stops routine dispatches.

### Interaction levels

1. Ready-made configurable devices: sensors, switches, gates, loaders, and rail controls.
2. Later custom circuits connecting inputs, timers, conditions, and outputs.

Initial implementation need not reproduce every Minecraft circuit behavior. Connections must be visible, inspectable, and explain why an output is active.

Automation may prepare dangerous missions, but departure approval stays manual initially. Familiar low-risk supply runs may later support automatic departure.

## 11. Visual Presentation

An isometric block-world diorama with visible changes caused by work.

Decided: real 3D block geometry viewed through a fixed isometric orthographic camera, built in Godot 4. The interface uses the "carpenter's chalk" visual language. Orders are chalk marks on the blocks themselves, and panels are slate boards around the edges of the screen. Details are in `slice-1-spec.md`.

- Chunky terrain and readable elevation.
- Buildings visibly constructed in stages.
- Recognizable characters, tools, and equipment.
- Stockpiles reflecting stored materials.
- Visible hauling, cart loading, workshop activity, and party assembly.
- Warm inhabited spaces contrasted with dangerous expedition environments.

### Proposed scope boundaries

- Fixed isometric camera with zoom initially; rotation remains optional.
- Discrete terrain / underground height layers.
- Initial buildings occupy a manageable surface layer rather than unrestricted multilevel construction.
- Roof cutaways and fading foreground objects preserve visibility.
- Village and expedition sites share the same visual language.

### Map views

- Village view: construction, work, storage, and daily life.
- World map: destinations, routes, travel, and planning.
- Expedition-site view: local gathering, exploration, and outpost construction.

Parties continue following orders when the player looks elsewhere. Separate regional maps are preferred over requiring one continuous enormous world.

## 12. Player Interaction

The player directs characters and designates work. They do not perform each axe swing manually.

### Proposed desktop controls

| Input | Action |
|---|---|
| Left-click | Select an object, character, structure, or party. |
| Drag over empty ground | Select multiple characters. |
| Right-click with selection | Issue a contextual order. |
| Shift + order | Queue an order. |
| Escape / empty-ground click | Cancel or clear selection. |
| WASD / middle-mouse drag | Pan camera. |
| Mouse wheel | Zoom. |
| Space | Pause / resume. |

Contextual orders include chop, break stone, haul, build, and move. The cursor previews the action. Dangerous actions require an explicit, readable commitment.

### Work designation

Without selecting workers, paint trees for chopping, mark boulders, draw storage zones, place blueprints, and set work priorities.

Eligible available residents claim tasks automatically. Direct orders temporarily override normal priorities; workers resume their jobs afterward.

### Construction

Blueprint previews display footprint, entrance, costs, available materials, obstructions, and access. Placement creates a job, not a completed building.

### Character panel

Show current task, condition, skills, equipment, work preferences, and expedition assignment. Permit job toggles, priorities, equipment assignment, and direct orders.

Show actionable reasons for inactivity: no tool, unreachable stockpile, missing materials, injury, or rest.

### Expedition interface

Plan at the expedition board or staging area. Confirmation creates preparation tasks. Workers collect supplies and gather visibly. The panel lists ready members and missing items before departure approval.

Select an active party to follow it, inspect status, change its objective, or recall it. At a site, issue local orders through the same interaction model as at home.

### Infrastructure tools

Draw rail routes and review terrain, obstacles, and cost before confirming construction. Connect redstone endpoints and configure their conditions through focused panels.

### Visibility and pacing

- Highlight the exact target before committing.
- Fade roofs and obstructing foreground objects.
- Provide underground layer controls and overlapping-target cycling.
- Offer optional storage, work, route, and redstone overlays.
- Allow orders and blueprints while paused.
- Provide normal and faster simulation speeds.
- Notifications focus the relevant party, resident, or construction site.

## 13. Suggested Prototype Sequence

These are development slices, not one combined minimum viable product.

### Slice 1 — The founding moment

One PC with bare hands, trees, boulders, a crafting bench, wooden and stone tools, a painted stockpile, two houses, gathering, hauling, staged construction, and the first villager's arrival. Validate selection, task orders, stuck-work reporting, and the isometric presentation. Implementation detail: `slice-1-spec.md`.

### Slice 2 — A functioning village

Add job designation, simple food production, a toolsmith job that keeps residents supplied with replacement tools, more residents, and understandable bottlenecks. Implementation detail: `slice-2-spec.md`.
- **Jobs:** every resident has a level in every job that rises with practice, plus on/off switches and priorities.
- **Food:** wheat farms and a kitchen for bread, and sheep hunted for mutton. Hunger is the only need.
- **Beds and wool:** beds make arrivals possible, so wool comes from sheep in the clearing and on a short trip to a meadow off the map.

### Slice 3 — The first expedition

One nearby destination, a small party, provisions, carrying limits, one meaningful discovery, and a visible return/unloading sequence. Implementation detail: `slice-3-spec.md`.
- **Destination:** an old mine a short walk off the map, with stone and coal. It's a small second block map with its own view, and travel to it is a timed walk, like the meadow trip.
- **Discovery:** iron. Iron ore smelted at the fireplace with coal gives iron ingots, which make iron tools at the bench.
- **Danger:** hazards that injure (§8). No mobs or combat.

### Slice 4 — Route investment

Build a minecart connection and demonstrate faster repeated travel without increasing extraction speed.

### Slice 5 — Nether foothold

One portal region, a quartz site, a trading location, and a fortress entrance. Add scout, gather, trade, and construction missions; shelter, retreat rules, injuries, and a rail connection.

### Slice 6 — Specialization and automation

A few explicit enchantment recipes and one redstone chain: detect a supply need, prepare freight, and deliver along a supported route.

## 14. Open Decisions

- Final title, and target platforms beyond desktop. (Resolved: Godot 4 engine; 3D blocks with an orthographic isometric camera.)
- Whether PC incapacitation or death has special consequences. (Resolved for Slice 3, #17: the PC can be hurt but never seriously, and the party always gets them home. Death stays open under "Death, rescue, and difficulty settings".)
- Rest, happiness, and other needs beyond food: depth and pacing. (Resolved for Slice 2, #18: food only.)
- Combat presentation and degree of player control.
- Death, rescue, and difficulty settings.
- Terrain modification, building customization beyond fixed templates, verticality, and camera rotation.
- Resource regeneration and deposit depletion rules. (Partly resolved, #22: hunting grounds such as the sheep meadow regain their animals over time, and the old mine's ore doesn't come back once mined. Tree regrowth, and depletion elsewhere, are still open.)
- Exact party sizes, costs, durations, capacities, and balance values. (Resolved for Slice 3, #23: parties of 1–3, PC eligible. Every number stays provisional.)
- Recruitment beyond free beds, such as requests or an inn. (Resolved for Slice 2, #24: a traveler arrives for each free bed.)
- How often expeditions require intervention and how many can run simultaneously. (Resolved for Slice 3, #25: one expedition at a time, and the game stops for the player only at a discovery and at a serious injury.)
- Outpost staffing and ongoing supply costs.
- Detailed End and Sift systems.
- Enchantment discovery and resource costs.
- How far custom redstone circuits and railway management should extend.
- Scope of original terminology, assets, and worldbuilding versus direct Minecraft references.

## 15. Core Experience to Preserve

The founder personally gathers the materials for two houses. A traveler arrives. Work becomes shared. A small group leaves on the first adventure and returns with something that changes the village. Trails become railways, discoveries become outposts, and the settlement eventually supports journeys into other dimensions.

Growth should be visible, understandable, and rooted in the actions of individual residents.
