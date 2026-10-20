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
const CRAFT_TIME := 3.0                 ## Seconds per recipe.
const STAGE_TIME := 10.0                ## Seconds of build work per construction stage.
const ARRIVAL_DELAY := 45.0             ## Seconds after a house with a free bed is finished, per traveler.
const UNREACHABLE_COOLDOWN := 8.0       ## Seconds before retrying a target that couldn't be reached.

## Indexed by tool tier: 0 = bare hands, 1 = wooden, 2 = stone.
const CHOP_TIME := [20.0, 8.0, 5.0]
const BREAK_TIME := [0.0, 10.0, 6.0]    ## Tier 0 can't break stone.
const DURABILITY := [0, 10, 25]         ## Uses before a tool breaks.
