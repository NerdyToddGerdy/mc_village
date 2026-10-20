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
# Skills (issue #47/#48, slice-2-spec.md §5).
const SKILL_LEVELS := [8, 25, 50, 90]   ## Experience for levels 2, 3, 4 and 5; one point per finished task.
const SKILL_SPEED := 0.15               ## Work speed added per level above 1.
const TOOLSMITH_USES := 0.2             ## Extra tool uses per Toolsmith level above 1.
const ARRIVAL_LEVEL := 3                ## A new arrival's level in their one skilled job.
const CRAFT_TIME := 3.0                 ## Seconds per bench recipe.
const BAKE_TIME := 3.0                  ## Seconds to bake bread at the fireplace.
const COOK_TIME := 3.0                  ## Seconds to cook mutton at the fireplace.
const MEAL_STOCK := 6                   ## The fireplace's standing order keeps this many meals stored.                 ## Seconds per recipe.
const STAGE_TIME := 10.0                ## Seconds of build work per construction stage.
const ARRIVAL_DELAY := 45.0             ## Seconds after a house with a free bed is finished, per traveler.
const UNREACHABLE_COOLDOWN := 8.0       ## Seconds before retrying a target that couldn't be reached.

## Indexed by tool tier: 0 = bare hands, 1 = wooden, 2 = stone.
const CHOP_TIME := [20.0, 8.0, 5.0]
const BREAK_TIME := [0.0, 10.0, 6.0]    ## Tier 0 can't break stone.
const DURABILITY := [0, 10, 25]         ## Uses before a tool breaks.
