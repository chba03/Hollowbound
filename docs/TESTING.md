# Test checklist

This file has four kinds of tests. Keep them apart when you report results:

| Part | What | Storage | Where |
|---|---|---|---|
| Sections 1-15 | Milestone 1-2 regression: pickup, registration, death, recovery, service | Studio mock (purple badge) or real | Studio, 2 clients |
| Part A | Automated tests (Store, Abilities, Persistence) | **Test-only MockBackend**, never DataStores | Studio server Output |
| Part B | Milestone 3 two-client checks: appraisal, activation, loadout, abilities, controls | Studio mock or real | Studio, 2 clients |
| Part C | **Real persistence**: rejoin, restart, competing sessions | **Real DataStores** in a separate test experience | Published test experience |
| Part D | Short beginner playtest script | any | Studio |
| Part E | Milestone 4 automated tests (Survival, Creatures) | none (pure rules) | Studio Output or `lune run tools/run-tests` |
| Part F | Milestone 4 solo playtest | Studio mock or real | Studio, 1 client |
| Part G | Milestone 4 two-client checklist | Studio mock or real | Studio, 2-3 clients |
| Part H | Device, console, and cloud checks | real | phones, controllers, published test experience |
| Parts I-M | Milestone 5: automated world checks, install and save, solo acceptance, two-client, device and cloud | mixed | Lune, Studio edit mode, Studio play |

Mock results never prove real saving. Only Part C does.

Sections 1-6 cover milestone 1 and sections 7-15 cover milestone 2; all still apply.
Milestone 3 changes to expect while running them:
- Five orbs now: A-B as before, plus C-E on the extra pedestals (Studio fixtures).
- The pack shows extra lines (slot and charges), and a save badge sits at the top left.
- Nothing can be picked up or registered until the badge leaves **Loading saved relics...**.
- The bench message for nothing-to-do is `None of your relics need service or recharging.`

## Setup
1. Run `rojo serve` and connect the Rojo plugin (see README).
2. In Studio, open the **Test** tab. In the **Clients and Servers** section, set the
   dropdown to **2 Players**, then click **Start**. Studio opens three windows: a Server
   and two Clients (Player1, Player2).
3. In the **Server** window's Output, confirm:
   - [ ] `Self-test (mock storage only):`, then `Store`, `Abilities`, and `Persistence`
         lines, and `Self-test finished: N/N passed`, with no `FAIL` lines
   - [ ] `Built development placeholder map at X=200.`
   - [ ] `Built development service station next to the registration terminal.`
   - [ ] `Built development relic fixtures (pedestals C-E).`
   - [ ] Five `Generated ...` lines. A and B have **different IDs and trait values**
         (A Common, B Rare). C is an Uncommon Echo Lens; D and E are Exceptional.
   - [ ] `Milestone 4 server ready (storage: ...)`
   - [ ] For each player: `Loaded StudioMock profile for -1: 0 relic(s) ...` (or `Real`
         if API access is on). Each client shows a purple **MOCK STORAGE** badge in mock mode.
4. In both client windows, the player stands in **Town**. The top label reads "Town", and the
   pack shows "No relics carried." Walk north (forward from spawn) across the walkway,
   through the camp, to the expedition area. The two glowing orbs are on pedestals.

Write down the two specimen IDs from the server Output: `A = ________`, `B = ________`.

## 1. Successful pickup
- [ ] Player1 walks to orb **A**. The prompt shows `Windhook (<rarity>)`. Hold **E**.
- [ ] The orb disappears in **both** client windows.
- [ ] Player1's pack shows: Windhook, rarity in color, **UNSECURED**,
      `Unappraised · Needs activation`, and an ID that matches the first 8 characters of A.
- [ ] No trait values appear on the client. Optional check: in the Player1 window, the
      Explorer under ReplicatedStorage and the HUD show no trait numbers.
- [ ] Server Output: `Player1 picked up <A> via prompt`.

## 2. Simultaneous pickup (orb B)
Option (a), dev key, most reliable:
- [ ] Both players stand within a few studs of orb **B**.
- [ ] Press **J** in Player1's window, then within about 3 seconds press **J** in Player2's
      window. Both messages should name the **same** server time.
- [ ] When that time arrives, exactly **one** player gets `Picked up Windhook`. The other
      gets `That relic is no longer there.` or `Someone else picked that relic up first.`
- [ ] Only one pack contains B. The server Output shows one `picked up` line and one
      `Rejected pickup` line.

Option (b), by hand: both players hold **E** on orb B at about the same moment. The same
expectations apply. This rarely produces a true same-frame race.

> Restart the test (Stop, then Start) to get fresh specimens. The server regenerates
> new IDs and traits on every start, because milestone 1 has no persistence.

## 3. Rejected out-of-range pickup
Restart so both orbs are present again.
- [ ] Player2 stands about 20 or more studs from both orbs (in the expedition area, or back
      in town). The pickup prompt is not visible.
- [ ] Press **K** in Player2's window. The message reads `Dev: requesting pickup from NN studs`.
- [ ] The server rejects it: `Too far away to pick that up (NN studs, limit 12).` The orb
      stays in the world, and Player2's pack is unchanged.
- [ ] Walk within 12 studs of the orb, without using the prompt, and press **K**. The pickup
      succeeds, which confirms the server limit is what rejected the first request.

## 4. Camp visit leaves fresh relics unsecured
- [ ] Carrying an unsecured relic, walk into the **camp** (the grass square with the
      campfire). The top label reads `Camp: refuge (relics stay unsecured)`. A message
      confirms that relics stay unsecured.
