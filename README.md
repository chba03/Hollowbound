# Hollowbound: milestone 2

A shared test place: a rim town of 8 player plots around the Hollow, a 10-layer pit. Lower
a rope from your plot, recover relics from the layers, register them, and display them
for passive cash. Spend it on longer ropes, faster climbing, and more display slots.
Built with Luau, Roblox Studio, Rojo, and ProfileStore.

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

ProfileStore is vendored in `src/server/Vendor/`, so there is nothing else to install.

## 2. Start a session

1. In this project folder, run:
   ```bash
   rojo serve
   ```
   It prints `Rojo server listening on port 34872`. Leave it running.
2. Open Roblox Studio. Choose **New**, then **Baseplate** (or open your own place file).
3. Go to the **Plugins** tab, click **Rojo**, then click **Connect** (localhost:34872).
   Rojo creates:
   - `ReplicatedStorage.HollowboundShared` (Folder: Config, Net, Progression)
   - `ServerScriptService.HollowboundServer` (Script, with server modules as children)
   - `StarterPlayer.StarterPlayerScripts.HollowboundClient` (LocalScript, with Hud,
     RopeController, LayerEffects, and DevKeys)
4. **Save the place** (File, then Save to File As, for example `Hollowbound.rbxl`) so your
   manual Workspace edits persist. Rojo does not store Workspace content.
5. Set **Game Settings > Places > Max Players** to **8**, one per plot. Scripts cannot
   change this.
6. Go to the **Test** tab. In **Clients and Servers**, choose **2 Players**, then click
   **Start**. Follow [`docs/TESTING.md`](docs/TESTING.md).

To test alone, press **Play** (F5).

**Saving in Studio:** without API access, ProfileStore uses a mock store and data resets
every test. To test real saving, publish the place and turn on **Game Settings > Security >
Enable Studio Access to API Services**.

### What Rojo touches
The project file maps only the three folders above. Every service node sets
`$ignoreUnknownInstances`, so Rojo leaves other scripts, models, and hand-built Workspace
content alone. Rojo does not manage Workspace. Keep code in `src/` and edit it there,
not in Studio: Rojo overwrites Studio edits to synced scripts.

## 3. What happens in a playtest

| Step | Where | Notes |
|---|---|---|
| Self-test | Server Output | Checks claim, registration, display, save, plot, and progression rules on scratch objects (Studio only). |
| Dev map | `Workspace.HollowboundDevMap` + Terrain, rim at Y=2000 (floor of layer 10 at Y=400) | Built at runtime in Studio only: the rim town on a terrain island in a sea, with 8 plots, houses, and lamps; below it the Hollow, a terrain chasm whose width changes with depth, with 2 ledges per layer, camps (layers 2 to 10), relic spawn points, and each layer's props (see below). Parts are skipped if the map already exists; terrain is skipped if the pit wall already has terrain. |
| Plots | Rim | Each player gets the lowest free plot and spawns on it. A plot has a rope winch and arm, a registry terminal, 10 pedestals, and 3 upgrade boards. A full server kicks the extra player. |
| Rope | Winch at the plot edge | First use deploys the rope to your rope length; the next use puts you on it. W / S climb, Space lets go (with a hop toward the wall), F grabs your rope from a ledge. Reaching the top returns you to your plot (the server dismounts you there, so network lag cannot drop you). |
| Falling | Anywhere | Nothing stops a fall. The server measures each drop: up to about 10 m is safe, 10 to 18 m hurts, and 18.5 m or more (one ledge to the next) is fatal and turns you into a ragdoll. Rope length is what lets you reach deeper layers safely. A depth meter in metres sits at the top of the screen. |
| Layers | 160 studs each | The server sets `HB_Layer`; the client changes fog and tint and shows a banner. Deeper layers have better relics and higher income multipliers. |
| Relics | `Config.RelicTypes` | 70 types across seven tiers (Common, Uncommon, Mythic, Secret, Divine, Eternal, Godly). Layers 1-2 hold Common to Secret, layer 3 adds Divine, layer 4 adds Eternal, layers 5-10 hold every tier (two Divine, one Eternal, two Godly). Divine, Eternal, and Godly only appear as rare spawns (`Config.RareSpawns`: Divine 60% a day, Eternal 22%, Godly 18%), announced to everyone. A type's tier is fixed and shown on pickup. Every specimen also rolls a visible size (Tiny 0.6x to Colossal 5x, `Config.Sizes`); income scales with size^1.5, so late-game finds earn absurd amounts. Each has its own model (`RelicModels`, 16 shapes from the relic reference sheet), income, and hidden traits. Mythic and up sparkle; Divine and Godly send up a beam of light. |
| Spawns | Ledges | Each layer keeps up to `maxNodes` relics in the world and refills one per tick. Each spawn rolls a tier by weight (60 / 26 / 10 / 3 / 0.8 / 0.2 %, among the tiers that layer has), then one of that layer's relics of that tier. A 1% lucky roll uses a deeper layer's table. |
| Pickup | ProximityPrompt (E) | Unchanged from milestone 1: living character, 12-stud server range check, non-yielding claim. |
| Registration | Plot terminal | Secures carried relics and writes them to the save. |
| Displays | Pedestals | "Display best relic" puts your highest-income registered relic on the pedestal. "Take back" returns it. Income ticks every second. |
| Upgrades | Plot boards | Rope length (orange), climb speed (blue), display slots (purple). The server checks cash and level. |
| Saving | ProfileStore | Cash, levels, registered relics, and display slots. |

