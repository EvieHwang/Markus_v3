# Requirements: native-polish-6

Behavioral requirements for the native-polish pass across the raw editor and rendered view. Derived from `declaration.md` (project) and `features/native-polish-6/declaration.md` (feature). Requirements are behavioral; they state observable outcomes, not implementation mechanisms.

## Revision notes

**v2 (addresses adversarial findings F-002 and F-003):**

- **NP-10.1 and NP-10.2 narrowed to best-effort framing (F-002):** The prior version asserted that files opened via bookmark would deterministically appear in Recents in access order. The design established that no documented public UIKit API exists for non-`UIDocument` apps to explicitly register Recents with `UIDocumentBrowserViewController` for programmatically-presented files. NP-10.1 and NP-10.2 are revised to reflect that the app makes a best-effort attempt; actual Recents appearance is OS-controlled and not guaranteed. NP-10.3–NP-10.6 are unchanged.
- **NP-9.1 scoped to feature-modified components (F-003):** The prior version stated "no color value in the app's UI" — an app-wide requirement that exceeded the design's audit scope (modified components only). NP-9.1 is narrowed to components added or modified by this feature, consistent with C6's audit scope in design.md.

## Definitions

These terms are used with fixed meaning throughout. Acceptance criteria reference them by name.

- **Raw editor** — the plain-text editing surface shown when a document is in edit mode.
- **Rendered view** — the formatted GFM display surface shown when a document is in read mode.
- **File browser** — the system-provided `UIDocumentBrowserViewController` that is the app's home screen.
- **Active mode** — whichever of raw editor or rendered view is currently visible and on screen.
- **Single newline** — a lone `\n` in raw source that is not preceded by two or more spaces and is not a blank line (i.e., not a paragraph break or a hard-line-break in CommonMark/GFM terms).
- **Security-scoped bookmark** — a persisted bookmark used to reopen a file across sessions, as used by the last-file resume feature.
- **Recents** — the "Recents" section of the system document browser that lists recently-accessed files in reverse access order.
- **HIG semantic color** — a `UIColor` or `Color` from the system semantic palette (e.g., `.label`, `.secondaryLabel`, `.systemBackground`, `.systemGroupedBackground`), not a hard-coded hex or RGB value.
- **`.bar` material** — the standard `UIBlurEffect.Style.systemMaterial` (or equivalent SwiftUI `.bar` material) applied to toolbars and navigation bars so they blur the content scrolling beneath them.
- **Share sheet** — the `UIActivityViewController` presented by the share button, offering system activities (AirDrop, Save to Files, Print, Mail, etc.) for the current file.

---

## User stories and acceptance criteria

### NP-1 — SF Mono font in raw editor

**As a** user editing raw markdown source,
**when** the raw editor is presented,
**so that** the editing surface is visually distinct from rendered prose and I can see raw characters (backticks, asterisks, hyphens) clearly,
**I want** the raw editor to use SF Mono at a legible prose size.

Acceptance criteria:
- NP-1.1 The raw editor displays all text in SF Mono.
- NP-1.2 The SF Mono size is fixed and appropriate for prose reading (not system-default body, not a display size).
- NP-1.3 The font is applied to the entire editing surface — existing text, newly typed text, and pasted text all render in SF Mono without exception.
- NP-1.4 The raw editor does not use the system default body font (SF Pro Text / San Francisco) for any portion of the editing surface.

### NP-2 — System default font (Dynamic Type) in rendered view

**As a** user reading formatted markdown,
**when** the rendered view is presented,
**so that** rendered prose respects my iOS accessibility text-size preferences,
**I want** the rendered view to use the system default font at Dynamic Type sizes.

