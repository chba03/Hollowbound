# Test checklist

This file has four kinds of tests. Keep them apart when you report results:

| Part | What | Storage | Where |
|---|---|---|---|
| Sections 1-15 | Milestone 1-2 regression: pickup, registration, death, recovery, service | Studio mock (purple badge) or real | Studio, 2 clients |
| Part A | Automated tests (Store, Abilities, Persistence) | **Test-only MockBackend**, never DataStores | Studio server Output |
| Part B | Milestone 3 two-client checks: appraisal, activation, loadout, abilities, controls | Studio mock or real | Studio, 2 clients |
| Part C | **Real persistence**: rejoin, restart, competing sessions | **Real DataStores** in a separate test experience | Published test experience |
| Part D | Short beginner playtest script | any | Studio |

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
   - [ ] `Milestone 3 server ready (storage: ...)`
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
