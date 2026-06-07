# Declaration

## What

Markus is a markdown editor for iOS that acts as a lens over the user's existing files — opening `.md` and `.markdown` files from anywhere in the iOS file system, letting the user read them as formatted GitHub Flavored Markdown or edit them as raw source, and saving changes back to the original location with no app-managed copies.

## Why

The dominant pattern in iOS markdown apps is to impose a proprietary vault, library screen, or sync engine that intercepts files and creates app-managed copies. This forces users who already have a folder structure they like — typically in iCloud Drive, Obsidian, or a similar location — to either reorganize around the app or maintain duplicate copies. Markus exists for users who want to edit the markdown files they already have, where they already are, without an app putting itself between them and their files.

## For whom

Someone who already has markdown files and already knows where they live — a writer (often a product manager or similar prose-writer) who works on iPhone, keeps files in iCloud Drive or another file-system-mounted sync service, and has organized them into folders of their own choosing. They are comfortable with iOS file conventions and the Files app. They want the shortest possible path from "launch app" to "editing my file," with no accounts, no onboarding, no library, and no settings to configure. They write prose, not code.

## Out of scope

- **No library or vault** — the user's folder structure is the library; Markus never relocates, copies, or indexes files.
- **No onboarding, splash, or setup wizard** — first launch goes straight to the system document browser.
- **No accounts or sync** — Markus does not authenticate with any service; sync is whatever the user's file-system location already does (iCloud, Dropbox, etc.).
- **No settings screen** — every behavior is fixed by design.
- **No version history** — the OS and sync services own that.
- **No syntax highlighting in the editor** — the user is writing prose, not code.
- **No proprietary format** — the file on disk is always plain `.md` / `.markdown`.
- **No silent merge on conflict** — the user is the only authority; conflicts are resolved by an explicit three-option choice.
- **No file types beyond `.md` and `.markdown`** — no `.txt`, no `.rtf`, no Word docs.

## Shape (revisable)

- **Document browser entry** — the system-provided document browser as the app's only "home"; no custom file-listing UI.
- **File access layer** — security-scoped bookmarks, external-change detection, save-back to original location, follow-on-move, deletion handling.
- **Document model** — the in-memory representation of an open `.md` file (raw source, dirty state, last-known-disk state).
- **Rendered view** — formatted GFM display, fading navigation chrome, tap-to-edit, long-press link handling.
- **Raw editor** — plain-text editing surface with native iOS editing behaviors, list continuation, smart-quote/dash suppression.
- **Mode switcher** — the rendered ↔ raw transition, including scroll-anchor preservation.
- **Conflict & lifecycle UI** — the three-option conflict sheet, deletion banner, new-file creation flow.

## Roadmap (revisable)

1. **Walking skeleton: open → render → edit → save** — open a `.md` file from the system browser, render it as GFM, tap to enter raw mode, edit, save back to original location, return to rendered. Stubbed: external-change detection, deletion handling, scroll preservation, new file creation. Touches: Document browser entry, File access layer, Document model, Rendered view, Raw editor, Mode switcher.
2. **Last-file resume on launch** — persist the last-opened file via security-scoped bookmark and reopen it directly on subsequent launches. Touches: File access layer, Document browser entry.
3. **External-change handling + conflict resolution** — silent absorption when clean; three-option sheet (Keep Mine / Keep Theirs / Discard Mine) when dirty; follow-on-move; deletion banner with Save As. Touches: File access layer, Document model, Conflict & lifecycle UI.
4. **Scroll-anchor preservation across mode switches** — nearest-heading anchor with fractional-scroll fallback. Touches: Mode switcher, Rendered view, Raw editor.
5. ~~**New file creation** — create a new file in the directory of the last-opened file, auto-incremented `Untitled.md` naming. Touches: File access layer, Conflict & lifecycle UI, Document browser entry.~~ *(superseded)*
6. **Native editing polish** — list continuation, smart-quote/dash suppression, autocorrect on, `Cmd+/` shortcut, swipe gestures. Touches: Raw editor, Mode switcher.
7. **Accessibility pass** — VoiceOver labels and traits, Dynamic Type, heading/list/link semantics in rendered view, "Edit" accessibility action. Touches: Rendered view, Raw editor, Mode switcher, Conflict & lifecycle UI.

