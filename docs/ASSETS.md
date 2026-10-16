# Asset manifest (milestone 5)

**No external assets are used.** No Creator Store models, meshes, images, sounds,
animations, or catalog items were imported, purchased, or referenced by ID. Every visual
below is a **proxy** built from Roblox parts and built-in materials. These are working
stand-ins, not finished custom art. Each row names what should replace it.

Rules for future replacements:
- Use only asset IDs that have been verified, with the creator, source page, and permission
  recorded in the table below.
- No guessed IDs, no models that contain scripts, and no purchases without the owner's
  approval.
- Keep the replacement's collision and size compatible with the proxy (routes, hitboxes, and
  prompts depend on them).

There is still no art guide or reference image in the repository. The palette
(`Config.World.Palette`) and lighting preset (`Config.World.LightingPresets.VerdantRim`)
are provisional, built from the milestone 5 brief's wording.

## Selected assets

| Asset | Asset ID | Creator / source | Permission | Used for |
|---|---|---|---|---|
| (none yet) | | | | |

## Proxies in use

| Area | Proxy (what exists now) | Where | Replace with |
|---|---|---|---|
| Shaft walls | Limestone/Slate blocks in 40-stud rings, deterministic irregular radius | `World/Planner` buildWalls | Sculpted cliff meshes, or Smooth Terrain carved by a future installer step |
| Rim town paving, parapet, hills, ridge | Cobblestone/Limestone/Grass/Rock slabs | buildTown | Modular paving, wall, and terrain kit |
| Lodges, workshops, towers | Box walls, tilted-slab roofs, neon windows | buildBuilding | Modular timber and stone building kit (walls, roofs, balconies, signage) |
| Registry Hall, Relic Workshop, Supply Depot | The same kit, plus a terminal block, bench, and crates | buildTown (service district) | Hero props: registry desk, workbench, supply racks |
| Relic-powered lift crane | Mast, boom, neon crystal core, transparent cage | buildTown | Machinery mesh with a crystal core |
| Overlooks, Descent Gate | Plank decks, rails, struts; stone arch | buildTown | Carved railings and an archway mesh |
| Route ramps, landings, stairs, bridges | Slate/plank slabs with wood rails | buildWallRoute, buildElderTree | Carved steps, rope bridges, scaffold kit |
| Elder Tree | Wood cylinder trunk, LeafyGrass ball canopy, block roots | buildElderTree | Giant tree mesh with roots and hanging foliage |
| Floor trees, vines | Cylinders, balls, thin Grass strips | buildFloor, buildTown, buildShelf | Foliage and vine meshes (few, reused) |
| Ruins, standing stones, cache | Limestone/Brick blocks, neon glyph | buildFloor | Ruin kit and a cache prop |
| Waterfalls, pools, mist | Transparent Glass sheets, Glass disc, ParticleEmitter (default texture) | buildWaterfalls | Waterfall mesh or texture with a scrolling texture; mist texture |
| The Lower Dark | Basalt rings (non-colliding), tiny neon points, mist | buildFloor | Background silhouette meshes |
| Signs | BillboardGui text | signExtra | Carved sign meshes with SurfaceGui text |
| Windhook (world relic) | Slate hook pieces, neon engraving, floating stone ring, rarity-colored glow | `WorldRelics` buildForm | Engraved stone hook mesh with floating parts |
| Echo Lens (world relic) | Slate disc, glass lens, three floating shards, glow | `WorldRelics` buildForm | Stone lens mesh with floating shards |
| Thornback (regular creature) | Fabric body, ball head, wedge ears and thorns, neon eyes | `Creatures` buildModel (look "Wildlife") | Rigged creature mesh; must keep the root size and telegraph cues |
| Rootwarden (guardian) | Slate body and plates, neon rune lines, single eye, moss, root | buildModel (look "Construct") | Construct mesh; must keep the root size and telegraph cues |
| Explorer gear | Fabric backpack and bedroll, strap, rope coil, neon hip lantern | `Outfitter` | Accessory meshes (backpack, lantern, rope); must stay massless and non-colliding |
| Melee weapon | Metal blade part with a trail | `Gear` | Blade mesh |
| Action poses | Procedural Motor6D offsets (downed, bandage, revive, self-rescue, swing, Windhook, Echo Lens) | `Poses` | Animation clips (see below) |
| Landing feedback | Default-texture dust particles, camera dip | client `WorldFx` | Dust texture |
| Locomotion | Roblox's default R15 animations (unchanged) | engine default | An animation set chosen by the owner |

## Remaining tasks (exact)

1. **Animation clips.** No clips were imported. Each needs an animation published to the
   owner's account (or a verified, permitted asset), loaded by ID through
   `Humanoid.Animator`, with `Poses` kept as the fallback:
   - melee swing (0.25 s windup, then the strike)
   - downed crawl or idle
   - bandage (2.5 s)
   - revive (4 s, kneeling)
   - self-rescue (5 s)
   - Windhook gust
   - Echo Lens raise
   - a landing recovery
2. **Locomotion set.** Keep Roblox's default R15 set, or pick an animation set. If picking
   one, record its ID, creator, and permission here.
3. **Meshes and textures** for every "Replace with" entry above, recorded in "Selected
   assets".
4. **Art guide.** Add the latest art guide or reference images to `docs/`, then revisit the
   palette and lighting preset.
