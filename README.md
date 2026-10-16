# Hollowbound: milestone 3

A shared test place for the relic system: pickup and town registration, final death with
dropped and protected relics, and town service. Milestone 3 adds **saved registered
relics**, **appraisal and activation**, a **3-slot loadout**, and two working abilities
(**Windhook** and **Echo Lens**), with keyboard, controller, and touch controls.
Built with Luau, Roblox Studio, Rojo, and ProfileStore.

Design source: [`docs/Hollowbound_Game_Design_v0_2.pdf`](docs/Hollowbound_Game_Design_v0_2.pdf).
Core rules and the current milestone: [`CLAUDE.md`](CLAUDE.md).
Tests (mock, two-client Studio, and real persistence): [`docs/TESTING.md`](docs/TESTING.md).
Third-party code: [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md).

Branch: `feature/relic-systems` (from `feature/relic-recovery`). It does not include
the separate `milestone-2` branch line.

---

## 1. Install the tools (once)

You need **Roblox Studio** and **Rojo 7.4.4**. The version is pinned in `rokit.toml`.

**Rojo through Rokit (recommended)**
1. Download the Windows build of Rokit from <https://github.com/rojo-rbx/rokit/releases>
   (`rokit-*-windows-x86_64.zip`) and extract it.
2. In a terminal in the extracted folder, run `./rokit self-install`. Close and reopen
   the terminal so `rokit` is on your PATH.
3. In this project folder, run:
   ```bash
   rokit install
   ```
   Rokit reads `rokit.toml` and installs Rojo 7.4.4. Check it with `rojo --version`.

**Rojo Studio plugin**
```bash
rojo plugin install
```
Restart Studio afterwards. A Creator Store "Rojo" plugin also works if it is version 7.4.x.

`rokit install` also installs **Lune 0.11.0**, which runs the logic tests outside Studio:
```bash
lune run tools/run-tests
```

ProfileStore needs no install. It is vendored at `src/server/Vendor/ProfileStore.luau`,
pinned and licensed as described in [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md).

## 2. Start a session

1. In this project folder, run:
   ```bash
   rojo serve
   ```
   Leave it running (`Rojo server listening on port 34872`).
2. Open Roblox Studio and open your test place (or **New**, then **Baseplate**).
3. Go to **Plugins**, then **Rojo**, then **Connect**. Rojo creates:
   - `ReplicatedStorage.HollowboundShared` (Config, Net, LoadoutRules)
   - `ServerScriptService.HollowboundServer` (Script with server modules, `Tests`, `Vendor`)
   - `StarterPlayer.StarterPlayerScripts.HollowboundClient` (LocalScript with Hud,
     Actions, AbilityFx, DevKeys)
4. Save the place. Rojo does not store Workspace content.
5. Go to **Test**, then **Clients and Servers**, choose **2 Players**, and click **Start**.
   Follow [`docs/TESTING.md`](docs/TESTING.md).

### Storage mode in a playtest

The top-left badge and the server Output show which storage is in use:

| Badge | Meaning |
|---|---|
| `Saved` / `Saving...` (dark badge) | Real DataStores through ProfileStore. The place is published and **Enable Studio Access to API Services** is on. |
| `MOCK STORAGE (nothing persists): ...` (purple badge) | Studio without API access. The game uses `ProfileStore.Mock` on purpose; nothing survives the playtest. Turn this off with `Config.Persistence.StudioMockWhenNoAccess = false`, which makes loading fail instead. |
| Player kicked with "could not load your saved relics" | Loading failed. Nothing was changed, and no blank profile was used. |

For real persistence checks, use a **separate published test experience** (see
`docs/TESTING.md`, part C). DataStores belong to one experience, so test data never
mixes with the real game.

### What Rojo touches
`default.project.json` maps only the three code folders. Every service node sets
`$ignoreUnknownInstances`, so Rojo leaves other scripts, models, and Workspace content
alone. It does not map Workspace, terrain, or lighting. Edit code in `src/`, not in Studio:
Rojo overwrites Studio edits to synced scripts.

## 3. How the relic system works

### States of a relic specimen
Each specimen has a unique ID, a type, a rarity, and permanent traits. These are
generated once on the server and never rerolled. The following states are separate and
independent:

| State | Changed by | Never changed by |
|---|---|---|
| Owner | pickup or recovery; dropped on final death if unregistered | registration, appraisal, activation, service |
| **Registered** (secured) | town registry terminal | appraisal, activation, service, death |
| **Appraised** (traits visible to owner) | town appraisal | registration, activation, service, death |
| **Activated** (usable, for types that need it) | town activation | registration, appraisal, service, death |
| **Needs service** | set when a registered relic survives final death | registration, activation, appraisal |
| **Charges** | ability use spends one; service refills to max | registration, activation, appraisal |

### Controls

| Action | Keyboard / mouse | Controller | Touch |
|---|---|---|---|
| Use slot 1, 2, 3 | `1`, `2`, `3` or click the slot | D-pad left, up, right | tap the slot |
| Open / close relic menu | `B` or the **Relics** button | D-pad down; **B button** closes | tap **Relics** |
| Menu buttons (Equip, Unequip, Appraise, Activate) | click | move selection, press **A** | tap |
| Pick up, register, service | hold `E` at the prompt | hold the prompt button (**X**) | tap the prompt |

