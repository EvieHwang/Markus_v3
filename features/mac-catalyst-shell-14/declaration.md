# Declaration

## What

Bring Markus to the Mac as a native **Mac Catalyst** app: the platform *shell* only. A standard Mac menu bar (File / Edit / View) exposing the document actions the app already has; **File → Open** as the Mac entry idiom; pointer/hover feedback on existing tap targets; single-window state restoration as the Mac expression of "resume last file"; and proper Mac app-icon assets. No new product capability.

## Why

Markus is "a lens over your files," and that premise is even more at home on the Mac, where the user's folder structure *is* the Finder. Feature 13 (`ipad-expansion-13`) already delivered readable line width and the ⌘P/⌘W/⌘S shortcuts; running that build on Apple Silicon via Catalyst gets Markus onto the Mac, but it behaves like an iPad app in a window — no menu bar, no File → Open, no pointer affordances. This feature makes it feel like a Mac app by conforming to Apple HIG at the shell level (advancing backlog items #13 pointer/hover, #14 Mac-aware entry flow, #16 Mac icon slots), adding zero product surface and staying true to the "nothing between you and your files" purpose.

## Success

- The app runs as a Catalyst Mac build with a standard menu bar; the File / Edit / View menus contain the app's existing actions (Open, Save, mode toggle, close) and the system-standard Edit items (undo / cut / copy / paste / select-all), each showing its ⌘ equivalent.
- File → Open (⌘O) lets the user pick a `.md` / `.markdown` file from the filesystem and open it, using the existing open + security-scoped-bookmark path.
- Save, mode-toggle, and close/return are reachable from the menu bar and the keyboard, matching feature 13's bindings where they overlap (⌘P toggle, ⌘W close, ⌘S save).
- Pointer/hover feedback appears on the tap-to-edit surface and the mode-switch control under a trackpad or mouse.
- The Mac app shows a proper app icon (no empty or placeholder asset slots).
- On relaunch, the app restores the previously open document via Mac window-state restoration, consistent with existing resume behavior.
- No regression to existing open / render / edit / save / conflict behavior; no new product surface.

## Shape touched

- **Host** (document browser entry / scene) — gains the Mac menu bar, the File → Open entry, and window-state restoration.
- **Mode switcher** — mode-toggle exposed in the View menu; pointer feedback on the switch control.
- **Rendered view** — pointer/hover on the tap-to-edit surface; menu items act on it where applicable.
- **Raw editor** — Edit-menu standard items operate on it; menu-driven save.

All are existing Shape components; this feature adds no new component.

## Out of scope

- **Multi-window / document tabs** and the multi-document model they imply — deferred to the roadmap (explicit decision for this feature). The Mac app is single-window.
- **Formatting commands** (⌘B / ⌘I / ⌘K, bold / italic / link) and any formatting toolbar — text-mutating, a new capability; excluded, consistent with feature 13.
- **New-document creation** (File → New / ⌘N) — no programmatic create path exists (roadmap item 5 superseded by `restore-system-create-7`; see feature 13). Excluded.
- **⌘/ as a mode toggle** — the toggle stays on ⌘P per feature 13.
- **Editor max content width (#11)** — already delivered by feature 13 and applies on Mac via the regular horizontal size class; not re-implemented here.
- **Settings / preferences window**, accounts, library / sidebar, drag-and-drop — none added.
- **Conflict / lifecycle behavior changes** — Catalyst inherits the existing conflict, deletion, and save flows unchanged.
