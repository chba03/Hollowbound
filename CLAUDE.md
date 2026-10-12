# Hollowbound: notes for Claude

Original Roblox exploration and extraction game. Luau + Rojo. Design source:
`docs/Hollowbound_Game_Design_v0_2.pdf`. Its status labels are Decided, Delegated,
Proposed, and Open. Keep those distinctions in code comments and docs. Never treat a
Proposed example or Open value as settled.

## Core rules (preserve these)
- Picking up an item establishes ownership. Crews do not pool loot. (Decided)
- New relics stay **unsecured** until registered in **town**. A camp is a refuge only;
  it never secures loot. (Decided)
- Each relic specimen has a unique ID and **permanent traits**. Repair and recharge restore
  usability and never change traits; no upgrades or rerolls. (Decided)
- **Appraisal**, **activation**, and **registration** are separate states. None implies
  another. (Decided/Delegated)
- Type and rarity show on pickup. Traits are revealed only by appraisal, so unappraised
  traits never leave the server. (Delegated)
- Later: final death drops ordinary carried gear and unregistered relics; registered relics
  return to the owner needing repair or recharge. (Decided, not yet implemented)
- Exploration and creature encounters lead. PvP is secondary.

## Architecture
- `src/server`: authoritative. Generates specimens and owns inventories, ownership, and
  registration. `RelicStore` is pure Luau with no Roblox services and must not yield in
  `claim`.
- `src/client`: input and presentation only. It must never decide game state.
- `src/shared`: `Config` (all provisional numbers) and `Net` (remote names).
- Geometry is located through CollectionService tags (`Config.Tags`). The dev map is
  Studio-only, built at runtime, and must never edit other Workspace content.
- Put provisional values in `Config`, not inline.

## Current milestone: 1, shared test place
Done: relic pickup with server validation, in-memory inventory, HUD, town registration,
camp refuge zone, Studio self-test, and dev keys for range and race tests.
Not yet: persistence (DataStore), death and downed handling, appraisal, activation, relic
abilities, combat, crews, trading, ranks, procedural terrain, and visible carrying of
exceptional finds.

Manual test checklist: `docs/TESTING.md`.
