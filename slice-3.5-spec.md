# Slice 3.5 Spec — The Meadow Adventure

Companion to `block-village-design-brief.md` and the Slice 1–4 specs. Slice 3.5 builds on Slice 3's site maps, expedition board and planner. This spec only describes what's new or changed. Numbers are **provisional** and collected in the tuning table at the end.

Tracking issue: #144. Decisions settled with the owner (2026-10-21), and recorded in the brief (§5, §8, §9, §13, §14):

| Question | Decision |
|---|---|
| Placement | Its own milestone, **Slice 3.5**, after Slice 3. Slice 3 stays at one destination. |
| The meadow | An **expedition site with its own map**, replacing Slice 2's timed meadow trip. |
| Animals | **Cows, pigs and sheep**, for more meat and leather. |
| Farming | **Pens and breeding** (fed with wheat), so the herds last. Breeding comes off Slice 2's deferred list; shears stay deferred. |
| Leather armor | **Reduces injuries** from expedition hazards. Later, Protection enchantments build on it. |
| Adventures | The expedition board lists every destination. |

Issues not built yet carry their own rules, and add their section here when they're built: #139 (pens and breeding), #140 (leather armor), #141 (grouped inventory in the tally bar) and #142 (the Slice 3.5 playtests).

## 1. Scope and done criteria

From a Slice 3 village, a player can:

