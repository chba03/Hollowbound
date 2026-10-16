# Third-party code

## ProfileStore (MadStudioRoblox / loleris)

| | |
|---|---|
| Purpose | Session-locked DataStore saving for registered relics (milestone 3) |
| Upstream | <https://github.com/MadStudioRoblox/ProfileStore> |
| Docs | <https://madstudioroblox.github.io/ProfileStore/> |
| Pinned commit | `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31, "Merge pull request #14") |
| Package version at that commit | `lm-loleris/profilestore` 1.0.3 (from upstream `wally.toml`) |
| Vendored file | [`src/server/Vendor/ProfileStore.luau`](../src/server/Vendor/ProfileStore.luau), byte-for-byte unmodified |
| SHA-256 | `ad43737203688b8e88cab34ebe8c483000c157e53bfb41e35f1b49ee89d0c95f` |
| License | Apache License 2.0, copied to [`licenses/ProfileStore-LICENSE.txt`](../licenses/ProfileStore-LICENSE.txt) |
| Verified | 2026-10-15 against the upstream repository and `docs/api.md` at the pinned commit |

The file is vendored, not installed through Wally, because this project uses only Rojo.
Its upstream header comment is kept intact.

### How this project uses it

Only [`ProfileBackend.luau`](../src/server/ProfileBackend.luau) requires ProfileStore.
Everything else talks to the adapter interface documented at the top of that file.

- One profile per player: store `Config.Persistence.StoreName`, key
  `Config.Persistence.KeyPrefix .. UserId`, started with `StartSessionAsync` (session
  locked). `AddUserId` is called for GDPR association.
- `Profile:Reconcile()` fills fields missing from older saves. Schema versions newer
  than the server's are refused and never overwritten.
- `OnAfterSave(last_saved_data)` confirms saves. The project's `Revision` counter
  makes confirmation monotonic.
- `OnLastSave("Shutdown" | "External")` writes the latest state before the final save.
- `OnSessionEnd` without our own `EndSession` means the session was lost. Mutations stop
  and the player is kicked.
- `ProfileStore.DataStoreState` is checked before any session starts. Upstream silently
  uses an internal mock when DataStores are inaccessible. This project never allows
  that unnoticed: it uses `ProfileStore.Mock` on purpose (Studio only, labelled MOCK), or
  it refuses to load.

### Upstream behaviours to keep in mind

- Autosave period: 300 s (`AUTO_SAVE_PERIOD`). Session steal after about 40 s of
  conflict (`SESSION_STEAL`). A crashed server's lock is assumed dead after 630 s
  (`ASSUME_DEAD`).
- If a key holds data that is not a ProfileStore profile, upstream replaces it with an
  empty profile and fires `OnOverwrite`. This project logs that, but cannot prevent it.
  Use a dedicated store name.

### Updating

1. Read the upstream changelog and commits since the pinned commit.
2. Replace the vendored file with the new revision's `ProfileStore.luau`, unmodified.
3. Update the commit, version, date, and SHA-256 above, and the license copy if it changed.
4. Re-run the mock tests and the real persistence checks in `docs/TESTING.md`.
