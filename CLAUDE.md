# Hollowbound: notes for Claude

Original Roblox exploration and extraction game. Luau + Rojo. Design source:
`docs/Hollowbound_Game_Design_v0_2.pdf`. Its status labels are Decided, Delegated,
Proposed, and Open. Keep those distinctions in code comments and docs. Never treat a
Proposed example or Open value as settled.

## Ownership and repository workflow
- Hollowbound is the owner's **solo-developed** game (Carlos Abreu). Every milestone extends
  one continuing project in this repository: `https://github.com/chba03/Hollowbound`
  (owner `chba03`, verified 2026-10-16 via GitHub's API: the account GitHub links to the
  owner's commits).
- **Excluded work:** the brother's separate line, branch `milestone-2` (commits `1c01b75`
  and `698956d`, rim town, store, ropes, creatures, terrain), is not part of this project.
  Never merge, cherry-pick, or copy from it, and never delete or rewrite his branches.
  Decide by checking history and content, not by branch names or authors alone.
  (Audit 2026-10-16: not an ancestor of the owner's line; the only identical files are the
  upstream ProfileStore and its license, fetched independently from MadStudioRoblox.)
- **Commit and push are authorized** for verified project work: normal commits on the
  current feature branch, pushed to `origin` for that branch only. Never force-push, mirror
  all branches, or push other people's branches. Label incomplete work honestly (WIP).
  After pushing, confirm with `git ls-remote origin refs/heads/<branch>` that the remote
  commit matches local `HEAD`.
- Keep credentials, caches, build output, and backup archives out of the repository (it
  is public). Backups live in `C:/Users/carlo/HollowboundBackups/`.
- **Branches:** `main` holds the owner-verified integrated version. Each milestone is
  built on a feature branch that starts from the latest integrated version, and is merged
  into `main` only after the owner confirms its Studio tests pass. Line so far:
  `0aaf004` milestone 1 (main) -> `25043f2` milestone 2 -> milestone 3 -> milestone 4 ->
  `feature/vertical-world` (milestone 5, work in progress, not yet owner-tested).
- **Authoritative documents:** `docs/Hollowbound_Game_Design_v0_2.pdf` and the owner's
  milestone briefs. The older concept v0.1 PDF is not authoritative and must not override
  newer decisions. No art guide or reference image is in the repository yet: ask for it,
  and label any palette or visual choices made without it as provisional.

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
  kept) and all ordinary items. Registered relics stay owned and equipped, marked Needs
  service with charges emptied, and never enter the world. (Decided)
- Combat and creature damage go only through `Vitals.damagePlayer`, which downs instead
  of killing (Decided: downed stage). Only engine death (bleedout, reset, void) and the
  field-departure rule reach final death, and only once, through `Defeat`.
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

## Milestone 4 rules (provisional, from the owner's brief)
- Expedition phases Town / Exploring / AtCamp: leaving town starts one run; camps neither
  start nor end one; town or final death ends it once. No time limit. Ending a run never
  touches relic states.
- Downed: 30 s bleedout, crawl, no attacks, heals, relic actions, or pickups. Revive is
  server-timed (4 s), re-validated every frame, one helper per down. Self-rescue: one kit,
  one success per run (allowance on the run, not the character).
- Explicit regeneration: none while exploring; town and camps only.
- Melee: the client sends only "Attack"; the server picks hits (range, arc, line of sight,
  once per target per swing). PvP damage is off. No parry or combo system yet.
- Creatures: one archetype, variants in config only (`CreatureBrain` for all). They never
  enter or chase into town or camps, ignore downed explorers, leash and reset at the den.
- Guardian caches: locked until the guardian falls; exactly one reward per cycle from
  `SpecimenFactory`, placed as a normal world relic (first pickup owns it). Leaving never
  resets an encounter.
- Ordinary items (weapon, bandages, self-rescue kits) are session-only, bounded by
  capacity and refill limits, and dropped as one unique crate on final death. No
  currency, vendors, stash, or crafting.