### Post-shipping hardening

Added after the initial Roadmap was fully built, in response to a post-shipping audit. Each item closes a specific silent-failure path identified by the audit; together they harden the file lifecycle without changing product surface.

8. **Save-bridge hardening** — surface write errors instead of swallowing; coordinate writes with `NSFileCoordinator`; refresh buffer on reconciliation lift. Touches: File access layer, Conflict & lifecycle UI.
9. **Open-path hardening** — labeled handling of non-UTF-8 files; visible load-error surface from the document browser; hard ceiling on file size to prevent OOM. Touches: Document model, Document browser entry, Conflict & lifecycle UI.
10. **Resume & detector hardening** — fall back to bookmark when recorded resume path has moved; guarantee initial coordinated read precedes live presenter callbacks. Touches: File access layer.

### Backlog

Candidate work not yet scheduled. Captured here so the next planning pass can sequence it; order below is not commitment order.

11. **iPad universal — responsive layout** — add a max content width to the rendered view so prose stays readable at iPad / Mac window widths; verify the raw editor and conflict sheet relayout cleanly at slide-over widths (~320pt) and at full iPad widths (~1366pt). Touches: Rendered view, Raw editor, Conflict & lifecycle UI.
12. **Keyboard shortcut suite** — wire `UIKeyCommand` for the shortcuts a prose writer expects on a hardware keyboard: ⌘B bold, ⌘I italic, ⌘K link insertion, ⌘N new file, ⌘O open (returns to browser), alongside the already-planned ⌘/ mode toggle. Touches: Raw editor, Mode switcher, and the host.
13. **Pointer and hover interactions** — add `UIHoverGestureRecognizer` / `UIPointerInteraction` to the tap-to-edit surface, the mode-switch control, and the toolbar so the app feels native under iPad trackpad and Mac (Designed for iPad). Touches: Rendered view, Mode switcher.
14. **Mac-aware entry flow** — when running on Mac (Catalyst or Designed for iPad), bypass the browser host on launch and open the last document directly via the resume store, since Mac users expect File → Open and Finder integration rather than a browser screen. Touches: Host, Resume.
15. **Info.plist hardening for submission** — set `ITSAppUsesNonExemptEncryption = false` (removes the per-upload prompt); change `LSHandlerRank` from `Owner` to `Alternate` on the Markdown document type (honest given the "no proprietary format" stance); remove `LSRequiresIPhoneOS` once iPad is enabled; add an iPad-specific `UISupportedInterfaceOrientations~ipad` array covering all four orientations. Touches: App/Info.plist.
16. **App icon asset catalog cleanup** — `AppIcon.appiconset/Contents.json` currently references the 1024 PNG only for the iOS light slot and leaves dark, tinted, and 12 macOS slots empty. Either strip the unused slots (iPhone-only build) or wire up the full set if shipping iPad/Mac. Touches: Assets.xcassets.
17. **Launch screen content** — replace the empty `UILaunchScreen` dict with a minimal storyboard or at least a background color matching the rendered-view background, so the blank flash on cold launch goes away. Touches: App/Info.plist (and a new launch storyboard file if we go that route).
18. **Rendered theme polish** — replace the partial custom `MarkdownThemeFactory` theme with `Theme.gitHub` as a base, overriding only text and headings to preserve Dynamic Type scaling. Delivers table padding, code block backgrounds, blockquote styling, paragraph spacing, and link color for free. Touches: Rendered view.
19. **Mac multi-window / document tabs** — let the Mac app open multiple documents in separate windows (and/or native document tabs), with the multi-document model this requires: per-scene document and dirty state, per-window conflict/deletion lifecycle resolution, the "same file open in two windows" rule (lean toward focusing the existing window rather than opening a second), and window-set restoration in place of single-document resume. Deferred out of `mac-catalyst-shell-14`, which ships single-window; this is the one Mac affordance that reaches into the document model rather than the shell. Touches: Host, Document model, Conflict & lifecycle UI.