Acceptance criteria:
- NP-2.1 The rendered view uses the system default typeface (SF Pro) with Dynamic Type; all body text scales with the user's preferred text size setting.
- NP-2.2 Changing the system text size (Settings → Accessibility → Display & Text Size → Larger Text) causes the rendered view's body text to grow or shrink accordingly when the view is next displayed.
- NP-2.3 The rendered view does not hard-code a fixed font size for body text.
- NP-2.4 Headings (`#`, `##`, `###`, etc.) in the rendered view scale proportionally relative to body text, consistent with standard HIG typographic scale behavior.

### NP-3 — Single-newline line break in rendered view

**As a** user who writes prose with single newlines between lines,
**when** I view the rendered output,
**so that** my line breaks appear visually as I wrote them,
**I want** each single newline in raw source to produce a visible line break (not a paragraph break) in the rendered view.

Acceptance criteria:
- NP-3.1 A single newline (`\n`) between two lines of text in raw source produces a visible line break in rendered output — the second line begins on a new line, not run-on as a continuation of a paragraph.
- NP-3.2 A blank line (two consecutive newlines, `\n\n`) between two lines of text in raw source produces a paragraph break (visible vertical spacing between paragraphs), not merely a line break.
- NP-3.3 The single-newline-as-line-break behavior applies everywhere in the rendered view that body text is rendered (paragraphs, list items, blockquotes), not only at the top level.
- NP-3.4 Single newlines within a fenced code block (``` ` ``` ` ` `` `...` `` ` ` ``` `` or indented code block) do NOT produce extra line breaks; code block content is rendered as-is, with newlines within the block representing only the code's own line structure.
- NP-3.5 Single newlines within an inline code span (`` `...` ``) do not affect rendering of surrounding body text.

### NP-4 — Swipe R→L on raw editor transitions to rendered view

**As a** user editing raw markdown,
**when** I swipe right-to-left on the raw editor,
**so that** I can preview my formatted output without lifting my hands to a button,
**I want** the swipe to transition me to the rendered view.

Acceptance criteria:
- NP-4.1 A right-to-left (leading-to-trailing) swipe gesture on the raw editor triggers a transition to the rendered view.
- NP-4.2 The transition is animated (consistent with standard iOS push/present transitions); the raw editor does not simply disappear.
- NP-4.3 Any unsaved edits in the buffer are preserved — the swipe does not discard them; the document state before the swipe is the document state in rendered view.
- NP-4.4 The rendered view shown after the swipe reflects the current buffer contents at the moment the swipe completes.
- NP-4.5 The swipe gesture recognizer on the raw editor does not interfere with the native iOS text selection gesture (a tap-and-hold that produces a cursor, not a swipe); only a clear horizontal swipe triggers the transition.
- NP-4.6 The swipe gesture recognizer on the raw editor does not interfere with scrolling — a predominantly vertical scroll gesture in the raw editor scrolls the content, not triggers a mode transition.

### NP-5 — Swipe L→R on raw editor transitions to file browser

**As a** user editing raw markdown,
**when** I swipe left-to-right on the raw editor,
**so that** I can return to the file browser without tapping a back button,
**I want** the swipe to navigate back to the file browser.

Acceptance criteria:
- NP-5.1 A left-to-right (trailing-to-leading) swipe gesture on the raw editor triggers a navigation back to the file browser, equivalent to the existing back/close button behavior.
- NP-5.2 The transition is animated and consistent with a standard iOS back navigation.
- NP-5.3 Returning to the file browser via swipe saves or handles unsaved state using the same rules as the existing close/back action (i.e., any autosave or save-before-close logic already in place fires on swipe-to-close).
- NP-5.4 The L→R swipe on raw does not conflict with the system-provided interactive pop gesture if one is active; they may be the same gesture recognizer or they must be coordinated so only one fires.
- NP-5.5 The swipe gesture recognizer does not interfere with text selection (see NP-4.5 for the same constraint applied here).
- NP-5.6 The swipe gesture recognizer does not interfere with scrolling (see NP-4.6 for the same constraint applied here).

### NP-6 — Swipe L→R on rendered view transitions to raw editor

