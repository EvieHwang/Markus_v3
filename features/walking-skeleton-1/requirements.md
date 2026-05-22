# Requirements: walking-skeleton-1

*Walking skeleton — first feature. Requirements deliberately thin; depth lives in later Roadmap items.*

## User stories

### US-1 — First launch lands at the document browser
**As** a first-time user
**I want** to see the iOS system document browser immediately when I launch the app
**So that** I can pick a markdown file without going through any onboarding, splash, or library screen

**Acceptance criteria:**
- AC-1.1: On first launch (no prior state), the app's first visible UI is the system document browser (UIDocumentBrowserViewController or equivalent).
- AC-1.2: No splash screen, onboarding flow, account prompt, or library screen is presented before the document browser.
- AC-1.3: The document browser is configured to filter to `.md` and `.markdown` content types only; other file types are visible but greyed/non-selectable per system behavior.

### US-2 — Open a markdown file and see it rendered
**As** a user with a `.md` file in iCloud Drive (or any file-system location)
**I want** to pick that file from the document browser and see it rendered as formatted markdown
**So that** I can read it without first having to enter an editor

**Acceptance criteria:**
- AC-2.1: Selecting a `.md` or `.markdown` file in the document browser opens the document view with the file rendered as GitHub Flavored Markdown (CommonMark + tables + task lists + strikethrough + autolinks).
- AC-2.2: Rendered mode is the default mode when a file is opened.
- AC-2.3: The navigation bar shows the filename without its extension.
- AC-2.4: The file is read from its original location via security-scoped access; no copy is created in the app's container.
- AC-2.5: A file with zero bytes opens successfully and shows an empty rendered view.

### US-3 — Tap to edit
**As** a user reading a rendered document
**I want** to tap the document to switch into raw editing mode
**So that** I can edit the source without navigating through menus

**Acceptance criteria:**
- AC-3.1: A single tap anywhere on the rendered document area switches the view to raw mode showing the markdown source as plain text.
- AC-3.2: In raw mode, the navigation bar shows an eye-icon toolbar item that returns to rendered mode.
- AC-3.3: Tapping a link in rendered mode also switches to raw mode (does not follow the link). Long-press link handling is **deferred** (see Out of scope).
- AC-3.4: After switching to raw mode, the user must tap once more in the text to place the cursor (tap-to-edit is a mode switch, not a cursor-placement gesture).

### US-4 — Edit and save back to the original location
**As** a user in raw mode
**I want** to edit the markdown source and have my edits saved back to the original file
**So that** my changes persist where the file already lives, with no app-managed copy

**Acceptance criteria:**
- AC-4.1: The raw editor is a plain-text editing surface (UITextView-class) using a monospace system font.
- AC-4.2: Edits update the in-memory document model and mark it dirty.
- AC-4.3: Dirty edits are persisted back to the original file location via security-scoped write — no copy in the app container, no rename, no relocation.
- AC-4.4: Save triggers (at minimum): switching back to rendered mode, leaving the document (back to browser), app entering background, and a typing-pause autosave (after ~500 ms of editor idle following a change).
- AC-4.5: After save, the in-memory dirty flag is cleared.
- AC-4.6: Default `UITextView` behavior is acceptable for the skeleton (autocorrect, smart quotes, etc., are not tuned — see Out of scope).

### US-5 — Return to rendered mode
**As** a user finished editing
**I want** to tap the eye icon to return to rendered mode
**So that** I can confirm my edits look right as formatted output

