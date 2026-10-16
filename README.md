# Hollowbound: milestone 4

A shared test place for the relic system: pickup and town registration, final death with
dropped and protected relics, town service, saved registered relics, appraisal and
activation, a 3-slot loadout, and two relic abilities (Windhook and Echo Lens).
Milestone 4 adds **the first complete dangerous PvE expedition**: an expedition
lifecycle, health with a **downed / revive / self-rescue** stage, **melee combat**, an
original **creature** with a **guardian** that locks a **relic cache**, **ordinary
supplies** (weapon, bandages, self-rescue kits), and **camp protection**.
Built with Luau, Roblox Studio, Rojo, and ProfileStore.

Design source: [`docs/Hollowbound_Game_Design_v0_2.pdf`](docs/Hollowbound_Game_Design_v0_2.pdf).
Core rules and the current milestone: [`CLAUDE.md`](CLAUDE.md).
Tests (mock, two-client Studio, and real persistence): [`docs/TESTING.md`](docs/TESTING.md).
Third-party code: [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md).

Repository: <https://github.com/chba03/Hollowbound> (solo project). `main` holds the
owner-verified integrated version; milestone 5 is in progress on `feature/vertical-world`
(milestones 3 and 4 are committed beneath it). The separate `milestone-2` branch is not part
of this project (see CLAUDE.md, "Ownership and repository workflow").

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
| Final death | Any engine death (bleedout, reset, void) or leaving outside town | Unregistered relics drop as the same specimens; registered relics stay, marked Needs service with charges emptied. Handled once per character. Combat and creature damage first **downs** you (milestone 4, section 4). |

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

## 4. The expedition (milestone 4)

The loop: **prepare in town, leave on an expedition, fight or evade creatures, claim a
guarded relic, use supplies and relic abilities, survive or recover from being downed,
and return to register the discovery.**

### Expedition lifecycle
- The server tracks a phase per player: **Town**, **Exploring**, or **AtCamp**. Leaving
  town starts one run. Camps neither start nor finish a run. Returning to town or final
  death finishes it, once. The next departure starts a new run. There is no time limit.
- Each run has a unique id, and each character has a separate condition: **Alive**,
  **Downed**, or **Dead**. Delayed callbacks carry run, character, and down ids, so an
  old run or character can never affect the current one.
- Ending a run never registers, appraises, activates, repairs, or recharges a relic.
  Registration still happens only at the terminal.

### Health, downed, revive, final death
- **One damage interface** (`Vitals.damagePlayer`) handles all combat and creature
  damage. It refuses damage in town and camps, and turns lethal damage into **Downed**
  instead of death.
- **Downed:** you crawl (3 studs/s, no jumping) and see a 30 s bleedout countdown. You
  cannot attack, heal, use relics, or pick up, register, or equip anything. Nothing drops
  and no relic is marked Needs service while you are only downed.
- **Revive:** another standing explorer holds **Revive** on you for 4 s. The server times
  it and re-checks distance (9 studs), line of sight, both characters, and the down
  itself every frame; letting go or moving away cancels. One helper per down, so several
  helpers cannot double-revive. You return with 35 health.
- **Self-rescue:** while downed, press **Supply** to use a carried self-rescue kit (5 s,
  returns you with 25 health). One success per run; the kit is consumed exactly once. A
  new character, swapping items, or a camp visit does not reset the allowance.
- **Final death:** bleedout, Reset Character, falling into the void, any other engine
  death, and leaving outside town all use the existing final-death path **once**.
  Unregistered relics and **all ordinary items** drop (separately recoverable), and
  registered relics need service. Milestone 2-3 behaviour and saving are unchanged.
- **Health regeneration is explicit:** Roblox's default regeneration is removed. You
  heal 10/s in town, 2/s at camps (after 6 s without damage), and **not at all while
  exploring**, so bandages and rescues matter.

### Melee combat (starter blade)
- Attack with **left click / F**, **R2**, or the on-screen **Attack** button. The client
  only asks; the server checks session, standing character, weapon, no timed action in
  progress, cooldown, and that you are **not inside town or a camp**.
- Visible swing: the blade tilts back (0.25 s windup) and sweeps with a trail. The server
  then picks hits from its own data: range 7 (+1.5 slack), a 110° arc in front, line of
  sight, at most one hit per creature per swing, 18 damage. There is no parry timing.
  Swings are 0.8 s apart; extra requests are ignored, then rate limited.
- Player-versus-player damage is **off** (`Config.Combat.PlayerVsPlayer = false`).

### Creatures and the guarded relic
- One original placeholder creature, the **Thornback** (name provisional), in two
  variants from config: **Thornback** (regular) and **Thornback Matriarch** (guardian).
  Both use the same AI: patrol or idle, detection (sight within a field of view, or
  hearing up close), pursuit, a **telegraphed** attack (red glow, "!", HUD warning),
  recovery, return to the den, and death.
