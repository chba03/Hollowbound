# Milestone 2: manual test checklist (two Studio clients)

## Setup
1. Run `rojo serve` and connect the Rojo plugin (see README).
2. In Studio, open the **Test** tab. In the **Clients and Servers** section, set the
   dropdown to **2 Players**, then click **Start**. Studio opens three windows: a Server
   and two Clients (Player1, Player2).
3. In the **Server** window's Output, confirm:
   - [ ] `Self-test finished: N/N passed` with no `FAIL` lines
   - [ ] `Built dev map parts in ...s` and `Built dev map terrain in ...s` (skipped if the
         map was baked into the place)
   - [ ] `Relic spawner: 100 spawn points across 10 layers`
   - [ ] `Assigned plot 1 to Player1` and `Assigned plot 2 to Player2`
   - [ ] `Loaded data for Player1 (store: NoAccess)` (or `Access` on a published place
         with API access)
   - [ ] `Milestone 2 server ready.`
4. Each player appears on **their own plot** on the rim. The sign at the back of the plot
   shows their name. The top-left panel shows `$0`, `Rope: 140 studs · 16 studs/s`,
   and `Displays: 0/3`.

## 1. World look
- [ ] Each base is a grassy cliff-top camp: a plank deck with a coloured rug, stone
      pedestals with glowing tops, lantern posts with rope railings, rope coils, crates,
      barrels, a tent and campfire behind it, and a timber crane with pulleys and a rusty
      gear over the pit. A fence runs along the pit edge with a gap at the crane.
- [ ] Below each base, a wooden scaffold tower stands on the first ledge against the cliff,
      beside the rope (never in its way). Its three decks hold you; the truss on its side
      is climbable, so you can climb from the ledge back up to the rim.
- [ ] Behind the bases: a cobbled road, timber-framed houses with red, teal, green, and
      blue roofs, windmills, ruined stone towers, trees, and rocks between bases. Warm,
      hazy afternoon light at the surface. Looking down the pit shows green cliffs.
- [ ] Ride the rope down (dev cash **M** and rope upgrades help) and check each layer's
      look: trees and vines (1), upside-down trees (2), great waterfalls (3), cup trees and
      crystals in a wide cavern (4), pools spilling between ledges (5), roots and ruins
      (6), glowing pods and the dark hole (7). Fog, tint, and floating motes change per
      layer.
- [ ] Nothing blocks the rope or the ledge edges. Waterfalls and props pass through you.
- [ ] Standing in a layer 5 pool does not make the character swim.
- [ ] Behind the houses the ground rises straight into a ring of craggy terrain mountains
      (green at the foot, rock above) all the way around. There is no drop or gap
      between the town and the mountains, and no empty void in any direction.
- [ ] Climb over the mountains and fall off the far side: you are sent back to your base.
- [ ] No blue disc inside the pit.
- [ ] With the starting rope (layer 1), look down the pit: layers 2 and 3 are clear, and
      from layer 4 down a cloud layer makes everything hazy and dim (not a solid wall).
      Buy rope length: the clouds move one layer deeper per level; at rope level 5 and
      above they are gone.
- [ ] Frame rate stays steady while climbing through every layer (Studio: View > Stats or
      Shift+F5).

