# Feature Declaration: native-polish-6

## What

Native polish across the raw editor and rendered view: replace the default editor font with SF Mono, restore system-default typography in rendered view, fix a single-newline rendering gap, add swipe navigation between modes and the file browser, expose a long-press system menu (Copy / Select All / Share) in rendered view, align all colors and toolbar materials to HIG semantic values, and fix recent-file ordering in the document browser.

## Why

The prior features established correctness — files open, save, resume, and handle external changes. This feature establishes native iOS feel. The app currently reads as functional but generic; a prose writer on iPhone expects the editor surface and interaction patterns to feel like they were designed by Apple. Swipe navigation in particular is a foundational iOS interaction pattern whose absence is felt immediately.

## Success

- Raw editor uses SF Mono at an appropriate prose size; rendered view uses the system default (SF Pro via Dynamic Type).
- A single newline in raw source produces a visible line break in rendered view.
- Swiping right-to-left on the raw editor transitions to rendered view; swiping left-to-right on raw transitions back to the file browser; swiping left-to-right on rendered transitions to raw.
- Long-pressing in rendered view raises the standard iOS system menu with Copy, Select All, and Share; Share opens `UIActivityViewController` with the file's markdown text.
- All colors use HIG semantic system colors; toolbar and navigation bar use standard `.bar` material.
- Files opened via bookmark re-register with the document browser so they appear in its Recents section in correct order.

## Shape touched

- **Raw editor** — font (SF Mono), swipe gesture (R→L to rendered, L→R to file browser)
- **Rendered view** — typography (system default), line-break fix, swipe gesture (L→R to raw), long-press menu (Copy / Select All / Share)
- **Mode switcher** — swipe gesture coordination between raw and rendered
- **Document browser entry** — recents registration after bookmark-based resume opens

## Out of scope

- Syntax highlighting (excluded by project declaration)
- Functional checkboxes / task list toggling
- Cmd+/ or any other keyboard shortcuts
- Custom toolbar buttons or any UI chrome beyond standard system controls
- Font size or typeface choices in rendered view (system Dynamic Type governs those)
- New file creation (separate roadmap item)