- [ ] The pack still shows **UNSECURED**. Server Output: `entered camp; 1 unsecured relic(s) unchanged`.
- [ ] Leave the camp and enter it again. The relic still shows **UNSECURED**.

## 5. Town registration
- [ ] Walk back to town. A message suggests the Registry Terminal.
- [ ] At the terminal (the teal block with the glowing screen), hold **E** on
      **Register relics**. The message reads `Registered: Windhook (<rarity>)...`.
- [ ] The pack shows **REGISTERED** with the **same ID** as before. It still shows
      `Unappraised · Needs activation`, because registration does not appraise or activate.
- [ ] The server Output `registered <fingerprint>` line shows the same ID and trait values
      as that specimen's `Generated` line.

## 6. Repeated registration
- [ ] Use the terminal again. The message reads `Nothing new to register. Already registered: ...`.
- [ ] The pack still has exactly one entry with the same ID, and nothing is duplicated.
- [ ] Server Output: `re-used terminal; 1 already registered, no changes`.
- [ ] A player with no relics who uses the terminal sees `You are not carrying any relics.`

## Also check
- [ ] Player2 cannot see or register Player1's relics.
- [ ] Reset Player1's character (Esc, Reset Character). The pack still shows their relics,
      because death handling is not implemented in this milestone.
- [ ] The Output windows show no errors or warnings, except FAIL lines if a self-test failed.

---

# Milestone 2: final death, recovery, and service

Restart the test (Stop, then Start) before this part so both orbs are fresh. Keep the
**Server** window's Output visible. With `LogTraitsToServerOutput` on, the
`Generated`, `picked up`, `dropped`, and `serviced` lines show each specimen's ID and
traits, so you can compare them. Every death here is final; the downed/revive stage is
a later milestone.

## 7. Setup: one registered and one unregistered relic
- [ ] Player1 picks up orb **A**, walks to town, and registers it (pack: **REGISTERED**,
      `Good condition`).
- [ ] Player1 returns to the expedition area and picks up orb **B** (pack: B **UNSECURED**).
- [ ] Note both IDs: `A = ________` (registered), `B = ________` (unregistered).

## 8. Dying with registered and unregistered relics
- [ ] Player1 stands next to a pedestal and resets (Esc, then **Reset Character**).
- [ ] An orb appears at the death spot on the ground, reachable on foot, in **both**
      windows. Its prompt reads `Windhook (<rarity>), dropped`.
- [ ] Only **one** orb appears (B). A never appears in the world.
- [ ] Player1 sees a message: `You dropped: Windhook (...)`.
- [ ] Server Output:
  - `dropped <B id>|...|registered=false|appraised=false|activated=false at death position`
  - `kept registered <A id>; needs service`
  - `Final death of Player1 (Humanoid.Died): 1 dropped, 1 protected`
- [ ] After respawn, Player1's pack shows **only A**: **REGISTERED**, **NEEDS SERVICE**,
      the same ID as before, and still `Unappraised · Needs activation`. A message says
      1 registered relic returned and needs service in town.

## 9. Another player recovers the dropped relic
- [ ] Player2 walks to the dropped orb B and holds **E**.
- [ ] Player2's pack shows B: **UNSECURED**, same short ID as before, `Unappraised · Needs activation`.
- [ ] Server Output: `Player2 picked up <B id>|<same traits as its Generated line>|...`.
      Compare the trait values with B's `Generated` line; they must be identical.
- [ ] Player1's pack does not show B.

## 10. Simultaneous recovery requests
- [ ] Player2 resets near a pedestal so B drops again. (Player2's own death also tests
      a relic changing hands twice.)
- [ ] Both players stand within a few studs of the dropped B orb.
- [ ] Press **J** in both windows within the same 5-second window (both messages name the
      same server time).
- [ ] Exactly one player gets `Picked up`; the other gets `That relic is no longer there.`
      or `Someone else picked that relic up first.`
- [ ] B appears in exactly one pack. Server Output has one `picked up` and one `Rejected` line.
- [ ] Optional: repeat with both players holding **E** at once.

## 11. Protected relics stay with their owner
- [ ] While A is **NEEDS SERVICE**, no orb for A exists anywhere. Check the
      `Workspace.HollowboundWorldRelics` folder in the Server window's Explorer: there is no
      `Relic_<A id>` part.
- [ ] Player2's pack never shows A.
- [ ] Player1 resets again while still carrying only A. No orb appears; Output reads
      `0 dropped, 1 protected`. A is still in Player1's pack once, still **NEEDS SERVICE**.
- [ ] Player1 uses the **Registry Terminal**. The message reads `Nothing new to register...`
      and A still shows **NEEDS SERVICE** (registration does not clear it).

## 12. Town service
- [ ] Player2 (carrying nothing that needs service) uses the **Relic Service** bench
      (the wooden bench beside the terminal). Message: `None of your relics need service or recharging.`
- [ ] Player1 uses the bench. Message: `Serviced: Windhook (...)`. A now shows
      `Good condition`, and is still **REGISTERED**, `Unappraised · Needs activation`, with the
      same ID.
- [ ] Server Output: `serviced <A id>|Windhook|<rarity>|<same traits>|registered=true|appraised=false|activated=false`.
- [ ] Use the bench again: `None of your relics need service or recharging.` The pack still holds one A.
- [ ] Town check: in the **Server** window, select `HollowboundDevServiceStation` and
      move it (Model tab, Move) outside the town ground (for example, onto the walkway).
      This change lasts only for the playtest. After resetting Player1 so A needs service
      again, walk to the moved bench and use it: `Relic service is only available in town.`
      A still needs service.

