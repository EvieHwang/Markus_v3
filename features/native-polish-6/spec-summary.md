# Spec Summary: native-polish-6

## Feature

Native polish across the raw editor and rendered view. The prior features established correctness — files open, save, resume, and handle external changes. This feature makes the app feel like it was designed by Apple. It targets a prose writer on iPhone who expects native iOS interaction patterns: swipe navigation between views, a share button that works like every other document app, a monospaced editor font that reads well, and colors that respect the system's light/dark mode properly.

## What it does

- **Raw editor font**: the editing surface uses SF Mono — Apple's own monospaced typeface — at a readable prose size, applied consistently including to pasted text.
- **Rendered view typography**: the rendered view uses the system's default Dynamic Type body style (SF Pro), scaling with the user's preferred text size.
- **Line break fix**: a single Return in the raw editor now produces a visible line break in the rendered view, matching what writers expect. Paragraph breaks (two Returns) and code blocks are unaffected.
- **Swipe navigation**: swipe left on the raw editor to switch to rendered view; swipe right on the raw editor to go back to the file browser; swipe right on the rendered view to switch to raw editing. The system edge-pan gesture keeps priority near the screen edge.
- **Long press in rendered view**: standard iOS text selection menu (Copy, Select All) appears on long press — no custom UI.
- **Share button**: a standard share icon in the top-right corner of the rendered view opens the system share sheet for the file, enabling AirDrop, Save to Files, Print, and Markup. The raw editor does not show the share button.
- **HIG colors and materials**: all UI components added or modified by this feature use semantic system colors and the standard toolbar blur material, correctly adapting to Dark Mode and Increase Contrast.
- **Recents registration**: when the app reopens a file via its saved bookmark, it makes a best-effort attempt to register the access with the document browser so the file appears in Recents. Whether it surfaces in Recents is OS-controlled and not guaranteed.

## Risks carried

**F-005 (LOW, open):** The line-break normalizer operates at the block level. A newline inside an inline code span (e.g. `` `foo\nbar` ``) will receive the trailing-space injection even though it shouldn't. The current renderer likely hides the artefact (spaces inside backticks render verbatim), but the algorithm is technically inconsistent with the spec. Documented as a known gap for a future polish pass; not blocking.

**NP-10 (best-effort):** Recents registration has no guaranteed public UIKit API for apps that open files programmatically rather than through the document browser UI. The implementation attempts registration via the best available mechanism; the builder should verify at build time and document which API was used.

## Out of scope

- Syntax highlighting (excluded by project declaration)
- Functional checkboxes / task list toggling
- Keyboard shortcuts (Cmd+/ or similar)
- Custom toolbar buttons or non-standard UI chrome
- Font size or typeface choices in the rendered view (Dynamic Type governs those)
- New file creation (separate roadmap item)
- Color or typography changes to app components not touched by this feature

## Build preview

3 waves, 8 tasks. Wave 1 (3 tasks) is fully parallel: SF Mono font, the line-break normalizer, and the recents registrar can all be built independently. Wave 2 (3 tasks) wires the normalizer into the rendered view and applies the color/material audit. Wave 3 (2 tasks) adds swipe navigation and the share button + text selection. The DAG fits comfortably in one build session with margin.

## Next step

Start a new session and run `/build feature-name: native-polish-6`.