- [ ] Pick the meadow from the adventures list and run an expedition there.
- [ ] Hunt cows, pigs and sheep, and bring back a full party's cargo.
- [ ] Pen animals and breed them with wheat from the village farms (#139).
- [ ] Cook beef and porkchops.
- [ ] Craft leather armor, see it worn, and see it lower injury chances in the mine (#140).
- [ ] Read the growing inventory at a glance (#141).
- [ ] Understand every stall from its on-screen reason alone.

## 2. The adventures list (#136)

**The list.** Selecting the expedition board opens it on the **adventures list**: one row per known destination, in the order the sim's `ADVENTURES` names them. Each row shows the destination's name, what's there ("Coal, iron · Level 2 open" or "Cows, pigs, sheep · 21 animals"), the walk each way, its known hazards and its status:
- **Not yet visited** or **Visited**, while nothing is planned;
- **Packing to go**, **Party on the way**, **Party there now** or **Party heading home**, for the destination the party is bound for;
- **Locked: the party is at the meadow** (or "packing for the meadow") for every other row.

**Choosing a row** opens that destination's site report and planner. **All adventures** goes back to the list.

**Built to grow.** Destinations are data: a later one (the Nether, an outpost) is a new entry in `ADVENTURES`, with a site report.

**One expedition at a time** (#25). While a party is packing or out, the rows can't be chosen. The board shows each row's status above the packing or the party.

**Signposts.** The village has a signpost per destination on the matching map edge: the meadow's on the west, the old mine's on the east. Clicking the meadow's signpost opens its adventure on the board (with no board, its panel says a board would know what's past it). The old mine's signpost keeps its route report (Slice 4) and gets a **Plan a trip to the old mine** button.

**Known destinations.** Both the old mine and the meadow become known when the expedition board is built. Each map's known and visited flags are saved.

## 3. The meadow (#137)

**A map of its own.** The meadow is a site map, `"meadow"`, named **Meadow**: 24×24, hand-laid in `game/sim/meadow.gd`. It has open grass, a pond with a muddy bank, scattered trees and a few old fences. The party arrives at the **entrance on the east edge**, the side the village is on, by a signpost pointing home. It appears on the map switcher once it's known.
- **Water** on a site map can't be walked through: the pond is walked around. Only the road's stream (Slice 4) is forded.
- **Fences** stand like rock: nobody walks through them.

**Herds.** Sheep, cows and pigs wander it (§4): 9 sheep, 6 cows and 6 pigs at the start, the most it holds of each.

**Going there.** An expedition like the old mine's: plan the party, provisions and objective at the board; pack, stage and depart. The party carries the packs to the **meadow signpost** on the village's west edge and walks off the map for `MEADOW_WALK`. They're away: not drawn, not working and not getting hungry, and their panels say "On the way to the meadow, N s". The way home is the same walk back, to the same signpost, where they unpack.

**The objective** is "Bring back N" of wool, raw mutton, leather, raw beef or raw porkchops. The planner packs no spare pickaxes for the meadow by default.

**Working it.** At the meadow, the party works by its orders, as at the mine (Slice 3 §11):
- it **marks animals** that give the objective's item, nearest the entrance first, a few at a time, until what's packed, lying about and marked will make the target;
- it **hunts** what's marked (the Hunt order works there too), follows an animal that wanders, picks up the drops and packs them;
- once the objective is met, it packs whatever else is lying about, the other drops of the same animals.

Cargo is limited by **carrying capacity**, not by Slice 2's fixed "2 sheep's worth": a full party with packs brings back far more than the old trip did. The return policy works as at the mine; with nothing left that gives the objective, the party heads home ("nothing left to hunt").

**Hazards** are few and mild, and never serious, so they never stop the game:
- **An angry bull:** hunting a cow has a `BULL_CHANCE` of hurting the hunter.
- **A slippery pond bank:** each step onto the bank has a `SLIP_CHANCE` of a slip.

An injured resident hunts on, slower, and heals in bed at home.

**The site report.** Before anyone has been there as an expedition: "A meadow a short walk west, with sheep, cows and pigs." Once visited: what all the animals would give if hunted (wool, mutton, leather, beef, porkchops), the herds, the two hazards, and "Open grass: room for the whole party".

**Regrowth.** Each species grows back on its own, one animal every `MEADOW_REGROW` for that species, up to its starting herd. New animals wander in at the far west edge. This replaces Slice 2's "the meadow regains 1 sheep every 4 minutes" (#22). Pens and breeding (#139) will beat it.

**Replacing the old trip.** "Send to the meadow" is gone from the resident panel, along with the "Meadow has no sheep left" reason. Wool for more beds comes from the clearing's sheep, then from the meadow adventure.

## 4. Cows and pigs (#138)

**Animals.** Every animal is `{kind: "animal", species, ...}`; the map's `sheep` list holds them all. Cows and pigs live at the meadow only. The clearing keeps its sheep.

| Animal | Drops when hunted | Looks |
|---|---|---|
| Sheep | 1 wool, 1 raw mutton | A woolly white block on a dark face |
| Cow | 1 leather, 2 raw beef | Tall and long, brown with a white middle and muzzle, pale horns |
| Pig | 2 raw porkchops | Low and pink, with a darker snout |

The species are told apart by shape as well as colour. An animal's panel says what it drops.

**The Hunt order** marks every kind in a drag. **Shift-drag** marks only the kind nearest where the drag starts. A queued hunt names the animal ("Hunt a cow").

**Cooking.** The fireplace cooks **cooked beef** (1 raw beef + 1 log) and **cooked porkchop** (1 raw porkchop + 1 log), like mutton, in `COOK_TIME`. Both are meals: the standing order keeps them in stock, the food tally counts them, and an expedition packs them. Hungry residents treat raw beef and porkchops like raw mutton: they're left for the fireplace and eaten only as a last resort.

**Items.** Leather, raw beef, cooked beef, raw porkchop and cooked porkchop, each with a palette colour, a drawing and a tally entry. Leather is a material.

## 5. Saving

Save format **v20** (shared with Slice 3's deeper levels, #132):
- **Animals** carry their species. Older saves' animals are all sheep.
- **The meadow** is a map of its own, with its animals and each species' regrowth time. An older save gets the meadow when it loads, known if the old mine is. What was left of Slice 2's off-map meadow carries over: the new map keeps that many sheep.
- **Anyone away on Slice 2's timed meadow trip** is home at the meadow signpost, with the wool and raw mutton they'd have brought back set down beside it.

## 6. Tuning table (provisional)

| Name | Value | Meaning |
|---|---|---|
| Meadow size | 24×24 | Cells (its layout is hand-laid in `game/sim/meadow.gd`). |
| Herds | 9 sheep, 6 cows, 6 pigs | At the start, and the most the meadow holds of each. |
| `MEADOW_WALK` | 30 s | The walk between the west signpost and the meadow, each way. |
| `MEADOW_REGROW` | sheep 240 s, cows 300 s, pigs 180 s | Seconds for a species to regain one animal. |
| `BULL_CHANCE` | 0.15 | Chance hunting a cow hurts the hunter (never seriously). |
| `SLIP_CHANCE` | 0.03 | Chance of a slip each step onto the pond's bank (never serious). |
| `ANIMAL_DROPS` | sheep 1 wool + 1 mutton; cow 1 leather + 2 beef; pig 2 porkchops | What each animal drops when hunted. |
| `FOOD_VALUE` | raw beef 20, raw porkchop 20, cooked beef 60, cooked porkchop 60 | Hunger a food restores. |
| Cooked beef, cooked porkchop | 1 raw meat + 1 log | At the fireplace, in `COOK_TIME` (3 s). |