## 13. Repeated death callbacks, respawns, and service requests
- [ ] Player1 carries one registered relic (A) and one fresh unregistered relic. If none is
      left, restart and repeat section 7.
- [ ] Press **L** in Player1's window (dev: die and report the death 3 times).
- [ ] Server Output shows exactly **one** `Final death of Player1 (...)` line (its source
      is `dev repeat 1` or `Humanoid.Died`, depending on event timing) and exactly **two**
      `Ignored duplicate death for Player1 (...)` lines. Exactly **one** dropped orb appears.
- [ ] After respawn, the pack holds A once, marked **NEEDS SERVICE**. No duplicates.
- [ ] Reset Player1 three times in a row (wait for each respawn). Each time Output shows
      `0 dropped, 1 protected` (or the unregistered relic count if any were carried), and
      the pack still holds exactly one A.
- [ ] Hold **E** on the service bench repeatedly. Only the first use services A; later
      uses report nothing to service.

## 14. Dying below the map
- [ ] In the **Server** window, delete `Workspace.Baseplate`. This lasts only for the
      playtest. Skip the deletion if your place has no baseplate.
- [ ] Player1 carries an unregistered relic and walks off the side of a walkway, falling
      until the character dies.
- [ ] Output: `dropped <id> ... at last safe position`. The orb sits on the walkway or
      platform near where Player1 last stood, not in the void, and can be picked up.

## 15. Regression
- [ ] Sections 1-6 still behave as described: pickup, simultaneous pickup, out-of-range
      rejection (K), camp visits, registration, and repeated registration.
- [ ] No trait values appear in either client's HUD at any point.
- [ ] Self-test reports all passed, and no errors appear in any Output window.

---

# Milestone 3: persistent, usable relics

## Part A. Automated tests (test-only mock storage)

These run at server start in Studio (`Config.Dev.RunSelfTest`). They use `MockBackend`,
an in-memory **test-only** backend with failure injection. They never call ProfileStore
or DataStores and cannot touch player data. They prove the game's rules, not real
DataStore behaviour.

They also run outside Studio with Lune (pinned in `rokit.toml`; run `rokit install` first):
```bash
lune run tools/run-tests
```
`tools/run-tests.luau` rebuilds the Rojo tree from `src/` and stands in for the few
Roblox APIs the tests touch: `game:GetService`, `script`, `Random` (a different random
sequence from Roblox), `Color3`, and `warn`. Anything else raises an error. It exits 1
on any failure. Passing under Lune does not replace the Studio run, which uses real
Roblox APIs.

- [ ] Start any playtest. The server Output shows `Store: N/N passed`,
      `Abilities: N/N passed`, `Persistence: N/N passed`, and
      `Self-test finished: N/N passed`, with no `FAIL` lines and no `suite crashed`.

What they cover:

| Requirement | Suite |
|---|---|
| Same specimen and states survive rejoin (same server) and restart (fresh server) | Persistence 1 |
| Only registered relics persist; unregistered loot cannot be banked | Persistence 2 |
| Death drops the original; another player recovers and registers it; the former owner cannot regain it by rejoining, even with a stale record | Persistence 3, Store |
| Registered relics survive death needing service and cannot be looted | Persistence 4, Store |
| Failed loads (no blank profile, no overwrite), failed saves (Retrying, nothing written) | Persistence 5, 6 |
| Late or out-of-order save callbacks, repeated departures | Persistence 7, 9 |
| Competing sessions: the old server stops, keeps no copy, cannot write | Persistence 8 |
| Newer schema refused; unreadable records kept; anti-wipe guard; deterministic migration | Persistence 10-12 |
| Appraisal, activation, registration, and service independent | Store |
| One exceptional at most, duplicate slots and forged IDs or slots refused | Store |
| Abilities: activation, service, and charge gates; cooldowns survive swaps, copies, and death; trait tuning within caps | Abilities |
| Milestone 1-2 rules (claims, registration, death, recovery, service) | Store |

## Part B. Two-client Studio checks

Start **Test**, then **2 Players**. Mock storage (purple badge) is fine for this part.
Wait until both badges leave `Loading saved relics...`. Open the relic menu with **B**,
**D-pad down**, or the **Relics** button.

### B1. Appraisal (traits stay server-side until then)
- [ ] Player1 picks up **A** (Windhook). In the menu, A's card says
      `Traits hidden until appraised`, `Unappraised · Needs activation`, `Charges 3/3`.
- [ ] Away from town, press **Appraise**: `Go to a registry terminal or service station in town.`
- [ ] At the teal terminal, press **Appraise**: `Appraised Windhook (...)`. The card lists
      Reach, Carrying strength, and Charge efficiency. The values match A's `Generated`
      line in the server Output.
- [ ] A is still **UNSECURED**, `Needs activation`, and `Charges 3/3`; appraisal changed nothing else.
- [ ] Player2's HUD never shows A or its traits.

### B2. Activation and Windhook
- [ ] Equip A: **Equip**, then **Slot 1**. Slot 1 shows `Windhook` and `Needs town activation`.
      Press **1**: `Needs town activation`.
- [ ] At the terminal, press **Activate**: `Activated Windhook`. Still unregistered, and
      appraisal unchanged.
- [ ] Press **1**: the character is pushed forward and up, a wind burst shows (Player2
      can see it), and the camera kicks. The slot shows `●●○` and a dark cooldown overlay
      shrinking with a countdown.
