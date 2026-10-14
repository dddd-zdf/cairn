# Reverse deletes (Immich trash → iPhone): what's untested

Branch `reverse-deletes` on the fork (dddd-zdf/cairn). Written on Windows
with no Mac, so nothing here has run on a device or simulator.

## What was checked

- `swift build` + `swift test` on the fork's GitHub Actions (macOS runner,
  `.github/workflows/fork-ci.yml`). Covers the matcher rules, the size
  limit, the orchestrator + journal, the client request shape, and the
  settings default.
- Unsigned iOS Simulator build of the app target in the same workflow.
  Proves it compiles, nothing more.
- Request shape against the Immich OpenAPI spec (3.3.0-rc): flat
  `trashedAfter` / `withDeleted` / `visibility` are deprecated since 3.2
  but present. Difei confirmed earlier they still work on Immich 3.3.1.

## Not tested at all

- `PhotoKitLocalAssetDeleter`: the real `performChanges` delete, the iOS
  confirmation prompt, the cancel path (`PHPhotosError.userCancelled`),
  Recently Deleted behavior.
- The review sheet UI (layout, dark mode, Dynamic Type, VoiceOver).
- Thumbnails of trashed assets (`ImmichAssetThumb` with a trashed asset
  id). Expected to work for the owner; not verified.
- What happens on the next sync after a phone delete (the forward
  pipeline should confirm the checksums and do nothing because the
  server assets are trashed).
- Limited Photos access.

## On a real iPhone (free Apple ID is enough)

Build: `cd iOS && make install && make generate`, open in Xcode, set your
own team under Signing (free personal team), change the bundle id if it
clashes, run on the phone. Use a test Immich account or a few throwaway
photos.

1. Settings → Recovery: toggle is off by default; "Review Immich trash"
   row only appears when on.
2. Take 3 new photos, let Immich upload them, run a cairn sync so they're
   hashed. Trash 2 on the Immich web. Review Immich trash (last day):
   both listed with thumbnails; "Delete 2 from iPhone" → cairn dialog →
   iOS prompt → both in Recently Deleted, list empties.
3. Repeat, but tap "Don't Allow" at the iOS prompt: list stays, journal
   tail shows `phone.fail` "Cancelled at the system prompt".
4. Live Photo: trash it on the web (only the still is trashed). It
   should be listed and deleted as one item.
5. Edited photo: edit on the phone, let Immich upload the edit. Trash
   only the edited version on the web → not listed ("edited, original
   still on Immich"). Trash the original too → listed.
6. Recovered photo: delete a photo on the phone, let cairn trash it on
   Immich, recover it from Recently Deleted. It must not be listed
   ("recovered after cairn trashed them").
7. Keep all → items added to Settings → Excluded and not offered again.
8. Size limit: hard to reach on a big library; on a small test library
   (under 250 photos), trashing 26+ should show the red callout and
   disable Delete.
9. Next sync after a delete: no errors, no new trash candidates, Runs tab
   unchanged; Status journal tail shows `phone.plan` / `phone.delete`.
10. Shared Library photos are never listed (only `.typeUserLibrary`).

## Known gaps / follow-ups

- An edit that never reached Immich can't match (its current SHA1 isn't
  on the server). Deliberately conservative.
- Duplicate photos on the phone sharing one checksum are both listed.
- Manual only. A Status banner with the count, or a check during sync,
  would be the next step.
- When Immich drops the flat search fields, switch to `filter.trashedAt`
  + cursor paging (3.2+ only).
- `fork-ci.yml` is fork-only; drop it before proposing upstream. Upstream
  CONTRIBUTING asks for an issue first for features.
