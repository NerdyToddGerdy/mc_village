class_name Tuning
extends RefCounted
## Every tunable number for Slice 1. Values mirror slice-1-spec.md §11 and are provisional.

const TPS := 20                         ## Simulation ticks per second.
const DT := 1.0 / TPS
const SPEEDS := [0, 1, 2, 3]

const CLAIM_EVERY := 2                  ## A land claim for every this many residents beyond the founding pair (issue #187).
const CLAIM_DEPTH := 8                  ## How deep a claimed strip is, in cells.
const CLAIM_STAKES := 4                 ## Sticks a builder plants as boundary stakes.
const MAP_MAX := 64                     ## The village never grows past this many cells a side.
const MAP_W := 32                       ## New games; a loaded save keeps its own size.
const MAP_H := 32
const OPENING_OFFSET := Vector2i(7, 7)  ## Where the original 18×18 opening sits in the bigger map.

const WALK := 3.0                       ## Cells per second.
const CARRY := 4                        ## Items of one type per trip.
const STACK := 16                       ## Items per stockpile or ground cell.
const BOULDER_COBBLE := 6
const SEED := 52                        ## Seeds the sim's random numbers (sheep wandering), so games replay exactly.
const SHEEP_WALK := 0.6                 ## Cells per second.
const SHEEP_PAUSE := [1.0, 4.0]         ## Seconds a sheep stands still between steps (min, max).
const HUNT_TIME := 4.0                  ## Seconds to hunt an animal.
## What each animal drops when hunted (issue #138).
const ANIMAL_DROPS := {"sheep": {"wool": 1, "mutton": 1}, "cow": {"leather": 1, "beef": 2}, "pig": {"porkchop": 2}}

# Hunger (issue #44): 100 is full, 0 is starving.
const HUNGER_EMPTY_TIME := 360.0        ## Seconds for a full resident to reach 0.
const EAT_BELOW := 40.0                 ## Below this, a resident's next job is to eat.
const EAT_UNTIL := 90.0                 ## At a berry bush, keep eating up to this.
const HUNGRY_BELOW := 25.0              ## Below this, work is slower.
const HUNGRY_SPEED := 0.75              ## Work speed while hungry.
const EAT_TIME := 1.5                   ## Seconds to eat one food item or berry.
const FOOD_VALUE := {"berries": 15.0, "mutton": 20.0, "bread": 50.0, "cooked_mutton": 60.0,
	"beef": 20.0, "porkchop": 20.0, "cooked_beef": 60.0, "cooked_porkchop": 60.0}
const BUSH_MAX := 3                     ## Berries a bush holds.
const BUSH_REGROW := 45.0               ## Seconds for a bush to grow one berry back.
# Farms (issue #45).
const PLANT_TIME := 2.0                 ## Seconds to plant one farm cell (no seeds needed).
const HARVEST_TIME := 2.0               ## Seconds to harvest one ripe cell.
const WHEAT_GROW := 120.0               ## Seconds from planting to ripe.
const WHEAT_YIELD := 2                  ## Wheat per harvested cell.
# Autosave (issue #295).
const AUTOSAVE_SECS := 300.0            ## Seconds of play between autosaves.
const AUTOSAVE_MIN_SECS := 120.0        ## A game younger than this isn't autosaved, so a fresh one never replaces a real village's.
# The meadow (Slice 3.5, issues #137, #138). Its herds are laid out in game/sim/meadow.gd.
const MEADOW_ROAD_LEN := 85             ## Cells in the road to the meadow, which sets the walk: 84 cells at WALK is 28 s each way (issue #210).
const MEADOW_REGROW := {"sheep": 240.0, "cow": 300.0, "pig": 180.0}  ## Seconds for a species to regain one animal.
const BULL_CHANCE := 0.15               ## Chance hunting a cow gets the hunter hurt by an angry bull (never seriously).
const SLIP_CHANCE := 0.03               ## Chance of a slip each time someone steps onto the pond's bank (never serious).
# Leather armor (Slice 3.5, issue #140).
const ARMOR_GUARD := {"head": 0.05, "chest": 0.15, "legs": 0.1, "feet": 0.05}  ## Share of hazard injuries each piece turns aside.
const FULL_SET_SERIOUS := 0.5           ## A full set multiplies the chance an injury is serious by this.
const ARMOR_USES := 8                   ## Hazards a leather piece takes before it wears out.
# Pens and breeding (Slice 3.5, issue #139).
const PEN_MIN := 4                      ## A pen's smallest side, fences included (2 cells inside).
const PEN_MAX := 8                      ## A pen's largest side, fences included.
const FENCE_STICKS := 1                 ## Sticks for each fence or gate cell of a pen.
const FENCE_TIME := 2.0                 ## Seconds to put up one fence or the gate.
const FEED_WHEAT := 1                   ## Wheat each animal of a pair eats when it's fed.
const FEED_TIME := 2.0                  ## Seconds to feed a pair.
const BREED_TIME := 30.0                ## Seconds from feeding a pair to its young one.
const BREED_COOLDOWN := 300.0           ## Seconds before a pair that bred can be fed again.
const GROW_TIME := 240.0                ## Seconds for a young animal to grow up; till then it can't be hunted.