## 2. Plots
- [ ] Player1 and Player2 are on different plots. Other plots read `Plot N: vacant`.
- [ ] Player2 uses a pedestal or upgrade on Player1's plot: `This isn't your base.`
- [ ] Reset a character (Esc, Reset Character). It respawns on its own plot.

## 3. Rope deployment and climbing
- [ ] At the winch on the plot's edge (by the post), hold **E** on **Deploy rope**. A rope
      extends down from the arm over the pit. The message says it is 140 studs long.
- [ ] Use the winch again (**Climb down**). The character hangs on the rope facing the
      wall. The hint reads `W / S: climb   Space: let go`.
- [ ] **S** slides down, **W** climbs up. Climbing stops at the rope's end (140 studs).
- [ ] On the rope the character holds it in both hands in front of the chest.
      Sliding down goes hand over hand downward and climbing up goes hand over hand upward,
      both faster with faster climb speed. No rocking. Letting go returns to normal.
      The other client sees the same pose.
- [ ] Climb all the way up, at every climb speed level. At the top you always land on your
      plot; you never drop back into the pit.
- [ ] Climb down to a ledge, press **Space** next to it. You hop onto the ledge.
- [ ] Walk back to the ledge's edge near your rope. The hint `F: grab your rope` appears.
      Press **F** to get back on.
- [ ] Player2 cannot grab Player1's rope (only your own rope shows the hint).
- [ ] Climb the scaffold truss from the first ledge. On every scaffold deck, walk to the
      end of the plank walkway: `F: grab your rope` appears, and F puts you on the rope.
      Climbing past the walkways never bumps into them.

## 3a. Hauling Rig and Speed
- [ ] Each base has a Hauling Rig left of the deck: timber frame, pulley, a rope with a
      handle on the near side and a crate on the far side.
- [ ] Only your own rig shows a **Haul rope** prompt. Hold E: you snap into place facing
      the rope and are locked there. With no input at all, it hauls twice a second:
      blue `+N Speed` numbers float up, your character pulls hand over hand on the rope,
      and the crate rises a step per pull and drops after ten.
- [ ] Any movement key, Space, the gamepad stick, or the **Stop hauling** button lets go
      and you can walk again. Dying or resetting also lets go.
- [ ] The stats panel shows `Speed: N` and `climb N studs/s`; climb speed rises with
      Speed (16 at 0, about 52 at 1K, 88 at 1M) and on the rope you really climb faster.
- [ ] The **Climb speed** upgrade board now shows `Nx per pull`: buying it multiplies
      the Speed each pull gives (it no longer changes climb speed directly).
- [ ] The player list (Tab) shows Speed and Cash for everyone in the server, sorted by
      Speed. Speed is saved.

## 3c. Pickaxes and the Forge
- [ ] You spawn with the **Gardener's Pick** in your hotbar (key 1). Equip it: it is held
      head up. Click: the character winds the pickaxe up overhead and brings it down
      hard (other players see it too).
- [ ] Each base has a straw **Training Dummy** near the front right. Swing at it from
      close in front: orange damage numbers (10) pop up and it heals straight back.
      Swinging faster than the pickaxe's speed does nothing extra; swinging with your
      back to it, or from too far, does not hit.
- [ ] The **Forge** button (under Shop) opens the Forge: ten pickaxe cards with a 3D
      preview, layer, DAMAGE / SWINGS/S / REACH, and a button. Locked ones read
      `Reach layer N` until you have been that deep. Buying (green when affordable)
      equips it and replaces the tool in your hotbar. Owned ones can be re-equipped.
- [ ] Getting on the rope or the Hauling Rig puts the pickaxe away.
- [ ] At the Hauling Rig the legs and feet stay still while the arms pull.

## 3d. Creatures
- [ ] Each layer has three creatures roaming its ledges, matching the layer: Mosshopper
      (green, hops) in 1, Barkcrawler (bark spider) in 2, Spray Wraith (floating mist) in
      3, Shardback (ice beetle with glowing spines) in 4, Murkfin (fish) in 5, Clockwork
      Sentinel (brass golem) in 6, Marrow Wyrm (pale crawler, glowing pods) in 7.
- [ ] Walk near one on its ledge: it chases you and attacks in reach (the screen edges
      flash red). Sprinting gets away; it gives up far from where it started.
- [ ] It never follows you into a camp's yellow ring, and never reaches you on the rope.
- [ ] Hit it with your pickaxe: damage numbers, a health bar over it, and about six hits
      with that layer's pickaxe kill it (`Defeated a ...: +$N`). It fades out and a new
      one appears somewhere on the layer about 25 seconds later.
- [ ] Dying to a creature (or any way) ragdolls you, then you respawn at your base.

## 3b. Sprint
- [ ] Hold **Left Shift** while moving: you run faster and a stamina bar appears above
      the hints (yellow while sprinting). It empties in about 4.5 seconds and you slow
      down; the bar turns red until it refills a little.
- [ ] Release Shift: after about a second the bar refills (green) and fades out when full.
- [ ] Holding Shift while standing still or on the rope does not drain stamina.
- [ ] Shift no longer toggles Shift Lock.

## 4. Layers, falling, and the depth meter
- [ ] Below the rim, the top label reads `Layer 1: Mistfall Gardens`, and the screen's
      fog and tint change. Going back up restores the surface look.
- [ ] The big number at the top of the screen shows your depth in metres (SURFACE in
      town) and changes smoothly as you climb or fall. The stats panel shows your
      deepest depth.
- [ ] Jump off a roof or a short drop (under about 10 m): no damage. A drop of 10 to
      18 m hurts (`Hard landing ...`), more the farther you fall.
- [ ] From a layer 1 ledge, jump off the inner edge into the shaft. Nothing catches you
      at your rope's end: you keep falling, land (or hit the floor) and die as a
      ragdoll, with `You fell N m. That was too far.`, then respawn at your base.
- [ ] Falling past your rope and pressing **F** while close to it grabs it and saves you.
- [ ] Climbing the rope and letting go next to a ledge never hurts.
- [ ] Press **M** a few times (dev cash), click **Rope length** on the orange upgrade board.
      The rope extends. You can now reach layer 2; a `Layer 2: The Hanging Wood` banner
      shows when you enter it.

## 5. Relic spawns and pickup
- [ ] Relic models (not plain orbs) float clear of the ground and grass on the ledges of
      every layer, slowly turning. Each
      layer has its own relics; layers 1-2 never show gold or cyan, layers 3-4 never cyan.
      The same relic comes in different sizes ("Tiny", "Large", "Huge", "Colossal" in its
      name); bigger ones show a higher $/s in the prompt. Most are Common (grey light) or Uncommon (green);
      Mythic (purple) and Secret (red) sparkle; Divine (gold) and Godly (cyan, rainbow
      sparkles) send up a beam of light. Server Output shows `Self-test` lines for the
      70-type catalogue passing.
- [ ] Hold **E** on a relic: `Picked up ... Unsecured until registered at your base's
      terminal.` The relics panel shows it as **UNSECURED** with its layer and the income
      it would earn on display.
- [ ] Orbs respawn on empty spawn points a few seconds after pickup.
- [ ] The milestone 1 race tests still work: **J** in both windows near the same relic gives
      it to exactly one player. **K** from far away is rejected for range.

## 6. Camp
- [ ] Campfires, tents, and the yellow rings sit on top of the ground, not sunk into it.
- [ ] Each camp has a glowing yellow ring on the ledge showing the safe area. Inside the
      ring counts as the camp; one step outside does not.
- [ ] On layer 2 or below, walk into a camp (campfire on a ledge). The top label shows
      `Camp: refuge (relics stay unsecured) · Layer N`. The relic stays **UNSECURED**.

## 6b. Night and announcements
To test quickly, set `Config.Night.CycleSeconds` to 60 (and restore it after).
- [ ] The top of the screen shows `Nightfall in m:ss`; it turns yellow in the last minute.
      Warnings appear at 60, 30, and 10 seconds.
- [ ] At nightfall the sky turns dark for everyone, a `NIGHT FALLS` card appears, and
      every relic in the Hollow disappears. A player on the rope or a ledge is sent to
      their base. A player inside a camp's yellow ring stays. A player at their base
      stays. Unsecured relics they carry stay in their pack.
- [ ] During the night, going back into the Hollow sends you home again within a second.
- [ ] After 25 seconds: `DAWN`, the sky brightens, and every layer refills with relics.
- [ ] When a Divine or Godly relic spawns (most likely at dawn), every player sees a
      gold or cyan `DIVINE / GODLY RELIC SIGHTED` card naming the relic and its layer.
      Layers 1-2 never get Divine or Godly and layers 3-4 never Godly, even from a lucky
      roll.

## 7. Registration and display
- [ ] Back on your plot, use a pedestal before registering: `Register your relics at the
      terminal first ...`.
- [ ] At the teal **Registry Terminal**, hold **E**. The relic shows **REGISTERED** with the
      same ID.
- [ ] Use an empty pedestal (**Display best relic**). The relic's model with its name and
      `+$N/s` appears on it, the panel shows **ON DISPLAY**, and cash starts rising.
      The top-left panel shows the income and `Displays: 1/3`.
- [ ] With several registered relics, each pedestal use displays the highest-income one.
- [ ] Pedestals 4 to 10 are faded and their prompts are hidden. Buy **Display slots**
      (purple board) and pedestal 4 unlocks.
- [ ] **Take back** on a displayed relic returns it to the pack; income drops.

## 8. Upgrades
- [ ] Each of your three boards shows a panel facing your base: the upgrade's name,
      **Upgrade**, `Level N > Level N+1` in green, a red price button, and a purple box
      with what the next level gives. There are no E prompts on the boards.
- [ ] Click the price button: the button pops, the upgrade is bought, and the panel moves
      to the next level. The button is dark red while you cannot afford it.
- [ ] Clicking without enough cash: `Not enough cash ...`, and nothing changes.
- [ ] **Climb speed** makes W / S faster. At max level the button reads **MAXED**.
- [ ] Other players' boards show no panel to you (only their floating labels).

## 8b. Store (Emporium)
In Studio every item without a Roblox id is granted free as a test purchase
(`Config.Shop.StudioFreePurchases`). Passes bought this way last for the session only.
- [ ] The **Shop** button on the left opens the Emporium: brass frame, leather header with
      turning gears, copper valve close button, blurred game behind. Cards have light rays
      and a soft glow behind a 3D item, the name, a detail plaque, and a green price
      button. Hovering a card lifts it and outlines it in amber. Tabs jump to sections.
- [ ] **Featured:** this week's limited offer shows `Stock: 3/3` and `Restocks in ...`.
      Buy it three times: the stock counts down and the button reads **SOLD OUT**.
- [ ] **Coin Purses:** each shows what it pays at your current income (at least its
      minimum). Buying adds that cash.
- [ ] **Rope & Gear:** each shows `Lv N > N+1`; buying raises the level (the upgrade board
      panel updates too). At max level the button reads **MAXED**.
- [ ] **Lanterns:** Merchant's Lamp doubles your income (the stats panel shows it);
      Climber's Lamp doubles climb speed. Both show time left and end on their own.
      Lucky Lantern announces to everyone and shows its timer in the header.
- [ ] **Relic Crates:** buying puts a REGISTERED relic from that layer in your pack.
      A Divine or Godly crate find is announced to everyone.
- [ ] **Charters (passes):** buying shows **OWNED**. Double Income doubles income, Swift
      Climber speeds climbing, Iron Lungs makes sprint last longer, Featherfall lets you
      survive a ledge-to-ledge drop.
- [ ] Rejoin (with saving): cash, levels, crate relics, and running boost timers remain.

## 9. Saving (needs API access)
Without API access the Output says `Roblox API services unavailable - data will not be
saved`, and data resets each test. To test saving: publish the place, turn on **Game
Settings > Security > Enable Studio Access to API Services**, then:
- [ ] Earn cash, buy an upgrade, register and display a relic. Stop the test.
- [ ] Start again. Cash, upgrade levels, registered relics (same IDs), and displays are
      restored. An unregistered relic carried at the time you left is gone.

## Also check
- [ ] The Output windows show no errors. `Rope snap-back` lines should not appear during
      normal climbing.
- [ ] Player1 never sees Player2's relics in their panel.

## 3e. Climbing fatigue and marked carriers
- Without an Eternal or Godly relic you climb freely, however deep you went.
- Pick up an Eternal or Godly relic at, say, 135 m, then climb up: at 35 m the rope stops
  you and the hint says "The rare relic weighs you down: rest at a camp to climb higher."
  Above that, the hint shows how many metres you have left. Registering it lifts the limit.
- Stand inside a camp's yellow ring for 5 seconds: "Rested" appears and you can climb
  100 m above the camp. Going back to town resets everything.
- Pick up a Divine or Godly relic (the dev keys can spawn one): everyone sees an
  announcement naming you, the relic, and the layer, and you glow red through walls.
  Register it at your terminal and the glow goes within a second.

## 3f. Layers 8-10, Eternal, and rare spawns
- Climb (or dev-teleport) below layer 7: Emberdeep Forges (lava falls, furnaces, orange
  haze), Gloamcap Grotto (glowing mushrooms, violet haze), and The Lumen Core (pale
  spires, floating stones, a glowing core on the floor). Each has its creature
  (Slagcrab, Gloam Stalker, Lumen Seraph) and a camp.
- The rope board goes to level 14 (250Qa, 5Qi, 100Qi for the last three); the Forge
  shows Emberhammer, Gloamreaver, and Dawnbreaker.
- Normal refills never give Divine, Eternal, or Godly. The output shows
  `Rare spawn: <tier> in layer N` when one rolls (Divine about 60% a day). To test,
  set `Config.RareSpawns.Tiers[1].perDay` to 0.999 and RollSeconds to 10.
- Eternal relics are orange, rank between Divine and Godly, and appear from layer 4 down.

## 3g. Grapple and announcements in chat
- Every announcement (night, dawn, rare spawns, crate finds, rare pickups) also appears in
  the chat window in its tier colour.
- Buy the Grappling Hook in the Forge (Climbing Gear, $100K). It's a second hotbar tool.
- Drop past the end of your rope onto a ledge, equip the hook, click: a line shoots to
  the ledge ring above and you're hauled up onto it. Click again in the same 100 m band:
  "Your grapple is spent for 100-200 m". Go deeper into the next band and it works again;
  a trip to town resets every band.
- On the rope, in town, or above the first ledge it refuses with a message.

## 3h. Admin commands (live servers)
- As the owner, type `/hb help`: a pop-up lists the commands; F9 > Server log has usage.
- `/hb cash 5qi`, `/hb rope 14`, `/hb max`, `/hb layer 10`, `/hb rare godly`,
  `/hb night`, `/hb dawn`, `/hb home`, `/hb heal`, `/hb gear`, `/hb speed 1m`.
- Add a friend's name at the end to target them (`/hb max alex`).
- A non-admin typing `/hb cash 1e18` gets nothing, and the text never shows in chat.


## 3i. PvP knockdown, shared ropes, swing on live servers
Use Test > Clients and Servers with 2 players, and repeat once on the published game.
- Swing a pickaxe: the arm swing plays for you and the other player sees it (Studio
  and live). Works on R15 and R6 avatars.
- In the Hollow, hit the other player: they ragdoll, fly back, and stand up after about
  1.6 s. Hitting again straight away does nothing (immunity). No damage taken.
- In town (bases, rim) or while they're on a rope: hits do nothing.
- Join: your rope is already down; the winch says "Climb down".
- Stand near another player's rope in the pit: hint "F: grab <name>'s rope (climb up
  only)". On it, S does nothing and W climbs; at the top you land on your own base.
  If the owner leaves, you fall off.
- `/hb speed 1t`: walking and sprinting are slightly faster and stamina lasts a bit
  longer (about +7% speed, +10% stamina). It keeps growing past the climb cap:
  `/hb speed 1dc` is faster again.