- Protected zones (`Config.ProtectedZones`): no combat or creature damage, no attacking
  from inside, and creatures inside cannot be damaged. Camps still never register, bank,
  recharge, or reset allowances. PvP aggressor/defender camp rules are documented for later.

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
  once, then runs final-death hooks (supplies crate, run end). `WorldRelics.spawnDropped`
  and `spawnReward` refuse owned specimens and duplicate world parts.
- Milestone 4 pattern: pure, Lune-testable cores (`VitalsCore`, `ExpeditionCore`,
  `BusyCore`, `RescueCore`, `GearStore`, `MeleeRules`, `CreatureBrain`, `EncounterCore`)
  plus thin Roblox modules (`Vitals`, `Expedition`, `Busy`, `Rescue`, `Gear`, `Combat`,
  `Creatures`, `Encounters`, `FieldActions`). Put new rules in a core and test them there.
- Stale callbacks: anything delayed captures charId, downToken, runId, swingId, cycle, or
  pathToken and re-checks it before acting.
- `Guard.checkActive` = loaded session + standing character; use it for every
  world, inventory, or combat action (self-rescue uses `Guard.check` plus Downed).
- `src/client`: input and presentation only. All input goes through `Actions`
  (keyboard, controller, touch); the HUD renders `RelicView.state`.
- `src/shared`: `Config` (all provisional numbers), `Net` (remote names), `LoadoutRules`.
- Geometry is found through CollectionService tags (`Config.Tags`), including the
  milestone 4 markers `HB_CreatureSpawn` (Variant, EncounterId) and `HB_RelicCache`
  (EncounterId); placement rules are in README section 4. Legacy dev geometry (map,
  service and supply stations, relic fixtures C-E, encounter arena) is Studio-only and
  built at runtime as separate models. Never clear Workspace, erase global Terrain,
  overwrite unrelated models, or map all of Workspace through Rojo.
- **Source control vs the Studio place:** Git tracks code, `Config`, and the world
  definition (`src/server/World/`: Layout, Planner, Installer). The installed world model
  in Workspace, any hand-made art under `HollowboundWorld.AuthoredDecor`, Lighting edits,
  and place settings live only in the saved Studio place: save the place (and export
  models you care about) separately. A Git commit never saves Studio-built content.
- Put provisional values in `Config`, not inline. Dev helpers stay Studio-only.

## Milestones
1 (done): pickup, registration, camp refuge, self-test, dev keys K and J.
2 (done): final death, dropped relics and recovery, protected relics Needs service,
town service, dev key L.
3 (done): saved registered relics (ProfileStore), appraisal and activation, 3-slot
loadout, Windhook and Echo Lens with charges and cooldowns, cross-platform HUD, mock
test suites (`src/server/Tests`).
4 (done, owner-playtested): expedition lifecycle, Vitals damage interface,
downed/revive/self-rescue, starter melee, Thornback creature and guardian with a locked
relic cache, ordinary supplies and supply crates, camp protection, field HUD, Survival and
Creature test suites.
5 (in progress on `feature/vertical-world`, not owner-tested): vertical world (rim town
around the abyss, first depth), edit-mode world installer, art and animation pass.
Not yet: ranks/XP, food and ascent strain, ranged combat, crews, PvP, trading, currency,
procedural depths, full reconnect (bodies, camp pause/resume), saving ordinary items.

Tests: `docs/TESTING.md` (Part A mock, B two-client Studio, C real persistence, D script).
Run the mock suites after every logic change: `lune run tools/run-tests` (exit 0 = all
pass). The harness stubs only game:GetService, script, Random, Color3, and warn; keep
tested modules free of other Roblox APIs, or extend the harness deliberately.
Syntax check: `luau-analyze` from the official luau-lang/luau release (Roblox globals
show as unknown; only SyntaxError lines matter without Roblox type definitions).
