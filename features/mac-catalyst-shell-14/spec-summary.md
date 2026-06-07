# Spec Summary — Mac Catalyst Shell (mac-catalyst-shell-14)

## Feature

Markus is a markdown editor that acts as a lens over the user's existing files —
opening `.md` files where they already live, with no vault, library, or
app-managed copies. This feature brings Markus to the **Mac** as a native **Mac
Catalyst** build: the platform *shell* only. It takes the existing iOS/iPad app
(which already runs on Apple Silicon but behaves like an iPad app in a window —
no menu bar, no File → Open, no pointer affordances) and makes it feel like a Mac
app by conforming to Apple's Human Interface Guidelines at the shell level. It
adds **no new product capability**: every action exposed already exists in the
iOS/iPad build, and all file-access, render, edit, save, conflict, and lifecycle
behavior is inherited unchanged.

## What it does

- **A standard Mac menu bar.** File (Open, Save, Close), Edit (the system-standard
  Undo / Cut / Copy / Paste / Select All), and View (Toggle Preview). Each menu
  item shows its keyboard shortcut and performs the exact same action as that
  shortcut — there is no second, divergent implementation behind any menu item.
- **Document-aware menus.** Save, Close, and Toggle Preview are grayed out when no
  document is open, so the menu never offers an action that can't be performed;
  Open is always available.
- **File → Open (⌘O).** Opens a `.md` / `.markdown` file through the standard Mac
  open panel, using the app's existing open and security-scoped-bookmark machinery
  — the same path as picking a file in the browser. A file opened this way is
  remembered for resume. Canceling the panel changes nothing.
- **Safe open-while-already-open.** If the user opens a new file while one is
  already open, the app validates the new file *first*; only if it loads
  successfully does it replace the current document. If the new file fails to open,
  the current document is left fully intact and the existing "Couldn't open"
  message appears — the user is never dropped to an empty window. The app stays
  single-window throughout.
- **Pointer and hover feedback.** Under a trackpad or mouse, the tap-to-edit
  surface and the mode-switch control respond to the pointer so they read as
  interactive. Clicking does exactly what tapping does; nothing is hidden or gated
  behind hover, and behavior is unchanged where there's no pointer device.
- **Relaunch restores your document.** On the Mac, "resume last file" is expressed
  as window-state restoration: relaunching brings back the document you had open,
  resolved the same way (and to the same file) as today's resume. If that file has
  moved or been deleted, the app falls back exactly as it does now — landing on the
  browser with no error dialog. Single window only.
- **A proper Mac app icon** in the Dock, Finder, and app switcher, with no
  regression to the existing iOS/iPad icon.

## Risks carried

No risks acknowledged. The adversarial review surfaced one HIGH finding — the
open-while-open transition was specified two contradictory ways, one of which
would have dropped the user to an empty window if a newly chosen file failed to
open — and it was resolved in the design (load-success-gated ordering) and
verified as holding, with zero open findings remaining. No findings were
acknowledged or deferred.

## Out of scope

- **Multi-window / document tabs** and any multi-document model — deferred to the
  project roadmap (backlog item 19). The Mac app is single-window.
- **Formatting commands** (⌘B / ⌘I / ⌘K) and any formatting toolbar — text-mutating
  new capability, excluded consistent with feature 13.
- **File → New / ⌘N** — no programmatic create path exists in the app today.
- **⌘/ as a mode toggle** — the toggle stays on ⌘P.
- **Editor max content width** — already shipped in feature 13 and inherited on Mac;
  not re-implemented.
- **Settings / preferences, accounts, library / sidebar, drag-and-drop** — none added.
- **Conflict / deletion / save behavior changes, or any new save UI** — the Catalyst
  build inherits these flows unchanged.

## Build preview

**3 waves, 7 tasks.** Wave 1 is a single root task — enabling the Mac (Catalyst)
destination on the target (a configuration change, not a new framework or deploy
path). Wave 2 is five independent shell components that parallelize: the menu bar,
the File → Open adapter, the pointer/hover layer, the scene-restoration bridge,
and the Mac icon slots. Wave 3 is the one higher-risk task — the load-success-gated
open-while-open operation that resolves the adversarial finding — isolated on its
own because it depends on the open adapter. The DAG is assessed as a comfortable
single-build-session feature: no new framework, dependency, or deploy path, and
every task reuses the app's own existing flows over standard Catalyst/UIKit
mechanisms. Every task has at least one mapped test.

## Next step

Start a new session and run `/build feature-name: mac-catalyst-shell-14`.