**The layers** (look follows the reference chart; names are original placeholders):

| Layer | Look |
|---|---|
| 1 Mistfall Gardens | Green cliffs, trees on the ledges, hanging gardens and vines, two falls from the rim |
| 2 The Hanging Wood | Upside-down trees and moss under the ledges, trees growing sideways from the walls |
| 3 Veilfall Cliffs | Sheer cliff columns and six great waterfalls in white mist |
| 4 Glasswood Hollows | The widest point: tall teal cup-shaped trees and glowing ice crystals |
| 5 Drowned Terraces | Water pools on the ledges, spilling from ledge to ledge |
| 6 Rootbound Ruins | Giant roots, broken buildings, old machinery, lanterns |
| 7 The Marrow | Fleshy fibres, glowing pods, a dark hole in the floor with rising motes |

Each layer also has its own fog, tint, and floating motes on the client (`LayerEffects`).

**Performance:** walls, ledges, island, and sea are Smooth Terrain, which Roblox renders and
streams cheaply. About 700 prop parts, all anchored, non-colliding, non-queryable, and
shadowless; about 40 point lights; about 20 low-rate particle emitters; one camera-following
emitter per client for motes.

**Keeping the map:** the runtime build takes a few seconds and is discarded when the test
stops. To bake it into the place, run this once in the command bar in edit mode, then save:

```lua
require(game.ServerScriptService.HollowboundServer.DevMap).ensure()
```

Playtests then reuse the saved parts and terrain, and you can edit them by hand.

**Using your own geometry:** tag parts with the names in `Config.Tags`:
- `HB_HollowRim`: one part at the pit centre, at rim height. The pit's radius at each depth
  comes from `Config.Layers[n].radius` (`Progression.pitRadiusAt`), which also decides
  where the pit ends and town begins.
- `HB_Plot`: a Model per plot with a number attribute `PlotIndex` (1 to 8) and the child
  parts listed at the top of `src/server/Plots.luau`.
- `HB_RelicSpawn`: spawn points on ledges, each with a number attribute `Layer` (1 to 7).
- `HB_RegistrationTerminal`, `HB_TownZone`, `HB_CampZone`: as in milestone 1.

Pit sizes (radius, ledge width, rope radius, layer height) live in `Config.Hollow`.

**Dev keys (Studio only):** **K** sends a pickup request for the nearest orb that skips the
prompt range. **J** sends one at the next 5-second server-time boundary, for
simultaneous-pickup tests from two windows. **M** grants `Config.Dev.CashGrant` cash.
Turn them off with `Config.Dev.EnableDevRemotes = false`.