# Site maps (Slice 3, issues #102, #103).
const ORE_YIELD := {"coal": 3, "iron": 4, "diamond": 1, "gold": 2, "obsidian": 1, "gravel": 1, "quartz": 2, "glowstone": 2, "lapis": 3, "redstone": 3, "chest": 1}  ## Items an ore block drops (coal; iron ore). The vein pays for the line (Slice 4).
const TORCH_LIGHT := 3.0                ## Cells a torch lights; open cells further from every torch are dark.
# The old mine's deeper levels (issue #132).
const LEVEL_ORE := {"coal": 2, "iron": 1}  ## Ore blocks each level down adds to Level 1's 6 coal and 4 iron.
const LEVEL_RISK := 0.25                ## Each level down raises the cave-in and fall chances by this share of Level 1's.
# The road to the mine (Slice 4, issues #118-#121).
# Worn paths (issue #196): the village's ground packs down where residents walk.
const WEAR_STEP := 1                    ## Wear a resident's step adds to the cell they step onto.
const WEAR_CAP := 100
const WEAR_WORN := 10                   ## Wear at which grass is worn.
const WEAR_DIRT := 30                   ## ...a dirt path.
const WEAR_PACKED := 60                 ## ...a packed path.
const WEAR_DECAY_SECS := 20.0           ## A cell nobody stepped on loses 1 wear this often.
const PATH_SPEED_DIRT := 1.15           ## Walking speed on a dirt path, as a share of WALK.
const PATH_SPEED_PACKED := 1.3
const FORD_SPEED := 0.4                 ## Walking speed wading the stream, before the bridge is built.
const RAILS_PER_SEGMENT := 2            ## Rails one segment of track takes.
const CART_SPEED := 8.0                 ## Cells per second riding a minecart over finished track.
const CART_CAPACITY := 20               ## Items a minecart carries, added to the party's packs once the line is complete.
const LAY_TIME := 4.0                   ## Seconds to lay one rail (issue #122).
const LOAD_RATE := 10.0                 ## Items a second loaded into or out of a cart at a station (issue #123).
const HAND_RATE := 2.0                  ## Items a second each party member unpacks by hand at the signpost.
# Expeditions (Slice 3, issues #106, #107).
const PARTY_MAX := 3                    ## Residents in a party, at most.
const PACK_CAPACITY := 15               ## Items each party member carries, shared by supplies and cargo.
const RETURN_MEALS := 1                 ## Meals per party member kept for the walk home.
const MEAL_FOOD := 50.0                 ## Food a meal is counted as when estimating time on site (bread's).
# Hazards and injuries (issue #110).
const CAVE_IN_CHANCE := 0.5             ## Chance that mining a loose-ceiling block brings it down on the miner.
const CAVE_IN_SERIOUS := 0.5            ## Chance a cave-in's injury is serious.
const FALL_CHANCE := 0.05               ## Chance of a fall each time someone steps onto a ledge in the dark.
const FALL_SERIOUS := 0.25              ## Chance a fall's injury is serious.
const DARK_WORK := 0.7                  ## Work speed in an unlit tunnel.
const INJURED_SPEED := 0.6              ## Walk and work speed while injured.
const HEAL_TIME := [0.0, 120.0, 300.0]  ## Seconds of rest in bed to heal: injured, seriously injured.
const HEAL_NO_BED := 0.5                ## Healing speed resting without a bed of one's own.
# The iron discovery (issue #111).
const FIND_RADIUS := 2                  ## Mining a block this close (in steps) to the hidden vein finds it.
const SURVEY_TIME := 15.0               ## Seconds to investigate the vein.
const SURVEY_USES := 3                  ## Pickaxe uses investigating takes.