All actions go through one action layer (`src/client/Actions.luau`). Nothing is
keyboard-only, and nothing needs drag and drop. The HUD scales with screen height.

### What happens in a playtest

| Feature | Where | Notes |
|---|---|---|
| Self-test | Server Output | Store, ability, and persistence rules on **mock storage only**. |
| Placeholder map | `Workspace.HollowboundDevMap` at X=200 | Studio only, built at runtime (unchanged since milestone 1). |
| Relic fixtures | `Workspace.HollowboundDevRelicFixtures` | Studio only: pedestals C, D, and E, 15 studs in front of pedestal A. A separate model; the map is not edited. |
| Specimens | Pedestals A-E | A: Windhook (Common). B: Windhook (Rare). C: Echo Lens (Uncommon). D: Echo Lens (Exceptional). E: Windhook (Exceptional). Regenerated on each server start. |
| Pickup | Prompt (E) | Server checks: profile loaded, living character, distance, availability, ownership. The claim never yields, so one request wins. |
| Registration | Teal terminal in town | Registers carried relics in place and requests an immediate save. "Registered" is shown at once. The badge shows **Saving...** until storage confirms, then **Saved**. |
| Appraise / Activate | Relic menu, at a terminal or service station in town | Free (provisional). Appraisal reveals the existing traits to the owner. Activation is needed only by types that require it (Windhook). |
| Service | Wooden bench beside the terminal | Clears Needs service, restores condition, refills charges. Free (provisional). |
| Loadout | Relic menu, then **Equip** and choose a slot | 3 slots, at most 1 Exceptional relic; Common, Uncommon, and Rare are Support. Swapping is allowed any time, including in danger. |
| Windhook (Gust leap) | Use its slot | Short forward-and-upward push in the facing direction. Needs activation. |
| Echo Lens (Echo pulse) | Use its slot | Marks nearby relics lying in the world, for you only. Works right after pickup. |
| Final death | Any character death | Unregistered relics drop as the same specimens; registered relics stay, marked Needs service with charges emptied. Handled once per character. |

### Provisional tuning (all in `src/shared/Config.luau`)

| Value | Setting |
|---|---|
| Loadout | 3 slots; Exceptional limit 1 (`Config.Loadout`) |
| Windhook | 3 charges; cooldown 6 s to 3 s (efficiency trait); forward speed 40 to 70 studs/s (reach trait, cap 80); upward speed 24 to 38 studs/s (carrying-strength trait, cap 45); push lasts 0.35 s |
| Echo Lens | 4 charges; cooldown 12 s to 6 s (efficiency trait); radius 40 to 120 studs (scan-range trait); marks last 4 to 10 s (clarity trait); at most 12 marks |
| Activation | Windhook requires town activation; Echo Lens works immediately (`requiresActivation`) |
| Death | Protected relics return with condition 0 and charges 0 (`Config.Death`) |
| Service, appraisal, activation | Free (`Config.Service.Price = 0`; costs are Open) |
| Requests | At most 8 relic actions per second per player |

Traits shape abilities through `{ trait, worst, best }` entries. A specimen's trait is
normalized within its type's range. A missing trait uses the weakest value; it is never
rerolled. Cooldowns are per player and per ability, and the deadlines are saved. Swapping
slots, switching copies, dying, or rejoining does not reset them.

### Saving (milestone 3)

- **What is saved:** registered relics only (ID, owner, type, rarity, quality, traits,
  appraisal, activation, Needs service, condition, charges, timestamps), the loadout
  slots that hold registered relics, and ability cooldown deadlines. One profile per
  UserId, session-locked, schema version 1. Key: `Player_<UserId>` in
  `Config.Persistence.StoreName`.
- **Never saved:** unregistered relics. Leaving cannot bank fresh loot, and a relic that
  another player recovered is never recreated from an old profile.
- **When:** registration, service, appraisal, and activation of a registered relic, and
  death with protected relics, request an immediate save. Equip changes, ability use, and
  cooldowns are saved on the next autosave (about 5 minutes) and when the player leaves.
- **Safety:** gameplay changes are refused until the profile loads, and again if the
  session moves to another server (that player is kicked with an explanation). A failed
  load kicks the player without writing anything. Newer-schema data is refused, not
  overwritten. Unreadable records are kept untouched. A save never deletes a
  previously saved relic. Save confirmations only move forward, so late callbacks cannot
  mark newer changes as saved.

#### Temporary departure rule (prototype only)
This is **not** the final reconnect design. Reconnect bodies and camp pause/resume are
future work.
- **Leaving outside town:** the final-death rules apply once, before cleanup.
  Unregistered relics drop as world pickups; registered relics are saved needing
  service.
- **Leaving in town:** registered relics are saved as they are. Unregistered relics
  cannot be saved, so they are released into the world where you stood.
- **Whole-server shutdown** (Studio Stop, or a server closing): everyone is saved as is,
  with no death penalties. Unregistered relics end with the server.
