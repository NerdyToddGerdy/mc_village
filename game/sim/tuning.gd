class_name Tuning
extends RefCounted
## Every tunable number for Slice 1. Values mirror slice-1-spec.md §11 and are provisional.

const TPS := 20                         ## Simulation ticks per second.
const DT := 1.0 / TPS
const SPEEDS := [0, 1, 2, 3]

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
# The meadow (Slice 3.5, issues #137, #138). Its herds are laid out in game/sim/meadow.gd.
const MEADOW_WALK := 30.0               ## Seconds walking between the west signpost and the meadow, each way.
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
const ORE_YIELD := {"coal": 3, "iron": 4}  ## Items an ore block drops (coal; iron ore). The vein pays for the line (Slice 4).
const TORCH_LIGHT := 3.0                ## Cells a torch lights; open cells further from every torch are dark.
# The old mine's deeper levels (issue #132).
const LEVEL_ORE := {"coal": 2, "iron": 1}  ## Ore blocks each level down adds to Level 1's 6 coal and 4 iron.
const LEVEL_RISK := 0.25                ## Each level down raises the cave-in and fall chances by this share of Level 1's.
# The road to the mine (Slice 4, issues #118-#121).
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
const SKILL_SPEED := 0.15               ## Work speed added per level above 1.
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
const WORK_RADIUS := 8.0                ## Cells from a chopping block or mason's bench that its gatherers work on their own.
const WORK_STORE := 20                  ## Logs or cobblestone a workstation's pile holds.
const KEEP_STOCK := 20                  ## A new workstation's keep-stock target: gatherers stop once the village has this many.
const KEEP_STEP := 5                    ## The keep-stock target's step in the workstation's panel.
const HERD_FLOOR := 2                   ## Wild animals of each species hunters leave in the village (issue #183), until changed on the jobs board.
const SAPLINGS := 1                     ## Saplings a felled tree drops.
const SAPLING_EXTRA := 0.3              ## Chance a felled tree drops one more.
const SAPLING_GROW := 300.0             ## Seconds from planting a sapling to a full tree.
const PLANT_TREE_TIME := 2.0            ## Seconds to plant a sapling.
const UNREACHABLE_COOLDOWN := 8.0       ## Seconds before retrying a target that couldn't be reached.

## Indexed by tool tier: 0 = bare hands, 1 = wooden, 2 = stone, 3 = iron (issue #104).
const CHOP_TIME := [20.0, 8.0, 5.0, 3.5]
const BREAK_TIME := [0.0, 10.0, 6.0, 4.0]  ## Tier 0 can't break stone.
const DURABILITY := [0, 10, 25, 60]     ## Uses before a tool breaks.