- Stepping out of reach during the telegraph avoids the hit. The guardian telegraphs
  longer (1.2 s) and recovers much longer (2.4 s) after striking: that is its **opening**.
- Line of sight and a lose-sight timer let you break contact. Pathfinding is rate
  limited; unreachable or stuck chases are given up after 3 failures. Creatures never
  enter or chase into town or camps, and return to their den beyond their leash. A
  return heals them to full, so poking from safety cannot farm them.
- Creatures ignore downed explorers and look for standing ones, which leaves a chance to
  revive.
- **Guardian cache:** locked while its guardian lives. When the guardian falls, exactly
  one reward relic is generated by the existing specimen factory and placed on the cache
  as a normal world relic. The first successful pickup owns it, never automatically the
  last hitter, and Echo Lens can mark it. After it is claimed the encounter resets after
  180 s. Players leaving never resets it.

### Ordinary supplies (session-only)
- The **Supply Station** in town hands out a free basic loadout: starter blade (max 1),
  3 bandages (max 5), 1 self-rescue kit (max 2). Repeated requests never exceed those
  amounts.
- **Bandage:** press **H / Y / Heal**, 2.5 s, +35 health. Taking damage or using a relic
  interrupts it and nothing is consumed. Press Supply again to cancel.
- Final death drops all ordinary items as one crate with a unique id beside the relic
  drops. Competing pickups have one winner, and taking the same crate twice cannot
  duplicate items. Untouched crates expire after 10 minutes.
- **Prototype limitation:** ordinary items are **not saved**. Leaving the game loses
  them (in town they vanish; outside town they drop through final death), and a rejoin
  starts empty. Refill in town. Registered relic saving is unchanged.

### Camps and protection
Town and camps are protected from the new combat and creature damage: no damage is
taken, creatures do not enter or chase, players cannot attack from inside, and creatures
inside cannot be damaged. Camps still do **not** register discoveries, bank loot, refill
relic charges, or reset the self-rescue allowance.

*Later PvP milestone (documented only, not implemented):* the design's proposed camp
rules are kept for then. Recent aggressors wait before gaining camp protection while
defenders gain it at once, with an aggression indicator and countdown, and protection
lingers briefly after leaving a crew.

### Controls (additions)

| Action | Keyboard / mouse | Controller | Touch |
|---|---|---|---|
| Attack | left click (not on UI) or `F` | R2 | **Attack** button |
| Bandage (standing) / self-rescue kit (downed); press again to cancel | `H` | Y | **Heal** / **Rescue kit** button |
| Revive a downed explorer | hold `E` at **Revive** | hold the prompt button (**X**) | hold the prompt |