**As a** user reading the rendered view,
**when** I swipe left-to-right on the rendered view,
**so that** I can switch to editing mode without lifting my hands to a button,
**I want** the swipe to transition me to the raw editor.

Acceptance criteria:
- NP-6.1 A left-to-right swipe gesture on the rendered view triggers a transition to the raw editor.
- NP-6.2 The transition is animated and visually consistent with iOS mode-switching conventions.
- NP-6.3 The document state is unchanged by the swipe — the same buffer is present in the raw editor.
- NP-6.4 The swipe gesture on the rendered view does not interfere with horizontal scrolling if the rendered view contains content that overflows horizontally (e.g., wide code blocks or tables); scroll gestures must be recognized as scrolling, not mode-switches, when the content is scrollable horizontally at that position.
- NP-6.5 The swipe gesture on the rendered view does not conflict with the standard iOS back/interactive-pop gesture if that gesture is also configured on this view.

### NP-7 — Long press in rendered view raises system text menu

**As a** user reading the rendered view,
**when** I long-press on text,
**so that** I can copy a passage or select all text using standard iOS conventions,
**I want** the standard iOS system text menu to appear with at minimum Copy and Select All.

Acceptance criteria:
- NP-7.1 A long press on text content in the rendered view presents the standard iOS system text menu (the callout bubble / context menu containing text-editing actions).
- NP-7.2 The menu contains at minimum the actions **Copy** and **Select All**.
- NP-7.3 **Copy** copies the selected (or long-pressed) text to the system pasteboard.
- NP-7.4 **Select All** selects all text in the rendered view.
- NP-7.5 The long-press gesture for the text menu does not conflict with the long-press gesture used for link activation if the pressed location is a rendered hyperlink; link long-press behavior (preview / open / copy link) takes precedence at a link, and the text menu is available at non-link positions.
- NP-7.6 When the rendered view contains no text (empty document), a long press produces no crash and no text menu (no text to operate on).
- NP-7.7 The text menu is the standard iOS system control — no custom-built action sheet or alert is used as a substitute.

### NP-8 — Share button in rendered view navigation bar

**As a** user reading the rendered view,
**when** I want to share, export, AirDrop, or print the file,
**so that** I can use any iOS system activity without the app needing to implement each one,
**I want** a standard share button in the navigation bar that opens the system share sheet with the file.

Acceptance criteria:
- NP-8.1 The rendered view navigation bar contains a share button using the `square.and.arrow.up` SF Symbol and no other icon.
- NP-8.2 Tapping the share button presents a `UIActivityViewController` (share sheet) with the file's URL as the activity item.
- NP-8.3 The share sheet includes at minimum the following system activities where supported by the device: AirDrop, Save to Files, Print, Mail (when configured), Copy (of the file reference). The exact activity list is provided by the OS; the app does not restrict or hard-code it.
- NP-8.4 When the share sheet is presented, the file on disk reflects the last-saved state (the share uses the disk copy, not an in-memory-only buffer).
- NP-8.5 If the user has unsaved edits in the buffer and taps the share button: the file shared is the last-saved version on disk (the share does not force-save before presenting). No data loss occurs — the unsaved edits remain in memory.
- NP-8.6 If the file has been deleted externally and the share button is tapped: the app does not crash. It may present an error or simply decline to open the share sheet; it must never hard-crash.
- NP-8.7 The share button is visible in the navigation bar when the rendered view is active; it is not present in the raw editor's navigation bar.
- NP-8.8 On iPad, the `UIActivityViewController` is presented in a popover anchored to the share button; on iPhone it is presented as a sheet. This is standard `UIActivityViewController` behavior and requires no special handling beyond passing the `sourceBarButtonItem` / `sourceView` correctly.

### NP-9 — HIG semantic colors and `.bar` material

**As a** user who may have Dark Mode, high-contrast mode, or other accessibility display settings enabled,
**when** I use the app,
**so that** the app adapts to my display preferences automatically,
**I want** all colors to be HIG semantic system colors and toolbars/navigation bars to use the standard `.bar` material.

