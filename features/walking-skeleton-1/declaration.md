# Feature declaration: walking-skeleton-1

*Walking skeleton — first feature.*

## What

The thinnest end-to-end path through Markus: pick a `.md` file from the system document browser, see it rendered as GitHub Flavored Markdown, tap the document to switch into raw mode, edit the source, and have the edits saved back to the original file location. Tapping the toolbar eye icon returns to rendered mode. Nothing more.

## Why

This is the project's first feature, intentionally built as a walking skeleton rather than a deep slice. It exists to prove the core thesis end-to-end — that an iOS markdown editor can open a file from anywhere the user keeps it, edit it, and save it back without app-managed copies — and to make all seven seams from `declaration.md`'s Shape meet for the first time. Once the spine exists, every subsequent feature (last-file resume, conflict handling, scroll preservation, new-file creation, polish, accessibility) iterates against it instead of being retrofitted onto a partial system.

## Success

The skeleton is working when a user can complete this full loop without the app crashing or losing data:

1. Launch the app → land on the system document browser (no splash, no onboarding).
2. Navigate to and pick any `.md` or `.markdown` file from anywhere in the iOS file system.
3. See the file rendered as GitHub Flavored Markdown.
4. Tap the document → enter raw mode showing the markdown source.
5. Edit the source.
6. Tap the toolbar eye icon → return to rendered mode, edits visible.
7. Close and reopen the file from the document browser → the saved edits are present on disk at the original location, with no copy created elsewhere.

All seven Shape seams participate in this loop, even if minimally:
- **Document browser entry** — opens, picks a file.
- **File access layer** — reads from and writes back to the picked file's original location via security-scoped access. (Stubbed: external-change detection, follow-on-move, deletion handling.)
- **Document model** — holds raw source and dirty state in memory.
- **Rendered view** — displays GFM. (Stubbed: fading nav chrome, long-press link context menu.)
- **Raw editor** — plain-text editing surface. (Stubbed: list continuation, smart-quote suppression, `Cmd+/`, swipe gestures.)
- **Mode switcher** — tap-to-edit and eye-icon-to-render transitions work. (Stubbed: scroll-anchor preservation.)
- **Conflict & lifecycle UI** — present as a no-op surface; no conflict sheet, no deletion banner, no new-file flow yet (those are later Roadmap items).

## Shape touched

All seven seams from `declaration.md`'s Shape participate. This is expected for a walking skeleton; later features deepen each.

- **Document browser entry** — full participation; the only way into the app.
- **File access layer** — minimal: read + write-back via security-scoped access on the picked file. No bookmark persistence, no external-change detection, no follow-on-move, no deletion handling.
- **Document model** — minimal: raw source + dirty flag in memory.
- **Rendered view** — minimal: GFM display only. No fading nav chrome, no link long-press menu.
- **Raw editor** — minimal: a plain `UITextView`-class editing surface. No list continuation, no smart-quote suppression, no shortcut bindings, no swipe gestures.
- **Mode switcher** — minimal: tap-to-edit, eye-icon-to-render. No scroll-anchor preservation.
- **Conflict & lifecycle UI** — present as a stub/no-op surface so later features have a place to attach. No actual conflict sheet, deletion banner, or new-file flow yet.

## Out of scope

The following are explicitly deferred to later Roadmap items or to project-level out-of-scope, and the skeleton must not attempt them:

- **Last-file resume on launch** — Roadmap #2. Skeleton always starts at the document browser; no bookmark persistence.
- **External-change detection** — Roadmap #3. Skeleton does not observe disk changes while a file is open.
- **Conflict resolution sheet** — Roadmap #3. Skeleton assumes no conflicts; last-write-wins from the editor.
- **Follow-on-move** — Roadmap #3. If a file moves externally while open, behavior is undefined.
- **Deletion banner / Save As** — Roadmap #3. Skeleton does not detect deletion.
- **Scroll-anchor preservation across mode switches** — Roadmap #4. Skeleton returns to the top on switch, or wherever the OS lands it.
- **New file creation** — Roadmap #5. Skeleton only opens existing files.
- **List continuation, smart-quote/dash suppression, autocorrect tuning, `Cmd+/` shortcut, swipe gestures** — Roadmap #6. Skeleton uses default `UITextView` behavior.
- **Accessibility pass** — Roadmap #7. Skeleton ships with whatever VoiceOver/Dynamic Type behavior the default views give; no explicit labels, traits, or "Edit" action.
- **Fading navigation chrome on scroll** — deferred polish.
- **Share button, Find, overflow menu** — deferred polish.
- **iPad-specific layout** — deferred (kickoff notes this was left open).
- **Syntax highlighting in code blocks** — out of scope project-wide.
- **Anything in `declaration.md`'s project-level "Out of scope"** — inherited (no library, no onboarding, no accounts, no settings, no version history, no proprietary format, no silent merge, no non-`.md`/`.markdown` files).