# Skills (issue #47/#48, slice-2-spec.md §5).
const SKILL_LEVELS := [8, 25, 50, 90]   ## Experience for levels 2, 3, 4 and 5; one point per finished task.
const SKILL_SPEED := 0.15               ## Work speed added per level above 1, up to the top core level.
const SKILL_CORE := 5                   ## The last level on the fixed table; past it the levels carry on (issue #236).
const SKILL_TAIL_XP := 8.0              ## Past the core, the total experience for level L is SKILL_TAIL_XP * (L - 1) ^ SKILL_TAIL_POWER.
const SKILL_TAIL_POWER := 1.7
const SKILL_TAIL_SPEED := 0.04          ## Speed added by the first level past the core; each next level adds SKILL_TAIL_DECAY times the one before, so speed tends to a ceiling.
const SKILL_TAIL_DECAY := 0.85
const SKILL_TAIL_STEP := 5              ## From level 2 x this, every this many levels give one more item per yield and 20% more tool uses.
const TOOLSMITH_USES := 0.2             ## Extra tool uses per Toolsmith level above 1.
const ARRIVAL_LEVEL := 3                ## A new arrival's level in their one skilled job.
const CRAFT_TIME := 3.0                 ## Seconds per bench recipe.
const BAKE_TIME := 3.0                  ## Seconds to bake bread at the fireplace.
const COOK_TIME := 3.0                  ## Seconds to cook mutton at the fireplace.
const MEAL_STOCK := 6                   ## The fireplace's standing order keeps this many meals stored.
const SMELT_TIME := 5.0                 ## Seconds to smelt one iron ingot at the fireplace (issue #104).
const STAGE_TIME := 10.0                ## Seconds of build work per construction stage.
const ARRIVAL_DELAY := 45.0             ## Seconds after a house with a free bed is finished, per traveler.
# Workstations (issue #177).
const WORK_START_RADIUS := 8.0          ## A new chopping block or mason's bench starts with the cells this near it (issue #203).
const WORK_REACH := 12.0                ## The furthest from its workstation a painted work area may reach.
const WORK_STORE := 20                  ## Logs or cobblestone a workstation's pile holds.
const KEEP_STOCK := 20                  ## A new workstation's keep-stock target: gatherers stop once the village has this many.
const WHEAT_KEEP := 20                  ## The farm's keep-stock target: farmers stop harvesting and planting once the village has this much wheat (issue #269).
const KEEP_STEP := 5                    ## The keep-stock target's step in the workstation's panel.
## The cargo priority list a location starts with (issue #185): the items it can give, best first, each with the
## amount wanted (0: as much as fits). Only the items the village knows the location gives are listed.
const CARGO_DEFAULTS := {
	"mine": [["iron_ore", 8], ["coal", 8], ["cobble", 0]],
	"meadow": [["wool", 6], ["leather", 0], ["beef", 0], ["porkchop", 0], ["mutton", 0]],
}
const SHAFT_COST := {"plank": 8, "stone_brick": 6}  ## Upgrading a mason's bench into a mineshaft (issue #204).
const SHAFT_DIG := 12.0                 ## Seconds of digging for 1 cobblestone at a mineshaft: slower than breaking boulders.
const SHAFT_WEAR_EVERY := 6             ## Cobblestone dug per use of a pickaxe, as a boulder's yield.
const MAKE_KEEP := {"chopping_block": 20, "mason_bench": 10}  ## A workstation's standing order (issue #178): keep this many planks or stone bricks.
const MAKE_STEP := 5                    ## Its step in the workstation's panel.
const CHESTS := 4                       ## Chests a storehouse holds (issue #189).
const CHEST_STACKS := 9                 ## Stacks a chest holds, each of any item.
const RADIAL_NEARBY := 4                ## "Chop all trees nearby" marks within this many cells (issue #176).
const HERD_FLOOR := 2                   ## Wild animals of each species hunters leave in the village (issue #183), until changed on the jobs board.
const SAPLINGS := 1                     ## Saplings a felled tree drops.
const SAPLING_EXTRA := 0.3              ## Chance a felled tree drops one more.
const SAPLING_GROW := 300.0             ## Seconds from planting a sapling to a full tree.
const PLANT_TREE_TIME := 2.0            ## Seconds to plant a sapling.
const UNREACHABLE_COOLDOWN := 8.0       ## Seconds before retrying a target that couldn't be reached.

