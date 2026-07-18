# OrgSync — Implementation Plan

An iOS notes app for `.org` files that is also a git client, syncing with the user's
org repo on GitHub. Classic, minimalist, native iOS design (SwiftUI, system fonts,
system colors, standard navigation).

## Architecture decisions

- **SwiftUI**, iOS 26 deployment target, existing `OrgSync` app target.
- **Git sync via the GitHub REST API** (Git Data API: blobs/trees/commits/refs) rather
  than bundling libgit2 — full clone/pull/push/commit semantics, pure Swift, no binary
  dependencies. Auth via a user-supplied fine-grained Personal Access Token stored in
  the Keychain (user pastes it in Settings; the app never sees GitHub passwords).
- **Local repo mirror** lives in the app's Documents directory; all edits are local-first
  and sync is explicit (pull-to-refresh / sync button) plus optional auto-sync.
- **App Group** (`group.com.memohnsen.OrgSync`) shares favorites + agenda snapshot data
  with the widget extension.
- **Org parsing** is a hand-written parser in a shared `OrgKit` folder used by app and
  widgets.
- The Xcode project uses file-system-synchronized groups: adding `.swift` files under
  `OrgSync/` automatically adds them to the app target. Only the widget extension
  phase edits `project.pbxproj`.

## Phases

### Phase 1 — Foundation & app shell — [x] COMPLETE
- Tab-based shell: **Notes**, **Agenda**, **Settings** (native `TabView`).
- `RepoStore`: manages the local repo directory (Documents/repo), file listing,
  create/rename/delete `.org` files, folder hierarchy.
- Notes tab: file browser (folders + org files) with native list styling, swipe
  actions, favorites (star), search by filename.
- Settings tab skeleton: repo URL field, token field (Keychain-backed), placeholder
  toggles for auto-sync and Reminders sync.
- Sample org files seeded on first launch so the app is usable before sync is set up.

### Phase 2 — OrgKit: parser & document model — [x] COMPLETE
- Full org syntax data model + parser: headlines (stars, TODO/DONE + custom keywords,
  priority `[#A]`, tags `:tag:`), SCHEDULED/DEADLINE/plain/inactive timestamps with
  repeaters, PROPERTIES drawers, plain/ordered/checkbox lists `[ ]`/`[X]`/`[-]`,
  tables, `#+BEGIN_SRC`/`QUOTE`/`EXAMPLE` blocks, `#+TITLE:`-style keywords, comments,
  horizontal rules, links `[[url][desc]]`, inline emphasis (bold/italic/underline/
  verbatim/code/strikethrough), footnotes.
- Serializer: model → text round-trips losslessly.
- Mutation helpers: toggle TODO state, cycle checkbox, set priority, add/remove tags,
  reschedule.
- Unit tests in OrgSyncTests covering parse + round-trip.

### Phase 3 — Note viewing & editing — [x] COMPLETE
- Note view: rendered org document — styled headlines by level, folding
  (tap headline to collapse subtree), checkboxes tappable, tables, code blocks,
  clickable links, timestamps rendered as native-styled pills.
- Edit mode: plain-text editor with org syntax highlighting (AttributedString),
  a formatting accessory bar (headline level, TODO state, checkbox, bold/italic,
  timestamp insert, link insert), autosave.
- TODO quick actions from the rendered view (toggle state, change priority).

### Phase 4 — GitHub sync (the git client) — [ ] PENDING
- `GitHubClient`: Git Data API (get ref, trees, blobs, create blob/tree/commit,
  update ref) + repo metadata; PAT auth from Keychain.
- `SyncEngine`: initial clone (fetch full tree → Documents/repo), pull (three-way
  diff base/local/remote with per-file merge, conflict copies on true conflicts),
  push (build tree from local changes → commit → update ref), sync status tracking
  (`.orgsync/state.json` with base commit SHA + per-file blob SHAs).
- Sync UI: sync button + pull-to-refresh in Notes, per-run status (ahead/behind,
  last synced, error surfaced natively), commit log view, initial repo
  connect flow in Settings (validate repo, choose branch, first clone).
- Auto-sync options in Settings: **auto-pull on app open** and **auto-commit &
  push on app close** (scene background), each independently toggleable.

### Phase 5 — Agenda — [ ] PENDING
- Agenda tab: aggregates TODO headlines across every org file in the repo.
- Views: **Today** (scheduled/deadline today + overdue), **Upcoming** (next 7 days),
  **All TODOs** grouped by file; native list sections, deadline/overdue coloring,
  priority badges, tag chips.
- Actions: complete (writes DONE + CLOSED timestamp back to file, honors repeaters),
  reschedule via date picker, jump to note.
- Agenda snapshot written to the App Group container for the widget.

### Phase 6 — Widgets — [ ] PENDING
- New `OrgSyncWidgets` WidgetKit extension target (this phase edits project.pbxproj)
  with App Group entitlement on both targets.
- **Favorites widget**: small/medium — favorited notes, tap deep-links into the note.
- **Upcoming TODOs widget**: small/medium/large — next scheduled/deadline items with
  date coloring, deep-links to Agenda.
- Deep-link URL scheme (`orgsync://note/...`, `orgsync://agenda`) handled in the app.

### Phase 7 — Reminders two-way sync — [ ] PENDING
- EventKit integration with permission flow; dedicated "OrgSync" Reminders list
  (user-choosable in Settings).
- Org → Reminders: TODOs with SCHEDULED/DEADLINE become reminders (due date,
  priority, notes carry file + heading path); DONE completes the reminder.
- Reminders → Org: completing a reminder marks the org heading DONE; reminders
  created in the list become TODOs in an inbox.org; due-date edits write back.
- Mapping store (org heading ID ↔ reminder ID) in the App Group container;
  sync runs on app foreground + after git sync; toggle + list picker in Settings.

### Phase 8 — Polish & verification — [ ] PENDING
- Full-text search across notes; sort options; recent notes.
- Settings completion: TODO keyword customization, agenda span, appearance check
  (dark mode), about screen.
- Empty states, error states, accessibility labels (Dynamic Type, VoiceOver).
- Build + full test pass; fix warnings; final end-to-end review.

## Working notes for agents

- Build check: `xcodebuild -project OrgSync.xcodeproj -scheme OrgSync -destination 'generic/platform=iOS Simulator' build`
- Tests: same with `test` and a concrete simulator destination.
- Keep design native and minimal: system materials, SF Symbols, standard list styles,
  no custom chrome unless org semantics require it.
- Agents do not commit; the session owner commits once after each phase completes.
