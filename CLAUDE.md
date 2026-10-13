# Hollowbound: notes for Claude

Original Roblox exploration and extraction game. Luau + Rojo. Design source:
`docs/Hollowbound_Game_Design_v0_2.pdf`. Its status labels are Decided, Delegated,
Proposed, and Open. Keep those distinctions in code comments and docs. Never treat a
Proposed example or Open value as settled.

Milestone 2 adds an incremental layer from the project's milestone 2 brief: a rim town of
8 player plots around a 10-layer pit (the Hollow), rope length as the progression stat that
gates depth, relic displays that earn passive cash, and saved data. It builds on the design
record's rules rather than replacing them. Original names only: no "Abyss", "Orth",
whistle ranks, or characters from the reference works.

## Core rules (preserve these)
- Picking up an item establishes ownership. Crews do not pool loot. (Decided)
- New relics stay **unsecured** until registered in **town**. The rim plots are town; each
  has a registry terminal. A camp is a refuge only; it never secures loot. (Decided)
- Only registered relics are saved and only registered relics can go on display.
- Each relic specimen has a unique ID and **permanent traits**. Repair and recharge restore
  usability and never change traits; no upgrades or rerolls. Saving and loading must keep
  ID and traits identical. (Decided)
- **Appraisal**, **activation**, and **registration** are separate states. None implies
  another. (Decided/Delegated)
- Type and rarity show on pickup. Traits are revealed only by appraisal, so unappraised
  traits never leave the server. Display income uses only type, rarity, and layer, never
  traits. (Delegated)
- Later: final death drops ordinary carried gear and unregistered relics; registered relics
  return to the owner needing repair or recharge. (Decided, not yet implemented)
- Exploration and creature encounters lead. PvP is secondary.

## Architecture
- `src/server`: authoritative. Generates specimens and owns inventories, ownership,
  registration, plots, displays, income, upgrades, rope state, and saved data.
  `RelicStore` is pure Luau with no Roblox services and must not yield in `claim`.
- `src/server/PlayerData.luau`: ProfileStore (vendored in `src/server/Vendor`, Apache-2.0).
  The schema is `PlayerData.Template`. Save levels, not derived stat values.
- `src/client`: input and presentation only. It must never decide game state. Rope
  climbing moves the local character for smoothness; `RopeService` validates every
  climber and owns the `HB_OnRope` attribute.
- `src/shared`: `Config` (all provisional numbers), `Net` (remote names), and
  `Progression` (pure level, layer, and income math used by both sides).
- Geometry is located through CollectionService tags (`Config.Tags`). The dev map is
  built at runtime in Studio and, while `Config.Dev.BuildMapOnLiveServers` is on, on live
  servers too (or baked in edit mode), and must never edit other
  Workspace content. It may write Smooth Terrain only inside the Hollow's own region, and
  only when that region has none (`DevTerrain.exists`).
- The pit's radius varies with depth (`Progression.pitRadiusAt`); never assume a fixed
  radius. Terrain carries large shapes; props (`DevDecor`) stay anchored, non-colliding,
  shadowless, and few. Visual direction: the reference chart supplied for milestone 2
  (the Hollow) and the base reference image (bases, town, scaffold towers; `DevBase`),
  with original names. `DevDecor`'s seeded draws must stay in the same order so the
  Hollow's props never move when surface decor changes.
