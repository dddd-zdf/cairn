# Reverse deletes: what's tested, what isn't

Design and maintenance: `docs/reverse-deletes.md`.

## Checked in CI (`.github/workflows/fork-ci.yml`)

- New suites run without crash tolerance: matcher rules, size limit,
  orchestrator + its journal, client request shape, check/reminder
  timing.
- The full upstream `swift test` run crashes with signal 5 before tests
  report, on unmodified `main` too. ci.yml's tolerance hides it.
  Pre-existing.
- Unsigned simulator build and an unsigned device `.ipa` (macos-26,
  Swift 6.3). On macos-15 / Swift 6.2 the app fails on existing code
  (`AppDependencies.swift:126`), unrelated.

## Checked on Difei's iPhone (SideStore build, first version)

- Manual review → Delete → iOS prompt → Recently Deleted works.
- Delete button text was unreadable; fixed.

## Not yet checked on the phone

1. Settings → Data & recovery: toggle off by default; turning it on asks
   for notification permission once; reminder day/time and "Review
   Immich trash" rows appear.
2. After the next sync, Status shows "N to delete on iPhone ›" when
   something is waiting; nothing when not.
3. Reminder: set it a few minutes ahead, trash a photo on the web, run
   a sync (pull Sync once). The notification arrives at that time;
   tapping opens the review with a fresh scan. With nothing waiting, no
   notification.
4. Cold launch from the notification (app killed) still opens the
   review after a moment.
5. Cancel at the iOS prompt: list stays.
6. Live Photo, edited photo, recovered-after-cairn-trash, Keep all, and
   Shared Library cases as in `docs/reverse-deletes.md` matching rules.
7. Background-only: leave the app closed for a few days; the check
   should still run on background syncs (watch "N waiting" in Settings).
