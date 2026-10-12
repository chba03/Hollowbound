# Manual test checklist (two Studio clients)

Sections 1-6 cover milestone 1 (pickup and registration) and still apply. Sections 7-13
cover milestone 2 (final death, recovery, and service). Run 1-6 first as a regression
check. The pack should now also show a `Good condition` line on each relic.

## Setup
1. Run `rojo serve` and connect the Rojo plugin (see README).
2. In Studio, open the **Test** tab. In the **Clients and Servers** section, set the
   dropdown to **2 Players**, then click **Start**. Studio opens three windows: a Server
   and two Clients (Player1, Player2).
3. In the **Server** window's Output, confirm:
   - [ ] `Self-test finished: N/N passed` with no `FAIL` lines
   - [ ] `Built development placeholder map at X=200.`
   - [ ] Two `Generated ...` lines with **different IDs and different trait values**
         (for example, the first Common or Uncommon and the second Rare or Exceptional)
   - [ ] `Built development service station next to the registration terminal.`
   - [ ] `Milestone 2 server ready.`
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
      (the wooden bench beside the terminal). Message: `None of your relics need service.`
- [ ] Player1 uses the bench. Message: `Serviced: Windhook (...)`. A now shows
      `Good condition`, and is still **REGISTERED**, `Unappraised · Needs activation`, with the
      same ID.
- [ ] Server Output: `serviced <A id>|<same traits>|registered=true|appraised=false|activated=false`.
- [ ] Use the bench again: `None of your relics need service.` The pack still holds one A.
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