- **Session lost to another server:** no penalties; that server owns the saved data.

#### Crash-recovery limits
- If a server crashes, changes since the last confirmed save are lost. The **Saved**
  badge means storage confirmed it. **Saving...** and "Saves on autosave or leave" mean
  it is not confirmed yet.
- A crashed server's session lock is released by ProfileStore after about 10 minutes
  (`ASSUME_DEAD`), or sooner when another server takes it over (about 40 s). Until then,
  a rejoin waits.
- Unregistered relics are never saved, so a crash loses them.
- Profile locking protects one player's profile. It is **not** a trading transaction
  system; cross-player trades would need their own atomic design.

**Using your own geometry:** tag parts with `HB_RegistrationTerminal`,
`HB_ServiceStation`, `HB_TownZone`, `HB_CampZone`, and `HB_RelicSpawn` (spawns named
`RelicSpawnA`-`E`).

**Dev keys (Studio only):** **K** sends a pickup request ignoring the prompt range.
**J** sends a timed pickup (race test). **L** kills your character and reports the death
two extra times. Turn them off with `Config.Dev.EnableDevRemotes = false`.

## 4. Project layout

```
default.project.json   Rojo mapping (shared / server / client only)
rokit.toml             toolchain pin (Rojo 7.4.4)
licenses/              third-party licenses (ProfileStore, Apache-2.0)
docs/                  design PDF, TESTING.md, DEPENDENCIES.md
src/shared/            ReplicatedStorage.HollowboundShared
  Config.luau          all provisional values, labelled with design status
  LoadoutRules.luau    slot classes from Config (rarity -> Support / Exceptional)
  Net.luau             remote names
src/server/            ServerScriptService.HollowboundServer
  init.server.luau     startup, player load, departure, shutdown
  RelicStore.luau      live state: specimens, inventories, loadouts (pure, never yields)
  SpecimenFactory.luau one-time ID and permanent trait generation
  SpecimenCodec.luau   saved record <-> specimen, deterministic migration
  Sessions.luau        saved sessions: gate, commit, confirm, depart, lost session
  ProfileBackend.luau  ProfileStore adapter (real storage; explicit Studio mock)
  MockBackend.luau     TEST-ONLY in-memory backend with failure injection
  Guard.luau           "may this player change anything now?"
  RelicDefs.luau       lookups over relic types and abilities
  AbilityRules.luau    use checks, charges, cooldowns, trait tuning
  Abilities.luau       Windhook push and Echo pulse effects
  RelicActions.luau    validated client requests: equip, unequip, use, appraise, activate
  RelicView.luau       what a client may see; traits only after appraisal
  WorldRelics.luau     world orbs, pickup validation, nearby-relic query
  Registration.luau    town registry terminal
  ServiceStation.luau  town repair and recharge
  Defeat.luau          final death and the temporary departure rule
  Zones.luau           Town / Camp / Depths, and the town-desk check
  ServerNet.luau       remotes, state push, notifications
  Characters.luau      living-character check
  DevMap.luau          Studio-only geometry, service station, relic fixtures
  SelfTest.luau        Studio-only test runner (mock storage)
  Tests/               StoreTests, AbilityTests, PersistenceTests, TestKit
  Vendor/              ProfileStore (pinned, unmodified)
src/client/            StarterPlayerScripts.HollowboundClient
  init.client.luau     wiring and requests
  Actions.luau         one action layer: keyboard, controller, touch
  Hud.luau             save badge, pack, loadout bar, relic menu, messages
  AbilityFx.luau       local-only ability feedback (Echo marks, Gust cue)
  DevKeys.luau         Studio-only K / J / L test keys
```

## 5. Design traceability

| Implemented behavior | Design status |
|---|---|
| Pickup establishes ownership; no crew pooling | Decided |
| Town secures relics; camp is refuge only | Decided |
| Unique specimens with permanent traits; repair and recharge preserve traits | Decided |
| Appraisal reveals, activation enables, registration protects: separate states | Decided / Delegated |
| Free appraisal in town; traits visible to the owner once appraised | Delegated |
| Activation varies by relic (Windhook needs it; Echo Lens does not) | Decided (rule) / milestone 3 brief (which types) |
| One exceptional relic plus support relics | Decided; 3 slots is a provisional test layout (Open) |
| Classify by the specimen's actual rarity | Proposed in the design record, used here |
| Windhook and Echo Lens abilities, charges, cooldowns, and numbers | Proposed examples; all tuning is Open |
| Final death drops unregistered relics; registered relics return needing service | Decided |
| Downed/revive before final death | Decided; not yet implemented |
| Free service, appraisal, and activation | Open; provisional testing choice |
| Temporary departure rule | Prototype rule from the milestone 3 brief; final reconnect rules are Open |
| Rarity tiers and thresholds | Open; placeholders |

## 6. Not in this milestone

- Ranks, currency, costs, trading, creatures and combat, downed/revive, procedural
  world generation, and the full reconnect system (bodies, camp pause/resume).
- Ordinary gear inventory (it will drop on final death like unregistered relics).
- Visible carrying of exceptional finds.
