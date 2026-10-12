# Milestone 1: manual test checklist (two Studio clients)

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
   - [ ] `Milestone 1 server ready.`
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