Acceptance criteria:
- NP-9.1 No color value in any UI component added or modified by this feature is expressed as a hard-coded hex, RGB, or non-adaptive UIColor; every color in those components is a HIG semantic system color (e.g., `.label`, `.secondaryLabel`, `.tertiaryLabel`, `.systemBackground`, `.secondarySystemBackground`, `.systemGroupedBackground`, `.tintColor`, or equivalent). UI components not touched by this feature are out of scope for this requirement. *Addresses adversarial F-003.*
- NP-9.2 All toolbars and navigation bars use the standard `.bar` material (blur effect over scrolling content beneath) rather than a solid opaque fill.
- NP-9.3 The app's UI renders correctly and legibly in Dark Mode — switching between Light and Dark Mode in Settings does not produce invisible text, invisible icons, or color collisions.
- NP-9.4 The app's UI renders correctly and legibly with Increase Contrast accessibility setting enabled.
- NP-9.5 The navigation bar in both the raw editor and the rendered view uses the `.bar` material; the document browser's navigation bar is system-provided and is therefore exempt from this requirement.

### NP-10 — Recents registration after bookmark-based open

**As a** user who reopens files via security-scoped bookmarks (last-file resume),
**when** a file is opened via bookmark,
**so that** my recently-opened files appear in the document browser's Recents section in the order I opened them,
**I want** each bookmark-based open to register with the document browser's Recents.

Acceptance criteria:
- NP-10.1 After a file is opened via a security-scoped bookmark (e.g., last-file resume on launch), the app makes a best-effort attempt to register the file with the document browser's Recents using the best available UIKit API. Whether the file actually appears in Recents depends on OS behavior for security-scoped files opened outside the browser delegate; appearance in Recents is not guaranteed. *Addresses adversarial F-002.*
- NP-10.2 The app's registration attempt is made in access order (i.e., on each bookmark-based open); if the OS honors the registrations, the most recently-opened file will appear first. Deterministic ordering in Recents is not asserted — actual Recents ordering is OS-controlled. *Addresses adversarial F-002.*
- NP-10.3 A file that is opened via the document browser's own UI already appears in Recents by the system's own mechanism; NP-10 does not break this existing behavior.
- NP-10.4 Recents registration is attempted on every bookmark-based open, not only on the first open of a given file.
- NP-10.5 If the document browser is not the active view controller at the time of the bookmark-based open (e.g., a document is already open), Recents registration is still attempted; the app does not skip registration because the browser is off-screen.
- NP-10.6 A failed Recents registration (e.g., the document browser is unavailable or the call fails silently) does not crash the app, does not surface an error to the user, and does not prevent the file from opening.

---

## Edge cases and failure modes

- NP-11 **Swipe gesture conflicts in rendered view with horizontal scroll.** When a rendered document contains wide content (wide code blocks, tables, images), horizontal scroll gestures must be recognized as scroll, not as mode-switch swipes. The L→R swipe-to-raw gesture must fire only when the content at the swipe position is not horizontally scrollable, or when the gesture's primary direction is clearly horizontal across the full viewport width rather than a local content scroll.

- NP-12 **Swipe gesture conflicts in raw editor with text selection.** A long horizontal drag on the raw editor that the text engine interprets as extending a selection must not simultaneously trigger a mode-switch swipe. The mode-switch gesture should require a minimum velocity and/or travel distance from the edge that distinguishes it from selection-extending drags.

- NP-13 **Share sheet with unsaved changes.** When the user has unsaved buffer edits and opens the share sheet, the share must use the last-saved file on disk. The unsaved buffer is not force-saved before the share, and no alert is required to warn the user — the behavior (sharing the saved version) is sufficient. Post-share, the unsaved edits remain intact in the buffer.

