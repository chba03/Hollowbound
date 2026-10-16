# Hollowbound: notes for Claude

Original Roblox exploration and extraction game. Luau + Rojo. Design source:
`docs/Hollowbound_Game_Design_v0_2.pdf`. Its status labels are Decided, Delegated,
Proposed, and Open. Keep those distinctions in code comments and docs. Never treat a
Proposed example or Open value as settled.

Branch line: `feature/relic-systems` builds on `feature/relic-recovery` (milestones 1-2).
The separate `milestone-2` branch line (rim town, store, creatures) is intentionally not
included; the owner chose to ignore it for now. Do not merge it in unasked.

## Core rules (preserve these)
- Picking up an item establishes ownership. Crews do not pool loot. (Decided)
- New relics stay **unsecured** until registered in **town**. A camp is a refuge only;
  it never secures loot. (Decided)
- Each relic specimen has a unique ID and **permanent traits**, generated once on the
  server. Repair and recharge restore usability and never change traits; no upgrades or
  rerolls. Loading never regenerates a specimen. (Decided)
- **Appraisal** (reveals traits to the owner), **activation** (enables use for types that
  need it), **registration** (protection), and **service** (Needs service, condition,
  charges) are separate. None implies, clears, or refills another. (Decided/Delegated)
- Type and rarity show on pickup. Unappraised traits never leave the server. (Delegated)
- A usable unregistered relic can be equipped and used on the same expedition;
  appraisal is not required for use. It stays lootable on final death.
- Final death drops unregistered relics as the same ownerless specimens (all states
  kept). Registered relics stay owned and equipped, marked Needs service with charges
  emptied, and never enter the world. (Decided) Every death is final until the
  downed/revive stage exists (Decided, later milestone).
- Only registered relics are saved. Never save or restore unregistered inventory.
- Exploration and creature encounters lead. PvP is secondary.

## Milestone 3 rules (provisional, from the owner's brief)
- Loadout: 3 slots, at most 1 Exceptional (`Config.Loadout`; rarity -> slot class). The
  client binds keys for 3 slots (`Actions`).
- Windhook needs town activation; Echo Lens works immediately (`requiresActivation`).
- Abilities have charges (per specimen, saved) and cooldowns (per player and ability,
  saved as unix deadlines). Swaps, copies, death, and rejoin never reset cooldowns.
- Appraisal, activation, and service are free for testing; costs are Open.
- Temporary departure rule (not the final reconnect design): leaving outside town
  applies final death once before cleanup; leaving in town keeps registered relics as
  they are and releases unregistered ones into the world; a known shutdown saves as is
  with no penalties.

## Architecture
- `src/server`: authoritative. `RelicStore` is pure Luau, the live state, and never
  yields. Storage calls happen in the backend, never between a store check and its change.
- Persistence: `Sessions` (gate, commit snapshot with `Revision`, monotonic save
  confirmation, anti-wipe guard, quarantine of unreadable records, depart, lost session)
  over a backend interface. `ProfileBackend` is the only module requiring the vendored
  ProfileStore (pinned in `docs/DEPENDENCIES.md`). `MockBackend` is **test-only**; never
  use it in gameplay code. No silent mock: Studio without API access uses
  `ProfileStore.Mock` only on purpose, labelled MOCK, otherwise loading fails.
- Every gameplay mutation asks `Guard.check(player)` first.
- Client requests go through `RelicActions` (type-checked, rate limited). Abilities never
  accept positions or directions from the client.
- `Defeat` processes each character's death once (weak-keyed guard) and each departure
  once. `WorldRelics.spawnDropped` refuses owned specimens and duplicate world parts.
- `src/client`: input and presentation only. All input goes through `Actions`
  (keyboard, controller, touch); the HUD renders `RelicView.state`.
- `src/shared`: `Config` (all provisional numbers), `Net` (remote names), `LoadoutRules`.
- Geometry is found through CollectionService tags (`Config.Tags`). Dev geometry
  (map, service station, relic fixtures C-E) is Studio-only, built at runtime as separate
  models, and must never edit other Workspace content. Do not touch terrain, lighting,
  models, world generation, or add a Rojo Workspace mapping.
- Put provisional values in `Config`, not inline. Dev helpers stay Studio-only.

## Milestones
1 (done): pickup, registration, camp refuge, self-test, dev keys K and J.
2 (done): final death, dropped relics and recovery, protected relics Needs service,
town service, dev key L.
3 (current): saved registered relics (ProfileStore), appraisal and activation, 3-slot
loadout, Windhook and Echo Lens with charges and cooldowns, cross-platform HUD, mock
test suites (`src/server/Tests`).
Not yet: ranks, currency, trading, creatures and combat, downed/revive, procedural world,
full reconnect (bodies, camp pause/resume), ordinary gear.

Tests: `docs/TESTING.md` (Part A mock, B two-client Studio, C real persistence, D script).
Run the mock suites after every logic change: `lune run tools/run-tests` (exit 0 = all
pass). The harness stubs only game:GetService, script, Random, Color3, and warn; keep
tested modules free of other Roblox APIs, or extend the harness deliberately.
Syntax check: `luau-analyze` from the official luau-lang/luau release (Roblox globals
show as unknown; only SyntaxError lines matter without Roblox type definitions).