## 3b. Publish for playtests with friends

1. Build a complete place file (code, Baseplate, SpawnLocation, streaming on):
   `rojo build publish.project.json -o build/Hollowbound.rbxl`
2. Open `build/Hollowbound.rbxl` in Studio. Live servers build the map themselves on
   start (`Config.Dev.BuildMapOnLiveServers`), so there is nothing to bake.
3. File > Publish to Roblox, then in Game Settings: enable Studio Access to API
   Services, Max Players 8, Avatar Type R15. Publish again.
4. On create.roblox.com: fill out the maturity questionnaire, set Privacy to Public.
5. Admin commands for testing: type `/hb help` in chat (owner only, plus
   `Config.Admin.UserIds`).

To update: rebuild the file, open it, publish, then shut down old servers from the
experience page. Purchases need real product and pass ids in `Config.Shop`.

## 4. Project layout

```
default.project.json   Rojo mapping (shared / server / client only)
rokit.toml             toolchain pin (Rojo 7.4.4)
src/shared/            ReplicatedStorage.HollowboundShared
  Config.luau          all provisional values, labelled with design status
  Net.luau             remote names
  Progression.luau     levels, layer-by-depth, income, cash formatting (pure)
  RopeAnimations.luau  the rope animations (hold, hand over hand) built in code
  Perks.luau           what a player bought, as multipliers (passes, boosts, server luck)
  PickaxeModels.luau   the ten pickaxes, built from parts (tools and previews)
  SwingAnimation.luau  the pickaxe swing, built in code
src/server/            ServerScriptService.HollowboundServer
  init.server.luau     startup order
  PlayerData.luau      ProfileStore schema (PlayerData.Template), load/save, cash
  Plots.luau           plot allocation, spawning players on their plot
  BaseManager.luau     pedestals, display pipeline, income tick, upgrades
  RopeService.luau     rope deploy, climb validation
  FallDamage.luau      fall damage and the ragdoll on a fatal fall
  Store.luau           purchases: prompts, receipts, grants, passes, boosts, weekly stock
  Hauling.luau         the Hauling Rig: lock in, AFK pulls train Speed
  Arsenal.luau         pickaxes: Forge buy / equip, tools, server-checked swings, dummies
  Enemies.luau         creatures: spawn, roam, chase, attack, rewards, respawn
  EnemyModels.luau     the ten creatures, built from parts
  Hollow.luau          locates the pit; depth measurement
  RelicSpawner.luau    layer-based spawn tables
  RelicStore.luau      specimens, inventories, claim, register, place (pure Luau)
  SpecimenFactory.luau one-time ID + permanent trait generation; save serialization
  RelicView.luau       what a client may see; traits only after appraisal
  WorldRelics.luau     relics in the world, pickup validation
  RelicModels.luau     relic 3D models (shape per type, effects per tier)
  Registration.luau    registry terminals
  Zones.luau           Town / Camp / Depths, layer and depth attributes, camp rings
  NightCycle.luau      nightfall every 5 minutes: relic reset, send players home, dawn
  Stamina.luau         sprint and stamina (server owns walk speed)
  ServerNet.luau       remotes, inventory push, notifications
  Characters.luau      living-character check
  Ground.luau          finds the real ground under a point (relics, camps)
  DevMap.luau          Studio-only map: rim marker, plots, spawn points, camps
  DevTerrain.luau      Studio-only terrain: island, sea, pit walls, ledges, floor
  DevBackdrop.luau     Studio-only sea and distant islands beyond the mountains (persistent parts)
  DevBase.luau         Studio-only base look: deck, crane, camp, scaffold tower; the town
  DevDecor.luau        Studio-only props: pit lip and each layer's look
  SelfTest.luau        Studio-only rule checks
  Vendor/              ProfileStore (MadStudioRoblox, Apache-2.0, commit 45c9847)
src/client/            StarterPlayerScripts.HollowboundClient
  init.client.luau     wiring
  Hud.luau             relics panel, stats, zone label, hints, banners, messages
  RopeController.luau  local rope movement and keys
  LayerEffects.luau    per-layer fog and tint
  RelicSpin.luau       spins and bobs nearby relic models
  RopePose.luau        plays the abseil animations on everyone on a rope
  NightEffects.luau    night sky and the nightfall countdown
  DepthVeil.luau       cloud layer over the layers your rope cannot nearly reach
  UpgradeBoards.luau   clickable upgrade panels on your base's boards
  ShopMenu.luau        the store menu (Emporium), live cards; catalogue is Config.Shop
  ShopIcons.luau       small 3D items for menu cards and tabs
  UiTheme.luau         steampunk / medieval UI kit: brass, walnut, leather, parchment, gears
  SprintController.luau Shift to sprint, stamina bar
  HaulController.luau  Hauling Rig stop input, crate animation, floating Speed gains
  ForgeMenu.luau       the Forge (pickaxe menu)
  CombatFx.luau        damage numbers
  SwingFx.luau         pickaxe swing animation for everyone, hurt flash
  DevKeys.luau         Studio-only K / J / M test keys
docs/                  design PDF, test checklist
```