- Relics: 70 types in `Config.RelicTypes` (built from the catalogue table). Tiers are
  Common, Uncommon, Mythic, Secret, Divine, Eternal, Godly (project owner's brief);
  layers 1-2 have none of the top three, layer 3 only Divine, layer 4 no Godly. Divine,
  Eternal, and Godly have spawn weight 0: they only come from rare spawns
  (`Config.RareSpawns`, per-day chances, Divine 60%). A type's tier is fixed and the specimen's
  `rarity` always equals it. Each specimen has a visible `size` (saved; old saves = 1)
  that scales its model and its income (`Progression.incomeOf`).
  Keep the six design-record type IDs so old saves load. Models: `RelicModels`.
- Night (`NightCycle`, `Config.Night`): every 5 minutes relics in the world are
  cleared, and players in the Hollow outside a camp go home; dawn refills. Camps are
  round (CampZone `Radius` attribute) with a yellow ring drawn by `Zones`. Divine and
  Godly spawns are announced to everyone (`Net.Announce`).
- Sprint: the server (`Stamina`) owns stamina and WalkSpeed; the client only sends
  whether Shift is held (`Net.Sprint`). Shift Lock is off in `default.project.json`.
- Store (`Store`, `Config.Shop`, shared `Perks`): the owner chose paid progress, relic
  crates, game passes, and weekly limited offers. The server validates every request,
  prompts the Roblox purchase, and grants on receipt (receipt ids saved, so never twice).
  Ids are 0 until created; Studio grants id-0 items free for testing. Perk effects go
  through `Perks` (income, climb speed, stamina, fall height, server luck).
- Speed (project owner): trained on each base's Hauling Rig (`Hauling`), clicks plus
  slow AFK pulls. Speed alone sets climb speed (`Progression.climbSpeed`, log curve,
  capped); the climb speed upgrade only multiplies Speed per pull. Leaderboard is the
  server player list (leaderstats Speed, Cash). No global boards.
- Pickaxes are the weapons (project owner), one per layer (`Config.Pickaxes`, `Arsenal`,
  `ForgeMenu`). Unlock by depth, buy with cash. The server checks every swing (cooldown,
  reach, facing) and damages models tagged `Tags.Enemy`; creatures will use that tag.
- PvP (`Arsenal`, `Config.Pickaxes.Pvp`, project owner): a pickaxe hit on another player
  does no damage; it ragdolls them (`FallDamage.ragdoll(character, true)` then
  `unragdoll`) and the victim's client applies the shove (`Net.Knockback`, client
  `Knockdown`). Not in town, not on ropes, short immunity after.
- Swing and rope poses are set on the joints directly (client `SwingFx`, `RopePose`):
  runtime-registered animations only play in Studio.
- Ropes auto-deploy on join. Anyone can grab anyone's rope but only climb up on it
  (`RopeService`, `HB_ClimbOwner`).
- Climb speed gives a tiny, uncapped walk/stamina bonus (`Config.Speed.MovePerClimb`,
  `StaminaPerClimb`, applied in `Stamina` from Speed before the climb caps).
- Creatures (`Enemies`, `Config.Enemies`): one kind per layer, kinematic (anchored,
  PivotTo), kept on ledges, never in camps or at the rope line. Tagged `Tags.Enemy`.
- Climbing fatigue (`Ascent`, `Config.Ascent`, project owner): only while carrying an
  unsecured Eternal or Godly relic. After climbing 100 m up from your deepest point since
  the pickup or your last rest, you must rest in a camp before climbing higher.
  The server holds climbers at `HB_AscentCeiling`; the client clamps to it for smoothness.
- Divine, Eternal, and Godly carriers (`RelicMarks`, project owner): picking one up is announced to
  everyone with the player and layer, and the carrier glows red (Highlight, always on
  top) until the relic is registered or lost.
- Grappling hook (`Grapple`, `Config.Grapple`, project owner): bought once at the Forge,
  given as a tool. It hauls you up to the ledge ring above, once per 100 m depth band
  (bands reset in town or on respawn). The server picks the target and moves you.
- Announcements also go to chat as local system messages (client `init.client`).
- Admin chat commands (`Admin`, `Config.Admin`): "/hb <command>" for the experience
  owner, listed user ids, and anyone in Studio. For playtests on live servers.
- Publishing: `rojo build publish.project.json -o build/Hollowbound.rbxl` makes a
  complete place (code, Baseplate, spawn, streaming on) to open in Studio and publish.
- Put provisional values in `Config`, not inline.

## Current milestone: 2, rim town and the Hollow
Done: milestone 1 (pickup, registration, camps, self-test, dev keys) plus plot allocation,
the 10-layer Hollow with layer atmosphere, rope deploy and climbing with server validation
fall damage with a ragdoll on fatal falls (no catch at the rope's end), a layer-based relic spawner, pedestal displays, passive
income, upgrades, ProfileStore saving, and a dev cash key (M).
Not yet: death and downed handling, appraisal, activation, relic abilities,
combat and creatures, crews, trading, ranks, procedural layouts, offline income, and mobile rope controls.

Manual test checklist: `docs/TESTING.md`.
