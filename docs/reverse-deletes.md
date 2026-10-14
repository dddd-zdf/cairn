# Reverse deletes (Immich trash → iPhone), fork feature

Fork-only feature on `dddd-zdf/cairn`, branch `reverse-deletes`. Opt-in,
off by default. Photos moved to Immich's trash (for example, deleted on
the web) can be removed from the iPhone after review.

Kept as separate from upstream cairn as practical, so it can be carried
forward on top of new upstream releases without merge pain.

## Where it lives

```
Sources/CairnCore/ReverseDelete/      pure logic + tests (platform-neutral)
  ServerTrashMatcher.swift            matching rules, size limit, LocalAssetDeleter protocol
  ServerTrashReview.swift             scan result for the sheet
  ServerTrashCheckPolicy.swift        once-a-day check, weekly reminder timing
  LocalDeleteOrchestrator.swift       limit re-check → journal → delete
  LocalDeleteJournal.swift            own JSONL file: phone-delete-journal.jsonl
  PhoneDeleteRun.swift                journal rows → one summary per run, for Runs
  ImmichClient+TrashedAssets.swift    search/metadata with trashedAfter
Sources/CairnIOSCore/ReverseDelete/   iOS side
  ReverseDeleteController.swift       settings (UserDefaults, cairn.reverseDelete.*), state, reminder
  ReverseDeleteViews.swift            Settings rows, Status line, sheet modifier
  ServerTrashReviewSheet.swift        review screen
  PhotoKitLocalAssetDeleter.swift     PHAssetChangeRequest.deleteAssets
  ServerTrashReminderScheduler.swift  weekly local notification
  ReverseDeleteNotificationRouter.swift  notification tap → review sheet
  PhoneDeleteRuns.swift               merges phone-delete runs into the Runs tab
iOS/App/AppDependencies+ReverseDelete.swift   wiring to cairn's stores and client
Tests/CairnCoreTests/ReverseDelete/   tests
```

## Hooks in upstream files

Every touch of an upstream file is a line marked `// fork: reverse deletes`
(find them with `git grep "fork: reverse deletes"`), except the first:

| File | Change |
|---|---|
| `Sources/CairnCore/ImmichClient.swift` | `postJSON` changed from `private` to internal, so the extension can reuse it |
| `Sources/CairnIOSCore/UI/CairnAppRoot.swift` | `.reverseDeleteSheet(palette:)` after the main `.sheet` |
| `Sources/CairnIOSCore/UI/SettingsScreen.swift` | `ReverseDeleteSettingsRows()` in the Recovery card |
| `Sources/CairnIOSCore/UI/StatusScreen.swift` | `ReverseDeleteStatusLine()` under "Last checked" |
| `Sources/CairnIOSCore/UI/RunsScreen.swift` | phone-delete label, count and icon in the run row |
| `Sources/CairnIOSCore/UI/RunDetailSheet.swift` | phone-delete kind and title, no Restore, no breadcrumb card |
| `iOS/App/AppDependencies.swift` | `configureReverseDelete()` in `bootstrap()`; `syncDidFinish()` after a successful sync; `mergePhoneDeleteRuns()` at the end of `refreshRunsList()` |
| `iOS/App/CairnApp.swift` | `ReverseDeleteNotificationRouter.install()` in `init` |

Not part of the feature: `MissedDeletionsSheet.swift` delete-button
colour fix (same unreadable red-on-red as the first version of the
review sheet). Worth offering upstream on its own.

## Updating from upstream

```sh
git fetch upstream
git rebase upstream/main        # on branch reverse-deletes
git grep -n "fork: reverse deletes"   # check every hook still sits in the right place
```

Conflicts can only be in the eight files above. If upstream renamed or
moved the surrounding code, re-add the one line in the equivalent spot.
Then push and let `.github/workflows/fork-ci.yml` run the tests, build
the app, and produce a fresh unsigned `.ipa` for SideStore.

Things to watch in upstream changes:
- `ImmichClient.postJSON` or `SearchResponseDTO` / `AssetItemDTO` changing shape.
- `LocalHashStore`, `EditRetirementStore`, `ObservedStore`,
  `ExclusionStore`, `JournalReader.recentlyTrashedChecksums` APIs (read
  by `AppDependencies+ReverseDelete.swift`).
- Upstream adding its own notifications: iOS allows one notification
  delegate. Route both through one delegate instead of installing two.
- Immich dropping the flat `trashedAfter` / `withDeleted` / `visibility`
  search fields (deprecated since 3.2): switch to `filter.trashedAt` and
  cursor paging.

## How it behaves

- **Check.** After every successful sync (foreground, background,
  Shortcut), at most about once a day, if the setting is on: list
  Immich assets trashed in the last 30 days (Immich's default trash
  retention), match them to phone assets, store the count. Never
  prompts. One small request to Immich; matching uses cached hashes.
- **Status.** "N to delete on iPhone ›" under "Last checked" when N > 0.
- **Reminder.** One pending local notification at the chosen weekday and
  time (default Sunday 10:00), rewritten by each check while N > 0 and
  removed when N = 0. Booked ahead, so iOS delivers it on time even if
  cairn gets no background time that week. Tapping opens the review.
- **Review.** Opens with a fresh 30-day scan. Skip, Keep (adds to
  cairn's exclusion list), or Delete. Delete re-checks the size limit,
  journals, and makes one PhotoKit request; iOS shows its own prompt and
  items go to Recently Deleted.

## Matching rules

A live user-library phone asset is a candidate when one of its *current*
`LocalHashStore` checksums equals the checksum of a trashed Immich
primary (`timeline` or `archive`). Skipped, in order:

1. Any checksum cairn itself trashed (user recovered it on the phone).
2. Excluded (current or first-observed checksum).
3. Matched checksum not in this account's scope-filtered `ObservedStore`.
4. Imputed (server-trusted) cache entry, not yet hashed on the phone.
5. Edited since first observed, and none of the retired first-observed
   checksums is trashed: only the edit was deleted on Immich; the phone
   copy still holds the original.

Live Photos match on the still; Immich's web delete doesn't cascade to
the motion video, so it isn't needed. Trashing only the pre-edit
original on the web never matches (current bytes differ). An edit that
never reached Immich can't match.

**Size limit.** Refuse when the live library is empty, or when the batch
is over 25 and over 10% of live user-library assets.

**Feedback loop.** The PhotoKit delete fires `deletedLocalIdentifiers`,
so cairn's forward pipeline confirms those checksums. Harmless: the
engine drops `isTrashed` server assets from candidates. If the asset is
later restored on Immich, the forward direction proposes trashing it
again, same as any phone deletion.

## Trade-offs of keeping it separate

- Its settings live in UserDefaults, not `CairnSettings`, so they aren't
  in cairn's export/import and don't reset with "Reset index".
- Its journal is a separate file, so phone deletes don't appear in the
  Status journal tail. They do appear in the Runs tab: `PhoneDeleteRuns`
  merges them into the view model (run ids start with `phone-`), with no
  Restore button since the photos are in the iPhone's Recently Deleted,
  not Immich's trash.
- The controller is a shared singleton and the sheet has its own
  presenter, instead of cairn's `CairnAppModel` / `PresentedSheet`
  pattern.

If upstream ever wants the feature, folding it into those native
patterns is a contained refactor: the Core logic and tests carry over
unchanged.