- [ ] Press **1** during the cooldown: `Cooling down: N s left.` The charge count does not drop.
- [ ] Leap at a wall: the wall stops you (no passing through). Spamming **1** cannot keep
      you airborne: one push at a time, then the cooldown, then no charges.

### B3. Echo Lens
- [ ] Player1 picks up **C** (Echo Lens). Its card says `Works immediately`. Equip it in slot 2.
- [ ] Near other orbs, press **2**: an expanding blue sphere, and each relic within range
      gets a highlight and a label such as `Windhook (Rare)`. The message reads
      `Echo pulse: N relic(s) marked.`
- [ ] Player2's window shows **no** sphere and no marks.
- [ ] Player2 picks up a marked orb: its mark disappears from Player1's view with the orb.
- [ ] Pulse again, then unequip the lens: the marks disappear at once.

### B4. Exceptional limit and swapping
- [ ] Player1 picks up **D** (Echo Lens, Exceptional) and **E** (Windhook, Exceptional).
- [ ] Equip D in slot 3. Then equip E in another slot:
      `Only 1 exceptional relic(s) can be equipped at a time.`
- [ ] Equip E **into slot 3** (D's slot): allowed, and D returns to the pack (swap).
- [ ] The menu header shows `exceptional 1/1 used`.

### B5. Cooldowns across swaps and copies
- [ ] Use the Echo Lens in slot 2, then equip the other Echo Lens copy and press its slot:
      `Cooling down`.
- [ ] Unequip and re-equip the first lens: still `Cooling down` with the same time left.
- [ ] Reset the character (Esc, then Reset Character). After respawning, still cooling
      down if time remains.

### B6. Charges, registration, and service
- [ ] Use Windhook until `No charges: recharge in town` (wait out each cooldown).
- [ ] Register at the terminal: still `Charges 0/3`; registration does not refill. If
      Windhook was activated, it stays activated.
- [ ] At the bench: `Serviced: Windhook (...)`. `Charges 3/3`, and registration,
      appraisal, activation, and ID unchanged.
- [ ] Use the bench again: `None of your relics need service or recharging.`

### B7. Death with a loadout
- [ ] Player1 has a **registered** Windhook in slot 1 and an **unregistered** relic in slot 2.
      Reset Player1 in the expedition area.
- [ ] The unregistered relic drops as an orb (`dropped <same id>...` in Output) and slot 2
      is empty. The registered Windhook stays in slot 1 with **NEEDS SERVICE** and
      `Charges 0/3`. Pressing **1** gives `Needs service in town`.
- [ ] Player2 recovers the dropped relic. It is unequipped for Player2. After Player2
      equips it, they can use it (their own cooldowns).
- [ ] Player1 can never use or see it again.

### B8. Forged and duplicate requests (Studio command bar)
In **Player1's** client window, open **View**, then **Command Bar**. Each check is one
line like the example below. Replace `ID` with the full ID of a relic Player1 carries
(from the server Output) and `OTHER` with one that Player2 carries. Change only the
arguments after `InvokeServer(`.
```lua
print(game.ReplicatedStorage.HollowboundRemotes.RelicAction:InvokeServer("Equip", "ID", 0).message)
```
Expected answers:
- [ ] `("Equip", ID, 0)`, `("Equip", ID, 4)`, `("Equip", ID, "1")`, `("Equip", ID, 1.5)`:
      `That slot does not exist.`
- [ ] Equip ID in slot 1, then `("Equip", ID, 2)`: `That relic is already equipped. Unequip it first.`
- [ ] `("Equip", OTHER, 1)`: `That relic is not yours.`
- [ ] `("Equip", "made-up", 1)`: `That relic is not available.`
- [ ] `("Use", 9)`: `That slot does not exist.` `("Fly")`: `Unknown action.`
- [ ] `("Appraise", OTHER)` at a desk: `That relic is not yours.`
- [ ] Sending about 20 requests at once (for example, with a `for` loop in the command
      bar) gives `Too many requests. Slow down.` for some of them.
- [ ] Nothing changed in either player's pack.

### B9. Controls on every input type
- [ ] Keyboard and mouse: **1**/**2**/**3** use slots, **B** toggles the menu, and every
      menu button works by clicking.
- [ ] Touch: **Test**, then **Device**, then choose a phone (for example iPhone 14). Tap
      slots to use them, tap **Relics**, then Equip, Slot N, Unequip, and Close. Text is
      readable and buttons are not hidden by the thumbstick or jump button.
- [ ] Controller (if one is connected): **D-pad down** opens the menu and selects the first
      button. The D-pad moves selection, **A** presses, and **B** closes. With the menu
      closed, D-pad left/up/right use slots 1/2/3. Hints on the slots change to `D-pad ...`.
- [ ] Resize the Studio window very small and very large: the HUD scales and the menu fits.

### B10. Temporary departure rule (Studio)
- [ ] Player2 carries an unregistered relic in the **expedition area** and closes their
      client window. Output: `Final death of Player2 (left outside town)` and a
      `dropped ...` line. The orb appears where Player2 stood, and Player1 can pick it up.
- [ ] In a new test, Player2 carries an unregistered relic **in town** and closes the
      window. Output: `left (Town): 1 unregistered relic(s) released, no penalties`.
      Registered relics are not marked Needs service.
- [ ] Press **Stop** with both players carrying registered relics. Output shows
      `left during shutdown: saved as is, no penalties`.

### B11. Regression
- [ ] Sections 1-15 still pass. Mutations wait for loading: right after **Start**, a
      pickup attempted while the badge says `Loading...` is refused with
      `Your saved relics are still loading.` (Mock loading is fast, so this may be hard
      to catch; Part C shows it more easily.)

## Part C. Real persistence (separate published test experience)

Real DataStores belong to one experience. Use a **separate test experience** so tests
never touch real players' data.

### Setup (once)
1. Open your test place in Studio (connected to Rojo). Choose **File**, then
   **Publish to Roblox As...**, then **Create new experience**. Name it, for example,
   "Hollowbound Persistence Test". Keep it private. Never use this for the real game's
   experience.
2. Go to **Home**, then **Game Settings**, then **Security**, and turn on
   **Enable Studio Access to API Services**. Save.
3. Recommended: set `Config.Persistence.StudioMockWhenNoAccess = false` while testing,
   so a missing permission kicks you instead of quietly using mock storage.
4. Optional: keep `StoreName = "HollowboundPlayers_v1"`, or use a test-only name such as
   `HollowboundPlayers_test1` for an extra layer of isolation.
5. Press **Play**. The badge is **not** purple and Output shows `Loaded Real profile`.
   Studio's Play uses your real UserId. Multi-client tests use negative test IDs
   (Player1 = -1), saved only in this test experience.

### C1. Restart in Studio (real storage)
- [ ] Press **Play**. Pick up A, appraise, activate, register, equip it in slot 1, and use
      it once. Wait for **Saved**. Note the ID, trait values, `Charges 2/3`, and slot.
- [ ] Press **Stop**, then **Play** again (a new server). The badge shows `Saved`; A is in
      slot 1 with the same ID, traits, appraisal, activation, registration, and charges.
      If you restart within the cooldown, it is still cooling down.
- [ ] Output shows no `Kept saved relic ... unloaded` warnings.

### C2. Real accounts in the published test experience
Publish the latest code (**File**, then **Publish to Roblox**). Then play from the Roblox
website or app.
- [ ] **Leave and rejoin in town:** registered relics, loadout, and states return exactly.
      Unregistered relics carried at the time do not return.
- [ ] **Leave outside town** with one registered and one unregistered relic: on rejoin, the
      registered relic needs service and has 0 charges; the unregistered one is gone. With
      a second account in the same server, check that the dropped orb appeared and can be
      recovered and registered by that account, and that the first account never gets it back.
- [ ] **Server restart:** Creator Dashboard, then your test experience, then **Servers**,
      then **Shut down all servers** (or publish an update and restart servers). Rejoin:
      registered relics are intact and **not** marked Needs service (shutdown applies no
      penalties).
- [ ] **Competing sessions:** while playing on device 1, join with the same account on
      device 2. Within about 40 s, device 1 is kicked ("profile was opened on another
      server") or device 2 waits for device 1 to release. The relics appear **once**, on
      the session that holds the profile.
- [ ] **Inspect data (optional):** Creator Dashboard, then **Data Stores**, then the store
      name and key `Player_<UserId>`: `Relics` contains only registered relics, and
      `Revision` grows.

Failed loads and saves, stale callbacks, and repeated callbacks cannot be forced safely
on real DataStores; they are covered by Part A's failure injection.

## Part D. Beginner playtest script (about 10 minutes)

1. Press **Play**. The top-left badge shows the storage mode. Wait until it no longer
   says `Loading`.
2. Walk forward (away from the spawn pad), past the camp, to the expedition area. There
   are glowing orbs on pedestals.
3. Find the **Echo Lens** on pedestal C, in the row of pedestals nearest the walkway.
   Hold **E** to pick it up.
4. Press **B** (or tap **Relics**). On the Echo Lens card, press **Equip**, then **Slot 1**.
   Close the menu.
5. Press **1**. A blue pulse spreads out and other relics glow with labels. That is the
   Echo pulse.
6. Pick up the **Windhook** on pedestal A. Equip it in slot 2. Press **2**: it says it needs
   town activation.
7. Walk back to town and stand by the teal **Registry Terminal**. Open the menu: press
   **Activate** on the Windhook, and **Appraise** on both relics to see their traits.
8. Hold **E** on the terminal to register both. The badge shows **Saving...**, then
   **Saved** (or the purple MOCK label in Studio without API access).
9. Press **2** to Gust leap. Leap again after the cooldown ends.
10. Walk out to the camp and reset your character. You respawn with both relics, now
    **NEEDS SERVICE**. Hold **E** at the wooden **Relic Service** bench in town to repair
    and recharge them.

---

# Milestone 4: the first dangerous PvE expedition

Note (milestone 5): the guardian is now named **Rootwarden** in game, with construct
dressing. Wherever this section says "Matriarch", expect "Rootwarden"; its behaviour is
unchanged.

Setup for every part below: **Test**, then **Start** (1 player for the solo script,
**2 Players** for Part G). Mock storage (purple badge) is fine. The server Output should
also show:
- [ ] `Built development supply station next to the registration terminal.`
- [ ] `Built development encounter arena (2 Thornbacks, 1 Matriarch den with a cache, a test camp).`
- [ ] `Milestone 4 server ready (storage: ...)`, and no `Creature #... update failed` warnings.

The arena is behind the expedition area: walk past pedestals A-E and cross the bridge.

## Part E. Automated tests (pure rules, test-only)

Run either way. Both use only pure modules and the test-only mock storage:
- Studio: the server Output at start.
- Outside Studio: `lune run tools/run-tests`.

- [ ] `Survival: N/N passed` and `Creatures: N/N passed`, plus the milestone 1-3 suites,
      with `Self-test finished: N/N passed`.

| Requirement | Covered by |
|---|---|
| Damage amounts validated; lethal damage downs, never kills; no damage while downed | Survival |
| Revive needs the current character and down (stale or duplicate revives refused, including after a respawn) | Survival |
| Bleedout fires only for the current down; death recorded once | Survival |
| Runs: start on leaving town, kept through camps, finished once; allowance per run, stale runs refused | Survival |
| Timed actions: server clock, one at a time, cancelled when conditions fail, interrupts | Survival |
| Bandage consumed only on completion, never when interrupted | Survival |
| One helper per down; simultaneous helpers refused | Survival |
| Supplies: bounded refill, capacity, unique drops, one winner, no duplication, partial pickups | Survival |
| Creature brain: detection, telegraph then strike, recovery opening, downed ignored, leash and reset, protected zones, lost sight, unreachable targets | Creatures |
| Guardian cycles: locked cache, exactly one reward per cycle, stale or repeated callbacks, environmental loss, repeated cycles | Creatures |
| Contested reward pickup, and the reward keeping ID and traits through death, recovery, and registration | Creatures |
| Melee hit selection: range, arc, line of sight, one hit per target, non-finite input, cooldown | Creatures |

Not automatable outside Studio (checked by hand below): Roblox physics and pathing,
ProximityPrompt hold events, Humanoid death events, and the HUD.

## Part F. Solo playtest (about 15 minutes)

1. [ ] Spawn in town. The top-left panel shows `Health 100 / 100` and `No weapon`.
2. [ ] Hold **E** at the green **Supply Station** next to the terminal: `Supplied:
       Starter blade x1, Bandage x3, Self-rescue kit x1`. A blade appears in your right
       hand. Use the station again: `You already carry the basic loadout.`
3. [ ] Try **Attack** (click, **F**, or the Attack button) in town:
       `You cannot attack from inside town or a camp.`
4. [ ] Walk out: the label changes to `Exploring` and a message says the expedition
       started. Health no longer regenerates.
5. [ ] Cross into the arena. A **Thornback** notices you (when you are in its view, or
       within about 10 studs) and chases. When it glows red with a "!", the banner warns
       `...is about to strike you: move away!`. Step back out of reach: no damage.
6. [ ] Fight it: each swing shows the blade sweeping, and hits show `Hit: 18`. Swinging
       while on cooldown does nothing extra. It falls after 4 hits (60 health), fades,
       and respawns after about 90 s.
7. [ ] Take some damage, then press **H** (Heal): `Bandaging...` with a progress bar,
       then `Bandaged: +35 health`, and the bandage count drops by 1. Start another and get
       hit: `You were hit. The bandage was not used.` The count does not change.
8. [ ] Break contact: run behind a cover wall and stay out of sight. After a few seconds
       the Thornback gives up and walks back to its den.
9. [ ] Camp protection: lure a Thornback toward the **test camp** (front-right corner)
       and step inside. It stops at the edge and returns, and you take no damage inside.
       Attacking from inside is refused.
10. [ ] The **Matriarch** at the back wall guards a cache. The cache prompt says it is
        sealed while she lives. Fight her using her **long recovery after each strike**
        (the opening), and bandage when needed. When she falls, `Unlocked` appears and a
        relic orb sits on the cache. Echo Lens (if equipped) marks it.
11. [ ] Pick up the reward. Server Output shows `Encounter DevArenaDen reward: ...` and
        later `claimed ... resets in 180 s`.
12. [ ] Get downed on purpose (let a Thornback hit you at low health): `DOWNED`,
        `Bleeding out in 30 s`, crawling, no jumping. Attack, Heal, relic slots, and pickups
        are refused. Creatures stop attacking you.
13. [ ] Press **H** (Rescue kit): after 5 s you stand with 25 health, the kit count drops
        by 1, and `Self-rescues left this expedition: 0`.
14. [ ] Get downed again: the hint says the self-rescue was already used. Visit the test
        camp first if you like: the allowance stays 0. Let the bleedout finish: final
        death drops the unregistered reward relic **and** a supplies crate beside it.
        You respawn in town with an empty supply list.
15. [ ] Refill, walk back, pick up your crate (`Picked up ...`) and the relic orb, return
        to town (`Back in town...`), and register the relic at the terminal. The pack shows
        **REGISTERED**, with the same ID as in the `reward:` Output line.

## Part G. Two-client checklist

Start **2 Players**. Both players take supplies first.

### G1. Revive and its cancellation
- [ ] Player1 gets downed in the arena. Player2 sees a red `DOWNED` marker above Player1
      and a **Revive** prompt up close. Player1 does not see a prompt on themself.
- [ ] Player2 holds **Revive** for 4 s: Player1 stands with 35 health, and both get
      messages. Player1's overlay shows `Player2 is reviving you...` with progress.
- [ ] Release early: `You let go. The revive stopped.` Player1 stays downed.
- [ ] Walk away while holding (beyond 9 studs) or put a wall between you: the revive
      cancels with a reason.
- [ ] Get hit while reviving: the revive cancels (`You were hit.`).

### G2. Simultaneous helpers (needs a third client, or swap roles)
- [ ] With a third player (**3 Players**), two helpers hold Revive together. Only one
      revive starts (`Someone is already reviving them.`), and Player1 is revived once with
      35 health, not 70.

### G3. Downed, final death, and loot transfer
- [ ] Player1 carries an unregistered relic plus supplies and bleeds out in the arena.
      One relic orb and one supplies crate drop (Output: `dropped supplies loot-N`).
- [ ] Player2 and Player1 (after respawning) both try to take the crate at the same
      moment: one gets the items and the other gets `Those supplies are gone.` Nobody
      ends up with extra items.
- [ ] Player2 with full bandages picks up a crate holding bandages: only what fits is
      taken. The crate stays with the rest, and its label updates.

### G4. Idempotency: reset, void, departure
- [ ] Player1 downed, then **Reset Character**: exactly one `Final death of Player1` line,
      one drop set, no revive prompt left behind, and no `bled out` line afterwards.
- [ ] Player1 downed near an arena edge, Baseplate deleted in the Server window: crawl off
      the edge. One final death, items at the last safe position.
- [ ] Player1 downed in the arena, then closes their window: Output shows
      `Final death of Player1 (left outside town)` once. Relics and a supplies crate drop.
- [ ] Press **L** (dev repeated death) while carrying supplies: one final death, one crate.
- [ ] After respawning, an old revive or bleedout from the previous character never
      affects the new one (no stray `revived` or `bled out` lines).

### G5. Contested cache and guardian behaviour
- [ ] Both players fight the Matriarch. When she falls, both press **E** on the reward
      at once (or press **J** in both windows): exactly one owns it. The other gets
      `Someone else picked that relic up first.` (or `That relic is no longer there.`).
- [ ] Whoever lands the last hit gets no automatic reward; only the pickup counts.
- [ ] The Matriarch never attacks a downed player while a standing one is near. With
      both downed, she returns to her den.
- [ ] Both players leave the arena and come back before 180 s: the encounter has **not**
      reset (no new guardian). Rejoining also does not reset it.
- [ ] After the claim and 180 s, a new Matriarch appears and the cache is locked again
      (`Encounter DevArenaDen resets` in Output). Repeat a few cycles: one reward per cycle,
      and no leftover creatures or orbs (check `Workspace.HollowboundCreatures` and
      `HollowboundWorldRelics`).

### G6. Camp protection and boundary abuse
- [ ] Standing just inside the test camp edge, Player1 cannot attack a Thornback right
      outside (`You cannot attack from inside town or a camp.`).
- [ ] Lure a Thornback to the camp, step in and out repeatedly, hitting it from outside:
      when it loses you it returns to its den and heals to full (its health bar refills).
- [ ] No creature walks into the camp or the town, even when chasing.

### G7. Relic regression during combat
- [ ] Windhook (activated) and Echo Lens work while exploring and fighting, and are
      refused while downed. Using one interrupts a bandage.
- [ ] Equip, unequip, appraisal, activation, registration, and service behave as in Part B.
      Registration and camps never refill charges.
- [ ] Final death: unregistered relics drop with the same ID; registered ones stay with
      **NEEDS SERVICE**, as in milestone 2. Registered relics still save and rejoin
      correctly (Part C on a published test experience).

### G8. Controls and HUD
- [ ] Keyboard and mouse: click and **F** attack (a click on a HUD button never attacks),
      **H** heals.
- [ ] Touch (**Test**, then **Device**, then a phone): the **Attack** and **Heal** buttons
      work; the Heal button reads **Rescue kit** while downed. The Revive prompt is
      tappable. Text stays readable at phone size.
- [ ] Controller (if connected): **R2** attacks, **Y** heals or rescues, and the prompt
      button revives. The button hints switch to controller names.
- [ ] Normal player UI shows no ids, tokens, or debug text (those stay in server Output).

## Part H. Checks only you can run (devices and cloud)

These were **not** run by the assistant:
- Real phone and tablet (Roblox app) and a real controller or console: input, layout,
  and readability.
- A published test experience with several real accounts: latency effects on melee range
  and telegraph dodging, revive across real network latency, server physics ownership of
  creatures, and saving and rejoining (Part C) with milestone 4 active.
- Performance with the creature budget full (12) and several players.

---

# Milestone 5: the vertical world (in progress, not owner-tested)

## Part I. Automated checks (no Studio needed)

- [ ] `lune run tools/run-tests`: `World: N/N passed` plus every earlier suite, and
      `Self-test finished: N/N passed`.
- [ ] `lune run tools/build-world`: `problems 0`, the key-marker coordinates print, and it
      writes `build/HollowboundWorld.rbxm`.

| Requirement | Covered by |
|---|---|
| Required markers exactly once (spawn, terminal, service, supply, guardian and cache, relic spawns A-E) | Validate (World suite) |
| Route connects gate, camp, ruins, and floor; no walkway steeper than 35 degrees; nothing near the kill plane | Validate |
| 3D zones: shaft, under the terminal, under and above the camp are not protected; behind lodges is town; the gate landing starts an expedition | Validate, World |
| Decor and background never collide or block raycasts (drops cannot land on scenery) | Validate |
| Dens farther than their leash from camps | Validate |
| Kill plane below the floor and above FallenPartsDestroyHeight | Validate |
| Reinstalling twice: no duplicates; AuthoredDecor and unrelated models kept; one world model | World (isolated workspace) |
| Lighting preset applied once; original Lighting and Atmosphere restored | World (Lune only) |
| Fixture selection: vertical binds only the world's markers, legacy only the others | World |
| Reach: same level and distance; below a terminal is refused | World |
| Falls: jumps and short drops are free; a rim-to-floor jump downs | World |
| Pure rotations match CFrame.fromOrientation | World |

Not automatable here: Roblox physics, pathfinding on the real geometry, streaming, the
camera, the look of the world, and real saving.

## Part J. Install, reinstall, and save (Studio, edit mode)

1. [ ] Open a **copy** of your place (or a new Baseplate place). Connect Rojo. Stay in edit
       mode.
2. [ ] In the Command Bar, run the install line from README "World installation". Output:
       `World installed: 1187 parts in 36 groups, camp depth 236, 0 plan problem(s), 0
       shaft blocker(s)`, then `Install OK`.
3. [ ] In edit mode, `Workspace.HollowboundWorld` is visible from the camera: the town ring
       around the opening, the shaft, and the floor below.
4. [ ] Put a part inside `HollowboundWorld.AuthoredDecor` (for example a statue at the plaza).
       Run the install line again. Output reports `1 authored item(s) kept`. The statue is
       still there. The Explorer shows exactly one `TownSpawn`, one `RegistryTerminal`, and
       three creature-spawn markers.
5. [ ] Lighting: `Lighting.HollowboundLightingBackup` exists once (even after two installs).
       Run `.restoreLighting()`: the old Lighting returns. Run `.install()` again to
       re-apply.
6. [ ] **Save the place** and reopen it: the world is still there in edit mode.
7. [ ] Optional: delete the Baseplate's `SpawnLocation`, or leave it. Players still spawn at
       the rim plaza.

## Part K. Solo acceptance playtest (about 20 minutes)

Play with **1 player**. Server Output shows `World mode: Vertical (installed m5-1)` and
`Milestone 5 server ready (world: Vertical, ...)`. No legacy dev map or arena appears.

1. [ ] You spawn on the **rim plaza** in town. The HUD place line reads `Rim Town`.
2. [ ] Take supplies at the **Supply Depot**. At the **Registry Hall** terminal, the menu's
       Appraise and Activate are available. Walk around the ring: lodges, towers, lanterns,
       the crane, and the gate.
3. [ ] Visit an **overlook**: you can see the town around the opening, the Elder Tree's
       canopy, the waterfalls, and the floor far below.
4. [ ] Walk through the **Descent Gate** onto its landing: the expedition starts and the
       place line changes to the shaft and depth (for example `The Descent Gate`, then
       `Upper Shaft · 10 m down`).
5. [ ] Descend **without Windhook**: Gatestair ramps, the Overhang Shelf, the bridge head, the
       Root Bridge, and the Elder Tree spiral to 236 deep. Cross to **Mistfall Camp**. The
       label says camp and you take no creature or combat damage there. Relics stay
       unsecured.
6. [ ] Optional branch: the **Lantern Ruins** ledge (relics A, B).
7. [ ] From camp, take the east ramps and the **scaffold stairs** to the floor. Nowhere do you
       get stuck, need to jump a gap, or take fall damage.
8. [ ] On the floor, the **Thornbacks** (furry, thorny) patrol their range. The **Rootwarden**
       (stone construct with a glowing eye) guards the cache by the wall. Fight it using its
       long recovery after each strike. The cache unlocks and the reward relic (engraved
       stone, floating pieces, soft glow) appears. Pick it up.
9. [ ] Echo Lens (if you have one) marks the reward and the floor relics. Windhook (if
       activated) reaches the **sky ledge** (relic E). Without Windhook, you cannot jump up.
10. [ ] **Ascend** with the relic: back up the scaffold stairs, the ramps, the camp bridge, the
        spiral, the Root Bridge, and the Gatestair. Looking up at town from below does **not**
        end the expedition. Stepping back onto the paved rim does (`Back in town...`).
11. [ ] Register the relic at the terminal. The pack shows **REGISTERED**.
12. [ ] Falls: drop off a short ledge (no damage). Jump from the rim into the shaft: you land
        on the floor **downed**. A self-rescue kit or bleedout works as in milestone 4. Fall
        into **the Lower Dark** pit: final death, with drops at your last safe ground (not in
        the pit).
13. [ ] Reach: stand on the ramp directly below the Registry terminal (through the rim
        floor): no terminal, service, or desk use (`You need to be on the same level.`).
14. [ ] Camera: zoom out far enough to see the next landing. The camera moves in front of
        walls in tight spots and never swings on its own during combat.

## Part L. Two-client checks

Start **2 Players** in the vertical world.

- [ ] Both spawn on the rim plaza. Services and creatures appear once (one terminal, two
      Thornbacks, one Rootwarden).
- [ ] Downed and revive on a ramp and on the Elder Tree walkway: the revive works, and creatures
      do not follow into Mistfall Camp.
- [ ] Final death on the floor: relics and a supplies crate drop on the floor (not in the
      pit, not on canopies). The other player recovers them.
- [ ] Contested guardian reward: one winner (as in milestone 4).
- [ ] Charges, cooldowns, protected-relic service, and registration all work as before.
- [ ] Streaming (if enabled): one player stays in town while the other goes to the floor and
      back. Prompts, relic glow, creature models, and Echo marks appear and disappear
      cleanly, with no duplicate prompts.
- [ ] Regression: run milestones 1-4 Parts B and G quickly in the vertical world, then set
      `Config.World.Mode = "Legacy"` and run Part F once to confirm the legacy fixtures
      still work.

## Part M. Only you can run these

These were **not** run by the assistant:
- Real persistence with milestone 5 active (Part C on a published test experience).
- Real phones, tablets, and controllers: readability, touch reach, and frame rate in the
  shaft. Emulation in Studio is not a performance test.
- Performance on the full world (about 1,200 parts and 16 lights) on low-end devices, with
  and without streaming.