## 5. Saved data schema

`PlayerData.Template` in `src/server/PlayerData.luau`, store `HollowboundPlayer_v1`, key
`Player_<UserId>`:

| Field | Type | Notes |
|---|---|---|
| `SchemaVersion` | number | For future migrations. |
| `Cash` | number | |
| `RopeLengthLevel`, `RopeSpeedLevel`, `BaseSlotsLevel` | number | Levels index into `Config` tables, so rebalancing needs no migration. |
| `Relics` | `{ [specimenId]: record }` | Registered relics only: type, quality, rarity, frozen traits, layer found, appraisal/activation/registration, condition, charge, timestamps. |
| `Placed` | `{ [slot as string]: specimenId }` | String keys, because ProfileStore cannot save gapped arrays. |
| `Stats` | table | `DeepestDepth`, `RelicsRegistered`, `CashEarned`. |

## 6. Design traceability

| Implemented behavior | Design status |
|---|---|
| Pickup establishes ownership; no crew pooling | Decided |
| Town secures relics; camp is refuge only | Decided. Plots on the rim count as town. |
| Unique specimens with permanent traits; repair and recharge preserve traits | Decided (the `condition` and `charge` fields exist but are unused) |
| Appraisal, activation, and registration are separate states | Decided/Delegated |
| Type and rarity visible on pickup; traits revealed by appraisal | Delegated. Income uses no traits. |
| Very rare relics occasionally appear outside their depth | Decided. The 1% chance is Open. |
| Atmosphere by depth (mist and gardens, luminous caves, dark water and machinery) | Proposed in the record; used for the placeholder layers. |
| Relic types (Windhook, Echo Lens, Stillbell, Anchor Charm, Pathfinder's Eye, Wayfarer Key) | Proposed examples. Kept, with their IDs, among the 70 catalogue types; no abilities. |
| 70-relic catalogue and the seven rarity tiers (Eternal added later; layers 8-10 added later) | Project owner's relic brief. A type's tier is fixed; specimen quality still varies its hidden traits. Names, numbers, and looks are Open. |
| Plots, rope progression, displays with passive income, upgrades | Milestone 2 brief. The record lists displays as an Open "home for the collection"; rope-gated depth and passive income are new. |
| Layer names, rarity tiers, all numbers | Open. Placeholders in `Config`. |

## 7. Not in this milestone

- **Death handling:** downed state, final death dropping ordinary gear and unregistered
  relics, and registered relics returning needing repair or recharge. Resetting your
  character currently keeps everything.
- **Leaving mid-expedition** forfeits unregistered relics (Open; the record defines only
  death).
- Ascent strain, appraisal and activation flows, relic abilities, combat and creatures,
  crews, PvP and camp aggression timers, trading, ranks and XP, procedural layouts,
  visible carrying of exceptional finds, offline income, and on-screen rope controls for
  mobile.
