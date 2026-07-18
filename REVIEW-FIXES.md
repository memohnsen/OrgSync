# Review Fixes — Step-by-Step Plan

Fixes from the 2026-07-18 four-agent codebase review, in priority order.
Each step is committed separately; checkboxes flip to `[x]` as steps complete.

## Step 1 — [x] Fix: `pull` silently discards local deletions (file resurrection)
`SyncWorker.swift` `applyRemote`/pull logic: in the (remote exists, local deleted)
case with an unchanged remote, keep the deletion tracked (`newFiles[path] = baseSHA`)
so `localChanges` still reports it and the delete gets pushed. Preserve `skippedPaths`
entries across pulls. Add regression test in `SyncTests.swift`.

## Step 2 — [x] Fix: post-push `rebase` loses edits made during the push
`SyncWorker.commitAndPush`: build the new baseline from the blob SHAs actually
uploaded (as `pushPending` does with `pendingCommit.changes`) instead of re-scanning
the disk after the push. Files edited or created mid-push must remain visible as
local changes. Add regression test.

## Step 3 — [x] Fix: pending-commit deadlock after remote moves
Add a "discard pending commit" path in `SyncWorker`/`SyncEngine` and surface it in
the Git command palette so a non-fast-forward pending commit is recoverable without
disconnecting. Add test.

## Step 4 — [x] Wire up ConflictResolutionView
It exists but is unreachable. Link it from the Git command palette and show a
"Resolve Conflicts" affordance in the Notes browser when `sync.conflictCopies()`
is non-empty.

## Step 5 — [ ] Fix: NoteDetailView overwrites background pulls with stale content
Reload the open document when `repo.revision` changes (unless there are unsaved
local edits, in which case prefer the in-memory buffer only if the disk content
still matches what was loaded).

## Step 6 — [ ] Fix: Reminders sync crash + deleted-TODO resurrection
`RemindersSyncEngine`: replace `Dictionary(uniqueKeysWithValues:)` with
`Dictionary(_:uniquingKeysWith:)`; when a mapped org TODO no longer exists, prune
the mapping (and remove the reminder) instead of re-creating the todo in inbox.org.
Add tests.

## Step 7 — [ ] UX: confirm before destructive delete
FolderView swipe-delete: confirmation dialog before deleting folders and non-empty
notes (permanent, unpushed edits unrecoverable).

## Step 8 — [ ] Security: Keychain accessibility class
`KeychainHelper`: set `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on add
and update; migrate existing items on write.

## Step 9 — [ ] Cleanup: reminders/agenda rule duplication
Point AgendaView's done-keyword / relevant-date / reschedule logic at
`ReminderSyncRules` so the rules live in one place.
