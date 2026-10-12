# Hollowbound: milestone 1

A small shared test place with relic pickup, an in-memory inventory, and town
registration. Built with Luau, Roblox Studio, and Rojo.

Design source: [`docs/Hollowbound_Game_Design_v0_2.pdf`](docs/Hollowbound_Game_Design_v0_2.pdf).
Core rules and the current milestone: [`CLAUDE.md`](CLAUDE.md).
Manual tests: [`docs/TESTING.md`](docs/TESTING.md).

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

You can instead download `rojo.exe` 7.4.4 directly from
<https://github.com/rojo-rbx/rojo/releases> and put it on your PATH.

**Rojo Studio plugin**
```bash
rojo plugin install
```
This installs the matching plugin into Studio. Restart Studio afterwards. You can also
install the "Rojo" plugin from the Creator Store, as long as its version is 7.4.x.

## 2. Start a session

1. In this project folder, run:
   ```bash
   rojo serve
   ```
   It prints `Rojo server listening on port 34872`. Leave it running.
2. Open Roblox Studio. Choose **New**, then **Baseplate** (or open your own place file).
3. Go to the **Plugins** tab, click **Rojo**, then click **Connect** (localhost:34872).
   Rojo creates:
   - `ReplicatedStorage.HollowboundShared` (Folder: Config, Net)
   - `ServerScriptService.HollowboundServer` (Script, with server modules as children)
   - `StarterPlayer.StarterPlayerScripts.HollowboundClient` (LocalScript, with Hud and DevKeys)
4. **Save the place** (File, then Save to File As, for example `Hollowbound.rbxl`) so your
   manual Workspace edits persist. Rojo does not store Workspace content.
5. Go to the **Test** tab. In **Clients and Servers**, choose **2 Players**, then click
   **Start**. Follow [`docs/TESTING.md`](docs/TESTING.md).

To test alone, press **Play** (F5).

### What Rojo touches
The project file maps only the three folders above. Every service node sets
`$ignoreUnknownInstances`, so Rojo leaves other scripts, models, and hand-built Workspace
content alone. Rojo does not manage Workspace. Keep code in `src/` and edit it there,
not in Studio: Rojo overwrites Studio edits to synced scripts.

## 3. What happens in a playtest

| Step | Where | Notes |
|---|---|---|
| Self-test | Server Output | Checks claim and registration rules on a scratch store (Studio only). |
| Placeholder map | `Workspace.HollowboundDevMap` at X=200 | Built at runtime in Studio only: town (spawn and terminal), camp, expedition area, and walkways. It is skipped if the map already exists or a part tagged `HB_RegistrationTerminal` already exists. |
| Specimens | Expedition pedestals | Two Windhook specimens. ID (GUID) and traits are generated once per server start, with non-overlapping quality bands so their traits differ. |
| Pickup | ProximityPrompt (E) | The server checks for a living character, distance (12 studs), that the relic is still in the world, and that nobody owns it. The claim runs without yielding, so one request wins. |
| Inventory HUD | Top-right panel | Name, colored rarity, UNSECURED or REGISTERED, Unappraised, Needs activation, and a short ID. Traits are not sent. |
| Camp | Grass square | Zone label and message only. Relic state never changes. |
| Registration | Teal terminal in town | Marks carried relics registered in place, keeping the same record, ID, and traits. Repeats are reported without duplicating anything. |

**Keeping the map:** the dev map exists only while a test runs. To keep and edit it, during
a playtest select `Workspace.HollowboundDevMap`, copy it, stop the test, and paste it into
Workspace. The bootstrap sees the existing map and does not build another. Tags survive
copy and paste.

**Using your own geometry:** tag parts with the names in `Config.Tags`:
`HB_RegistrationTerminal`, `HB_TownZone`, `HB_CampZone`, and `HB_RelicSpawn`. Name relic
spawns `RelicSpawnA` and `RelicSpawnB`. Use Studio's **Tag Editor** in the Model tab, or
the Properties panel's Tags section.

**Dev keys (Studio only):** **K** sends a pickup request for the nearest orb that skips the
prompt range, for out-of-range tests. **J** sends a request at the next 5-second
server-time boundary, for simultaneous-pickup tests from two windows. Both go through the
same server validation. Turn them off with `Config.Dev.EnableDevRemotes = false`.

## 4. Project layout

```
default.project.json   Rojo mapping (shared / server / client only)
rokit.toml             toolchain pin (Rojo 7.4.4)
src/shared/            ReplicatedStorage.HollowboundShared
  Config.luau          all provisional values, labelled with design status
  Net.luau             remote names
src/server/            ServerScriptService.HollowboundServer
  init.server.luau     startup order
  RelicStore.luau      specimens, inventories, claim, register (pure Luau, no yields)
  SpecimenFactory.luau one-time ID + permanent (frozen) trait generation
  RelicView.luau       what a client may see; traits only after appraisal
  WorldRelics.luau     spawning orbs, pickup validation
  Registration.luau    town terminal
  Zones.luau           Town / Camp / Depths attribute; camp never touches relics
  ServerNet.luau       remotes, inventory push, notifications
  Characters.luau      living-character check
  DevMap.luau          Studio-only placeholder geometry
  SelfTest.luau        Studio-only rule checks
src/client/            StarterPlayerScripts.HollowboundClient
  init.client.luau     wiring
  Hud.luau             pack panel, zone label, messages
  DevKeys.luau         Studio-only K / J test keys
docs/                  design PDF, test checklist
```

## 5. Design traceability

| Implemented behavior | Design status |
|---|---|
| Pickup establishes ownership; no crew pooling | Decided |
| Town secures relics; camp is refuge only | Decided |
| Unique specimens with permanent traits; repair and recharge preserve traits | Decided (the `condition` and `charge` fields exist but are unused) |
| Appraisal, activation, and registration are separate states | Decided/Delegated |
| Type and rarity visible on pickup; traits revealed by appraisal | Delegated |
| Windhook as the test relic; its trait names (reach, carrying strength, efficiency) | Proposed example. Used provisionally. |
| Rarity tiers Common, Uncommon, Rare, Exceptional, and their thresholds | Open. Placeholders in `Config`. |
| All distances, hold times, and quality bands | Open. Placeholders in `Config`. |

## 6. Not in this milestone

- **Persistence:** all data lives in server memory and is lost when the server stops.
  DataStore saving is a later milestone. Rejoining the same running server keeps your
  relics, because records are keyed by UserId.
- **Death handling:** downed state, final death dropping ordinary gear and unregistered
  relics, and registered relics returning needing repair or recharge. Resetting your
  character currently keeps everything.
- Appraisal and activation flows, relic abilities, combat and creatures, crews, PvP and
  camp aggression timers, trading, ranks and XP, procedural terrain, and visible carrying
  of exceptional finds.
