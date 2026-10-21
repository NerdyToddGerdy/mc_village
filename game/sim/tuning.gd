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
const HUNT_TIME := 4.0                  ## Seconds to hunt a sheep.

# Hunger (issue #44): 100 is full, 0 is starving.
const HUNGER_EMPTY_TIME := 360.0        ## Seconds for a full resident to reach 0.
const EAT_BELOW := 40.0                 ## Below this, a resident's next job is to eat.
const EAT_UNTIL := 90.0                 ## At a berry bush, keep eating up to this.
const HUNGRY_BELOW := 25.0              ## Below this, work is slower.
const HUNGRY_SPEED := 0.75              ## Work speed while hungry.
const EAT_TIME := 1.5                   ## Seconds to eat one food item or berry.
const FOOD_VALUE := {"berries": 15.0, "mutton": 20.0, "bread": 50.0, "cooked_mutton": 60.0}
const BUSH_MAX := 3                     ## Berries a bush holds.
const BUSH_REGROW := 45.0               ## Seconds for a bush to grow one berry back.
# Farms (issue #45).
const PLANT_TIME := 2.0                 ## Seconds to plant one farm cell (no seeds needed).
const HARVEST_TIME := 2.0               ## Seconds to harvest one ripe cell.
const WHEAT_GROW := 120.0               ## Seconds from planting to ripe.
const WHEAT_YIELD := 2                  ## Wheat per harvested cell.
# The sheep meadow (issue #50). Regrowth is the proposed default for open decision #22.
const MEADOW_SHEEP := 8                 ## Sheep in the meadow at the start, and the most it holds.
const MEADOW_TRIP := 90.0               ## Seconds a resident is away on a trip.
const MEADOW_TAKE := 2                  ## Sheep's worth each resident brings back (wool and raw mutton each).
const MEADOW_REGROW := 240.0            ## Seconds for the meadow to regain one sheep.

# Site maps (Slice 3, issues #102, #103).
const MINE_TRIP := 60.0                 ## Seconds to walk between the village and the old mine.
const ORE_YIELD := {"coal": 2, "iron": 2}  ## Items an ore block drops (coal; iron ore).
const TORCH_LIGHT := 3.0                ## Cells a torch lights; open cells further from every torch are dark.
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
const UNREACHABLE_COOLDOWN := 8.0       ## Seconds before retrying a target that couldn't be reached.

## Indexed by tool tier: 0 = bare hands, 1 = wooden, 2 = stone, 3 = iron (issue #104).
const CHOP_TIME := [20.0, 8.0, 5.0, 3.5]
const BREAK_TIME := [0.0, 10.0, 6.0, 4.0]  ## Tier 0 can't break stone.
const DURABILITY := [0, 10, 25, 60]     ## Uses before a tool breaks.
