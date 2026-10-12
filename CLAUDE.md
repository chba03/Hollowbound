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
- **Appraisal**, **activation**, **registration**, and **service** (Needs service, cleared
  by repair/recharge) are separate states. None implies or clears another. (Decided/Delegated)
- Type and rarity show on pickup. Traits are revealed only by appraisal, so unappraised
  traits never leave the server. (Delegated)
- Final death drops unregistered relics as ownerless world pickups, keeping ID, traits,
  appraisal, and activation. Registered relics stay owned and carried, are marked Needs
  service, and never enter the world. Only registered relics are protected; ordinary gear
  will drop too once it exists. (Decided; the relic part is implemented)
- The design puts a downed/revive stage before final death. It is not implemented yet, so
  every death is currently final. (Decided, later milestone)
- Exploration and creature encounters lead. PvP is secondary.

## Architecture
- `src/server`: authoritative. Generates specimens and owns inventories, ownership,
  registration, death, and service. `RelicStore` is pure Luau with no Roblox services.
  `claim`, `processDeath`, and `service` must not yield.
- `Defeat` processes each character's death once, through a weak-keyed guard.
  `WorldRelics.spawnDropped` refuses owned specimens and duplicate world parts.
- `src/client`: input and presentation only. It must never decide game state.
- `src/shared`: `Config` (all provisional numbers) and `Net` (remote names).
- Geometry is located through CollectionService tags (`Config.Tags`). Dev geometry (the
  map and the service station) is Studio-only, built at runtime, and must never edit
  other Workspace content.
- Put provisional values in `Config`, not inline. Dev helpers stay Studio-only.

## Milestones
1 (done): relic pickup with server validation, in-memory inventory, HUD, town registration,
camp refuge zone, Studio self-test, and dev keys K and J.
2 (current): final death handler, dropped relics and recovery, protected relics returning
Needs service, free town service station (provisional), HUD service line, and dev key L.
Not yet: persistence (DataStore), the downed/revive stage, ordinary gear, appraisal and
activation flows, service costs, relic abilities, combat, crews, trading, ranks,
procedural terrain, and visible carrying of exceptional finds.

Manual test checklist: `docs/TESTING.md`.
