# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

The Godot project hasn't started yet. The repo holds design docs and a browser prototype for **Block Village** (working title), an isometric settlement simulation inspired by Minecraft:
- `block-village-design-brief.md` is the vision and decisions document.
- `slice-1-spec.md` is the implementation spec for the current slice. It covers architecture, the job system, recipes, construction, controls, saving, the tuning table, and the "carpenter's chalk" UI language.
- `prototype/founding.html` is a playable, single-file browser prototype of Slice 1. Open it directly in a browser; it has no build step or dependencies beyond Google Fonts. It's used to test rules before they go into the spec. When a playtest changes a rule, update both the prototype and the spec. Its live copy is published as a claude.ai artifact.

There's no build system or test suite yet. Update this file with commands once the Godot project exists.

## Technical decisions

- Godot 4 with statically typed GDScript. Real 3D block geometry viewed through a fixed isometric orthographic camera.
- **The sim and the view are kept separate.** `sim/` is plain data and fixed-tick logic: no Nodes, and it must run headless. `view/` only reads sim state and submits commands. It never mutates the sim directly. The sim reports one-off happenings through a per-tick event list.
- Every tunable number goes in the spec's tuning table and in data resources, never hardcoded in logic.

## The design docs are the source of truth

- The brief separates **core decisions** from **proposed** details. Treat core decisions as fixed. Treat proposed mechanics and all numbers as provisional, not final balance.
- Section 14 ("Open Decisions") lists questions that are deliberately still open, including platforms beyond desktop, combat, needs depth, and party sizes. Don't quietly settle any of them in code or docs. Raise the choice with the user.
- Minecraft-derived content (Nether, End, the Sift, enchantments, redstone, minecarts) is an adaptation and doesn't have to match Minecraft's exact rules. How much original versus directly referenced terminology to use is still an open decision.

## Core loop and principles

Gather locally → build and support the village → recruit residents → equip an expedition → explore and recover supplies → unlock improvements → expand infrastructure → take on more ambitious expeditions.

Cross-cutting principles that design and implementation work should keep:
- Work and material movement are visible in the world. Resources are gathered, hauled, stored, processed, and consumed. Nothing teleports into a stockpile.
- Direct orders to characters gradually give way to delegation. Designations (chop, break, haul, build) create jobs that eligible residents claim. Direct orders override priorities only for a while.
- Idle or stalled work always reports an actionable reason: missing materials, no tool, unreachable stockpile, unavailable labor, injury, or rest.
- Setbacks can be recovered from. The home village stays useful throughout progression.
- Residents sent on expeditions are absent from village labor.
- Minecart routes speed up travel in both directions but don't increase extraction speed.

## Development order

Section 13 defines prototype slices that are built one at a time, not as a single MVP:
1. Founding moment: bare-handed PC, crafting bench, tools, a stockpile, two houses, and the first villager's arrival (see `slice-1-spec.md`).
2. A functioning village: jobs, food, tools, more residents, and bottlenecks.
3. The first expedition.
4. Route investment (minecarts).
5. A Nether foothold.
6. Enchantments and one redstone automation chain.

Scope new work to the current slice. Don't build ahead into later slices' systems.
