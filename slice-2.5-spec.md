# Slice 2.5: Night and the iron golem

Built after Slice 7 was decided, from the decisions on #66 (research) and the issues #357 to #360. It only describes what's new since Slice 2. Rules live in `game/sim/night.gd`; every number is in `game/sim/tuning.gd`.

## The day (#357)
- A day is **720 s** (12 minutes): the first **450 s** are day, the last **270 s** night. Light eases over **20 s** at dusk and dawn.
- It runs on sim ticks (it follows the speed buttons and stops when paused). `stats.day_zero` is the tick a morning began on; a new game, and an older save when it loads, start just past the dawn light.
- Night is for looks and mood: the sun dims and turns blue, the sky darkens, and the top bar says "Day N · night". Residents keep working. There's no sleep and no rest need. Underground maps don't change.

## The night's mobs (#358)
- From **3 residents** a **wave** comes in from the village's edge each night: zombies, skeletons and spiders (no creepers). A wave is **2 mobs, plus 1 for every 2 residents past the third, plus 1 per Guard**, at most **9**. One wave a night, saved as `stats.wave_day`.
- Night mobs notice a resident anywhere in the village (`MOB_SIGHT`). They stay for the night; at dawn what's left slinks away.
- Their drops (rotten flesh; bones and arrows; string) lie where they fell and are hauled to a stockpile like anything loose.

## The iron golem (#359)
- At **3 residents** an iron golem appears by itself and patrols within `PATROL_RADIUS` of the village's middle. Only one. It goes for the nearest mob and knocks it out; it never hurts a resident and nothing hurts it. It isn't a resident.

## Village combat (#360)
- A mob's blow uses the injury path of hazards (`Sim._hazard`): armor turns some aside and a serious injury needs rest. Nobody dies (#20).
- Visible auto-combat, no per-blow control. The golem and **Guards** (and Ada) go after mobs within `GUARD_DEFEND_RANGE`; **anyone else** fights back when a mob is within `FIGHT_BACK_RANGE`, with blows `FIGHT_BACK_SLOW` times slower. A resident turned from their work goes back to it afterwards; the injured rest.

## Tuning
| Name | Value | Meaning |
|---|---|---|
| `DAY_SECONDS` | 720 | A whole day |
| `NIGHT_AT` | 450 | Seconds into the day when night falls |
| `DUSK_SECONDS` | 20 | Light change at dusk and dawn |
| `NIGHT_FROM` | 3 | Residents before mobs come |
| `GOLEM_AT` | 3 | Residents before the golem appears |
| `WAVE_BASE` | 2 | Mobs in the smallest wave |
| `WAVE_PER_RESIDENTS` | 2 | One more mob per this many residents past the third |
| `WAVE_MAX` | 9 | The most mobs a night brings |
| `MOB_SIGHT` | 40 | How far a night mob notices a resident |
| `GOLEM_SPEED` | 1.2 | Cells a second |
| `GOLEM_DAMAGE` | 4 | Its blow |
| `GOLEM_HIT` | 1.2 | Seconds between blows |
| `GOLEM_SIGHT` | 30 | How far it goes after a mob |
| `PATROL_RADIUS` | 9 | How far it wanders |
| `GUARD_DEFEND_RANGE` | 14 | How far a guard goes after a mob |
| `FIGHT_BACK_RANGE` | 2 | How close a mob must be for anyone else to fight it |
| `FIGHT_BACK_SLOW` | 2.2 | Slower blows for anyone but a guard |

## Saves
Format version 64: `stats.day_zero`. The mobs and the golem are in the village map's `creatures`, which was already saved. An older save loads on a morning; if it has 3 or more residents the golem appears on its first tick.