### Placing encounters and camps (markers)
Any authored map can host encounters. Tag parts with CollectionService tags (Studio:
Model tab, then **Tag Editor**, or the Properties panel's **Tags** section) and set
attributes (Properties, then **Attributes**, then **+**):

| Tag | Part | Attributes |
|---|---|---|
| `HB_CreatureSpawn` | a small flat part on the ground where the creature stands; its den is here | `Variant` = `"Regular"` (default) or `"Guardian"`; guardians need `EncounterId` (text); optional `RespawnSeconds` (number) |
| `HB_RelicCache` | the cache prop near the den | `EncounterId` matching the guardian's |
| `HB_CampZone` | an invisible, non-colliding box covering the camp (anchored, `CanCollide` off, `Transparency` 1) | none |
| `HB_TownZone` | the same, covering town | none |
| `HB_SupplyStation` | a part **inside** a town zone | none |

Rules of thumb: put dens at least `leashRadius` (55 for regulars, 40 for guardians) away
from camps and town; leave walkable, mostly flat ground (creatures do not jump); place
caches 6-10 studs behind their den; one `EncounterId` per guardian. Placement mistakes
show as warnings in the server Output.

### Studio test fixtures (optional)
With `Config.Dev.BuildEncounterFixtures` and `BuildSupplyStation` on, Studio playtests
add separate models: `HollowboundDevSupplyStation` (next to the terminal) and
`HollowboundDevEncounterArena`. The arena sits behind the expedition area, past a
bridge: two Thornbacks, a Matriarch den with its cache, two cover walls, and a small test
camp in the front-right corner. Neither is built when the model exists or hand-placed
`HB_CreatureSpawn` markers exist. Neither edits authored content.

### Provisional tuning (milestone 4, `src/shared/Config.luau`)

| Value | Setting |
|---|---|
| Health | 100; regeneration Town 10/s, Camp 2/s, Exploring 0 (after 6 s without damage) |
| Downed | bleedout 30 s; crawl 3 studs/s; revive 4 s within 9 studs, +35 health; self-rescue 5 s, +25 health, 1 per run |
| Starter blade | 18 damage, range 7, 110° arc, 0.25 s windup, 0.8 s cooldown |
| Bandage | +35 health, 2.5 s, carry 5, town refill 3 |
| Self-rescue kit | carry 2, town refill 1 |
| Thornback | 60 health, 15 damage, 0.8 s telegraph, 1.0 s recovery, speeds 8 / 15, sight 45 studs (120°), hearing 10, leash 55, respawn 90 s |
| Thornback Matriarch | 180 health, 25 damage, 1.2 s telegraph, 2.4 s recovery, speeds 6 / 12, sight 38 (140°), leash 40, reset 180 s after its reward is claimed |
| Rewards | Windhook or Echo Lens, equal weights, quality 0.55-0.97 |
| Budget | at most 12 creatures; AI tick 0.2 s; dormant beyond 180 studs; repath at most once a second |
| Loot | supply crates expire after 600 s; pickup range 12 |

All names and numbers above are placeholders (Open).

### Known limitations (milestone 4)
- Ordinary items are session-only (see above). There is no currency, vendor, stash,
  or crafting.
- Placeholder visuals only: no imported models or animations. Swings tilt a welded blade,
  and downed characters crawl but do not play a lying-down pose.
- Creature movement is client-agnostic server physics. Expect simple, sometimes
  awkward pathing around complex geometry; creatures do not jump or climb.
- Melee uses the character's facing from its replicated position, which a modified
  client could rotate. Range, arc, line of sight, cooldown, and rate limits still bound it.
- A downed explorer who crawls into town or a camp is safe from creatures, but still
  bleeds out unless revived.

## 5. Project layout

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
  DevMap.luau          Studio-only geometry, service and supply stations, relic fixtures, test arena
  SelfTest.luau        Studio-only test runner (mock storage)
  Tests/               Store, Ability, Persistence, Survival, Creature suites; TestKit
  -- milestone 4 (pure rule cores first, then the Roblox-facing modules) --
  VitalsCore.luau      health, Alive/Downed/Dead, down tokens (pure)
  ExpeditionCore.luau  Town/Exploring/AtCamp, run ids, self-rescue allowance (pure)
  BusyCore.luau        server-timed, re-validated actions (pure)
  RescueCore.luau      one helper per down (pure)
  GearStore.luau       ordinary items, capacity, refills, unique drops (pure)
  MeleeRules.luau      swing cooldown and hit selection (pure)
  CreatureBrain.luau   creature state machine for every variant (pure)
  EncounterCore.luau   guardian cycles, locked cache, one reward per cycle (pure)
  Vitals.luau          central damage interface, downed, bleedout, regeneration
  Expedition.luau      expedition lifecycle per player
  Busy.luau            timed actions (bandage, revive, self-rescue)
  Rescue.luau          revive prompts and self-rescue
  Gear.luau            supply station, bandages, weapon visual, supply crates
  Combat.luau          melee requests and server hit resolution
  Creatures.luau       creature bodies, perception, pathing, strikes, cleanup
  Encounters.luau      marker-driven spawns, guardian caches, rewards
  FieldActions.luau    Attack / Supply / Cancel requests (rate limited)
  Vendor/              ProfileStore (pinned, unmodified)
src/client/            StarterPlayerScripts.HollowboundClient
  init.client.luau     wiring and requests
  Actions.luau         one action layer: keyboard, controller, touch
  Hud.luau             save badge, pack, loadout bar, relic menu, messages
  AbilityFx.luau       local-only ability feedback (Echo marks, Gust cue)
  FieldHud.luau        health, supplies, downed and rescue display, warnings, Attack/Heal buttons
  DevKeys.luau         Studio-only K / J / L test keys
```

## 6. Design traceability

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
| Downed/revive before final death; limited self-rescue item | Decided; window, health, and limits are Open (30 s, 4 s revive, 1 per run here) |
| Camps are refuges; town secures | Decided; damage protection details Open |
| Most creatures killable; guardian dens hold valuable relics | Decided / design examples; the Thornback is an original placeholder |
| Melee, no precise parry timing | Decided goal; tuning Open |
| PvP secondary; aggressor/defender camp rules | Decided / Proposed; PvP damage is off in this milestone |
| Ordinary gear lootable on final death | Decided; session-only storage is a prototype limitation |
| Explicit regeneration (none while exploring) | Implementation choice for this milestone |
| Free service, appraisal, and activation | Open; provisional testing choice |
| Temporary departure rule | Prototype rule from the milestone 3 brief; final reconnect rules are Open |
| Rarity tiers and thresholds | Open; placeholders |

## 7. Not in this milestone

- Ranks and XP, food and ascent strain, ranged combat, crews, PvP, trading, currency,
  vendors, stashes, crafting, procedural depths, and the full reconnect system (bodies,
  camp pause/resume).
- Saving ordinary items.
- Visible carrying of exceptional finds.