## Indexed by tool tier: 0 = bare hands, 1 = wooden, 2 = stone, 3 = iron (issue #104).
const CHOP_TIME := [20.0, 8.0, 5.0, 3.5, 2.5]
const BREAK_TIME := [0.0, 10.0, 6.0, 4.0, 2.5]  ## Tier 0 can't break stone.
const DURABILITY := [0, 10, 25, 60, 150]     ## Uses before a tool breaks.
const ORE_PICK_TIER := {"diamond": 3, "obsidian": 4, "lapis": 3, "redstone": 3}  ## The pickaxe tier an ore needs: iron for diamonds, a diamond pickaxe for obsidian (issue #146).
const GRAVEL_FLINT_CHANCE := 0.5      ## Chance a broken gravel block drops a flint (issue #146).
const PORTAL_OBSIDIAN := 10           ## Obsidian in a portal's frame (issue #147).
const PORTAL_LIGHT_TIME := 4.0        ## Seconds to light a finished portal with flint and steel.
const PORTAL_GUTTER_CHANCE := 0.2     ## Chance the portal goes out while a party is through it (issue #148).
const LAVA_CHANCE := 0.04             ## Chance of a burn each time someone steps onto a cell beside lava (issue #149).
const LAVA_SERIOUS := 0.25            ## Chance a lava burn is serious.
const FIRE_BURN_TIME := 2.0           ## Seconds someone keeps burning after they leave a fire.
const FIRE_CHANCE := 0.4              ## Chance of a burn each second someone is alight.
const FIRE_SERIOUS := 0.2             ## Chance a fire burn is serious.
const HEAT_STEP_COST := 250           ## A step onto a cell beside lava or fire costs this, against 100 for open ground: paths go round.
const SWORD_USES := 40                ## Hits an iron sword lands before it breaks (issue #150).
const IRON_ARMOR_USES := 20           ## Blows an iron chestplate takes before it wears out.
const IRON_GUARD := 0.35              ## Share of injuries an iron chestplate turns aside (a leather tunic: 0.15).
const BARE_DAMAGE := 1                ## Damage of a blow with no sword.
const SWORD_DAMAGE := 4               ## Damage of a blow with an iron sword.
const HIT_TIME := 1.2                 ## Seconds between a guard's blows, at Guard level 1.
const HIT_CHANCE := 0.6               ## Chance a blow lands at Guard level 1, and 0.08 more for each level above.
const CREATURE_SPEED := 1.4           ## Cells a creature walks in a second (issue #151).
const AVOID_RANGE := 3                ## How close a hostile creature gets before someone who isn't a guard moves away.
const SELF_DEFENSE_RANGE := 2         ## How close a creature must be for a guard to fight it when the party avoids combat.
const ENGAGE_RANGE := 8               ## How far a guard goes after a creature when the party doesn't avoid combat.
const SHELTER_COST := {"cobble": 4, "plank": 6}   ## What a party carries to build the landing's shelter (issue #152).
const SHELTER_BUILD_TIME := 10.0      ## Seconds to build it.
const GLOWSTONE_TIME := 3.0           ## Seconds to break a block of glowstone, by hand or with any tool (issue #155).
const RESCUE_WINDOW := 240.0          ## Seconds a stranded party shelters before it sets off on its own (issue #158).
const STRAND_WAIT := 20.0             ## Seconds the party waits at a dark portal with no flint and steel before it's stranded.
const NETHER_BRIDGE_PLANKS := 8       ## Planks a bridge over a Nether route's lava channel or gap takes (issue #159).
const NETHER_BRIDGE_TIME := 10.0      ## Seconds to build it.
const PORTAL_LINE_RAILS := 6          ## Rails the portal line's Nether side takes, from the portal's far side to the landing station (issue #168).
const PORTAL_STATION_REACH := 6       ## How far from the portal frame the village station may stand, in cells.
const FREIGHT_TRIP_TIME := 14.0       ## Seconds a freight cart takes to run the portal line one way (issue #169).
const FREIGHT_CROSS := 0.3            ## How far along the trip the portal is, as a share of it.
const CACHE_CAPACITY := 60            ## Items the shelter's cache holds in all (issue #169).
const DUST_PER_REDSTONE := 4          ## Cells of dust one redstone dust lays (issue #170).
const DUST_TIME := 1.5                ## Seconds to lay one cell of dust.
const SENSOR_ITEMS := ["food", "iron_ingot", "plank", "cobble"]   ## What a cache sensor can watch (issue #171).
const SENSOR_BELOW := 10              ## The threshold a new cache sensor starts with.
const FREIGHT_CAPACITY := 30          ## Items a freight cart carries (issue #172).
const FREIGHT_LIST := {"bread": 10, "iron_ingot": 2}   ## What a new loader loads: a full load (provisional).
const DISPATCHER_REACH := 4           ## How far from the portal station the dispatcher may stand (issue #173).
const EFFICIENCY_SPEED := 1.3         ## Work speed of an Efficiency tool (issue #167).
const UNBREAKING_WEAR := 0.5          ## Share of wear an Unbreaking item takes.
const PROTECTION_CUT := 0.3           ## Share of creature injuries Protection armor adds to what it turns aside, as a cut in the chance.
const FIRE_PROTECTION_CUT := 0.5      ## Cut in the chance of a burn from fire or lava for Fire protection armor.
const ENCHANT_TIME := 12.0            ## Seconds an Enchanter works an enchantment, at level 1 (issue #166).
const FLINT_STEEL_USES := 8           ## Times a flint and steel lights something before it's spent (issues #146, #147).
const DIAMOND_PICK_TIER := 3            ## The pickaxe tier diamond ore needs: iron (issue #186).