**Acceptance criteria:**
- AC-5.1: Tapping the eye-icon toolbar item in raw mode switches the view to rendered mode.
- AC-5.2: Returning to rendered mode triggers a save (if dirty) before re-rendering.
- AC-5.3: The rendered view reflects the latest in-memory source (including unsaved edits if save is in flight).
- AC-5.4: Mode is not persisted across document opens — every fresh open starts in rendered mode (skeleton has no resume; resume is Roadmap #2).

### US-6 — Edits persist across a close/reopen cycle
**As** a user who has edited and exited a file
**I want** my edits to be present the next time I open that file
**So that** I trust the app to actually save my work

**Acceptance criteria:**
- AC-6.1: After editing a file, returning to the document browser, and reopening the same file, the rendered view shows the edited content.
- AC-6.2: The file on disk at the original path contains the edited content (verifiable in the iOS Files app or any other markdown-aware app).
- AC-6.3: No additional file has been created in the app's container or elsewhere as a side effect of editing.

## Edge cases and failure modes

### File content
- **EC-1: Empty file.** Opens successfully; rendered view is blank; raw editor shows empty text. Editing and saving an empty file produces a non-empty file on disk if content is added.
- **EC-2: Very large file.** *Addresses adversarial F-004.* Files **≥ 500 KB** open into **raw mode by default** (skipping the rendered-mode default of AC-2.2 for this case only); the user can tap the eye icon to render on demand. Below 500 KB, opens in rendered mode per AC-2.2. Rendering of large files may take a moment but must not freeze the UI for >2 s of unresponsive input; this is enforced by the size threshold, not by async rendering (deferred). The 500 KB threshold is a measured-byte file-size check, not a parsed-content check, so it works before the file is read fully.
- **EC-3: GFM features present.** Tables, task lists (checkboxes, both checked and unchecked), strikethrough, autolinks, fenced code blocks, and ATX/Setext headings all render visibly (need not be pixel-perfect, but must be visually recognizable as their construct).
- **EC-4: Invalid UTF-8 or unusual encoding.** Best-effort decode as UTF-8; if decode fails, surface a non-blocking error and return to the document browser. The skeleton does not attempt encoding detection.
- **EC-5: File with `.markdown` extension.** Treated identically to `.md`.

### Lifecycle
- **EC-6: App backgrounded mid-edit.** *Addresses adversarial F-001.* Pending edits are saved before the app suspends. On return **while the scene is still alive** (short backgrounding, typical case), the document is re-presented in the same mode the user was in when backgrounded. After **scene tear-down** (long backgrounding or OS memory pressure), `@State` is lost and the document re-presents in rendered mode per AC-2.2 / AC-5.4 — this is a known consequence of skeleton-level state handling and is acceptable for this feature. SceneStorage-backed mode restoration is deferred (likely Roadmap #2 alongside last-file resume).
- **EC-7: App killed mid-edit before save fires.** Unsaved edits may be lost. The skeleton makes no autosave guarantee tighter than the AC-4.4 triggers. (Stronger autosave is deferred.)
- **EC-8: Rapid mode switching.** Switching modes repeatedly in quick succession must not crash, deadlock, or corrupt the document. The visible mode is whichever the user landed on last.

### File system
- **EC-9: File deleted externally while open.** Skeleton is not required to detect this proactively. If the next save fails because the file is gone, the save error is surfaced non-fatally (alert per AC-RECOVER-1) and the in-memory content is preserved. The deletion banner with Save As is Roadmap #3.
- **EC-10: File moved externally while open.** Skeleton is not required to follow the move. If the next save fails, behavior is the same as EC-9. Follow-on-move is Roadmap #3.
- **EC-11: File modified externally while open.** Skeleton is not required to detect this. The next save overwrites the external change (last-write-wins). External-change detection and the three-option conflict sheet are Roadmap #3.
- **EC-12: Read-only file or write permission denied.** Save fails; alert surface per AC-RECOVER-1; in-memory content is preserved.
- **EC-13: iCloud download pending.** *Addresses adversarial F-007 (partial).* A file whose contents have not yet downloaded from iCloud must not appear as a blank document. While the download is pending, the document view shows a loading indicator (system progress spinner with the text "Downloading…"). The rendered view appears once contents are available. If the download fails (e.g., user goes offline), surface a non-fatal alert and return to the document browser.

### Save-failure recovery
- **AC-RECOVER-1.** *Addresses adversarial F-002.* When any save fails (EC-9 / EC-10 / EC-12, or a silent `UIDocument` save error surfaced per F-003), the user is shown a non-blocking alert with the following actions: **"Copy contents to clipboard"** (writes the current in-memory `text` to `UIPasteboard.general`) and **"Dismiss"**. The in-memory content remains intact and editable after dismiss. This is the skeleton's minimum recovery surface — full Save As is Roadmap #3.
- **AC-RECOVER-2.** The "Copy contents to clipboard" action must not silently fail. After the copy, the alert is dismissed and a brief confirmation ("Copied") appears (toast or similar).

### Browser interaction
- **EC-14: User cancels file picker.** Returns to whatever previous state the document browser was in; app does not crash.
- **EC-15: User picks a non-`.md`/`.markdown` file via "All Files" or external means.** The browser's type filter (AC-1.3) is the primary defense. If a non-markdown file somehow reaches the open path, it is rejected with a non-fatal error and the browser is re-shown.

## Out of scope

These are explicitly **not** part of walking-skeleton-1. Each maps to a later Roadmap item or to project-level out-of-scope; do not pad the skeleton with them.

- **Last-file resume on launch** — Roadmap #2.
- **External-change detection, follow-on-move, deletion banner, three-option conflict sheet** — Roadmap #3.
- **Scroll-anchor preservation across mode switches** — Roadmap #4. Skeleton may scroll to top or wherever the OS lands it.
- **New file creation** — Roadmap #5. Skeleton opens existing files only.
- **List continuation on Return, smart-quote/dash suppression, autocorrect tuning, `Cmd+/` shortcut, swipe gestures** — Roadmap #6.
- **Long-press link context menu in rendered mode** — Roadmap #6 or later.
- **Find / Share button / overflow menu in the navigation bar** — deferred polish.
- **Fading navigation chrome on scroll in rendered mode** — deferred polish.
- **iPad-specific layout (split view, sidebar, larger-screen affordances)** — deferred.
- **Performance tuning for very large files beyond "does not deadlock"** — deferred.
- **Encoding detection for non-UTF-8 files** — out of scope.
- **Syntax highlighting in code blocks** — out of scope project-wide.

## Standards check

- **Apple HIG (Interface).** The skeleton uses the system document browser and a standard navigation bar; HIG compliance is largely inherited from system controls. No custom chrome competes for it.
- **WCAG 2.1 AA (Accessibility).** A full accessibility pass is deferred to Roadmap #7. The skeleton inherits default UIKit/SwiftUI accessibility for most surfaces, **plus three minimum additions absorbed into this feature** because retrofitting them later is more expensive than adding them now:
  - AC-A11Y-1: The eye-icon toolbar item in raw mode has a VoiceOver label of "Show rendered" (or equivalent).
  - AC-A11Y-2: The rendered document exposes an "Edit" accessibility custom action equivalent to the tap-to-edit gesture, so VoiceOver users can switch to raw mode without simulating a tap.
  - AC-A11Y-3: *Addresses adversarial F-008 (requirements side).* The "Copy contents to clipboard" action (AC-RECOVER-1) posts a VoiceOver announcement ("Copied") in addition to showing the visual toast (AC-RECOVER-2). The announcement and the toast are independent — the announcement must fire for VoiceOver users even when the toast is suppressed or missed.
  Anything beyond these three — heading/list/link semantics in rendered view, Dynamic Type tuning, contrast verification, traits on every element — remains in Roadmap #7.
- **OWASP Top 10 (Security).** Applicability is minimal — no network, no auth, no server. The skeleton must not log file contents or paths to anywhere persistent beyond what iOS itself does.
- **OpenAPI (API contracts).** N/A — no API surface.

## Notes on changes

**Third pass — addresses adversarial F-008 (requirements side).** New change:

- **AC-A11Y-3 added** — the Copy action posts a VoiceOver announcement so blind users get audible confirmation; toast remains for sighted users. Architecture side (the `UIAccessibility.post` call wiring) is picked up by `/t3-architecture`.

**Second-pass changes (retained):**

- **EC-2 tightened** — files ≥ 500 KB open into raw mode by default (addresses F-004). Avoids the "frozen app" UX that "does not deadlock" allowed.
- **EC-6 tightened** — explicitly acknowledges scene tear-down resets mode to rendered (addresses F-001). The contract now matches the OS reality; SceneStorage-backed mode restoration is deferred to a later feature.
- **EC-13 expanded** — iCloud download-pending file shows an explicit loading indicator instead of "whatever loading affordance the system provides" (addresses F-007 partial — architecture handles the `UIDocument` state observation).
- **AC-RECOVER-1, AC-RECOVER-2 added** — save failures present a "Copy contents to clipboard" action so the user can rescue their work (addresses F-002). Full Save As remains Roadmap #3.

No standards-creep introduced by AC-A11Y-3 — it's a single accessibility hook on an existing surface, not a broader pass.

Requirements stable — no further requirements-side adversarial findings open.