- NP-14 **Share sheet when file has been deleted externally.** If the file on disk no longer exists when the share button is tapped, the app must not crash. An appropriate no-op (e.g., the share sheet fails to appear, or a brief system error is shown) is acceptable; the session with the buffer must not be interrupted.

- NP-15 **Long press on empty rendered content.** If the document contains no renderable text and the rendered view is visually empty, a long press produces no crash, no exception, and no spurious text menu (there is no text to select or copy).

- NP-16 **Single newlines inside fenced code blocks.** NP-3 (single-newline-as-line-break) must not alter rendering of code block content. Fenced code blocks (``` ``` ``` delimiters) render their internal newlines as literal newlines in the code presentation — no additional `<br>`-equivalent is injected between code lines. This must be confirmed against both single-line-fenced blocks and multi-line-fenced blocks.

- NP-17 **Single newlines inside inline code spans.** An inline code span spanning multiple lines of raw source is unusual but must not crash the renderer. Inline code content is rendered verbatim; no extra line breaks are injected.

- NP-18 **Recents registration when document browser is off-screen.** If the user relaunches the app and the bookmark-based open places a document view directly on screen (the browser is in the navigation stack but not visible), registration must still be attempted. Failure to register because the browser is off-screen is not acceptable; the implementation must use a mechanism that works without the browser being the current view controller (e.g., `recentDocumentURLs` API or equivalent).

- NP-19 **Swipe L→R on raw when file browser is not in the navigation stack.** If, for any reason, the file browser is not present in the navigation stack when the L→R swipe fires, the app must not crash. The swipe should either navigate to the nearest valid parent or be a no-op; it must not produce an assertion failure or navigation inconsistency.

- NP-20 **Swipe gestures during keyboard presentation.** If the software keyboard is up in the raw editor, a swipe R→L (to rendered) dismisses the keyboard as part of the transition. The keyboard state must not cause the gesture to fail or produce a visual glitch.

- NP-21 **Dynamic Type size extremes.** The rendered view at "Accessibility XL" (the largest Dynamic Type size) must not clip text, overlap elements, or produce illegible layout. The raw editor's SF Mono font is fixed-size and is exempt from Dynamic Type scaling (SF Mono is used for technical legibility, not accessibility scaling).

---

## Out of scope

- OOS-1 **Syntax highlighting** — the raw editor uses SF Mono for typographic clarity; no token coloring or language-aware highlighting is introduced. (Excluded by project declaration.)
- OOS-2 **Font or size selection** — the user cannot change the raw editor font or size, and cannot change the rendered view typeface. Dynamic Type governs rendered text size; the raw editor size is fixed by design.
- OOS-3 **Functional checkboxes / task list toggling** — GFM task list items are rendered but tapping the checkbox does not toggle state.
- OOS-4 **Keyboard shortcuts** — no `Cmd+/` or other keyboard shortcuts are added by this feature.
- OOS-5 **Custom toolbar buttons** — no new UI chrome beyond the share button in the rendered view navigation bar.
- OOS-6 **Custom share sheet activities** — the share sheet presents the standard system activity set; no app-specific activities are added.
- OOS-7 **Swipe navigation on the file browser** — no swipe gestures are added to the system document browser (it is a system control).
- OOS-8 **Long-press link handling in rendered view** — link tap and long-press behavior for hyperlinks is a separate concern; this feature adds the text-selection menu at non-link positions only.
- OOS-9 **Full accessibility labeling pass** — VoiceOver labels, traits, and heading semantics for the new controls (share button, swipe gesture hints) are deferred to the Roadmap #7 accessibility pass. Controls must function but complete VoiceOver labeling is not required here.
- OOS-10 **New file creation** — a separate roadmap item; not touched here.

---

Requirements stable — no architectural feedback to incorporate

*v2: F-002 and F-003 addressed. F-001 (indented-code-block heuristic in normalizer) and F-004 (rendered view L→R swipe vs. edge-pan overlap) remain open — both are architecture-side findings requiring updates to design.md, not requirements changes.*
