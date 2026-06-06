# Declaration

## What

Make Markus a first-class iPad app through two concrete, bounded improvements to the existing editor surface:

1. **Hardware keyboard shortcuts** for the core document actions a writer reaches for without leaving the keyboard:

   | Shortcut | Action |
   |----------|--------|
   | ⌘P | Toggle raw ↔ rendered mode |
   | ⌘W | Close the editor, return to the file browser |
   | ⌘N | Create a new document |
   | ⌘S | Trigger an explicit save |

   These surface in the iPad discoverability overlay (hold ⌘) and are no-ops where no hardware keyboard is present (typically iPhone), so they need no device conditional — they simply never fire without a keyboard.

2. **Editor line-length constraint.** Cap the editor content at a maximum readable width (~700pt), centered in the available space, applied to both the raw editor and the rendered preview. This applies only when horizontal space is ample (regular horizontal size class); on iPhone or in Slide Over, the layout is unchanged.

## Why

Markus serves a prose writer who already keeps their files where they want them and wants the shortest path from launch to editing. That writer increasingly works on iPad with a hardware keyboard, where Markus today behaves like a stretched iPhone app: every core action requires reaching for the screen, and text runs the full width of a large display, producing tiring, hard-to-scan lines. These two changes make the iPad experience feel intentional — keyboard-driven document control and a reading/writing width that matches focused writing apps — without adding any product surface (no library, no settings, no toolbar), staying true to the project's "lens over your files, nothing between you and them" purpose. This advances the roadmap's backlog items 11 (iPad responsive layout) and 12 (keyboard shortcuts), narrowed to a concrete, shippable cut.

## Success

- On an iPad with a hardware keyboard, each of ⌘P, ⌘W, ⌘N, ⌘S performs its action from the editor, and all four appear in the system discoverability overlay when ⌘ is held.
- The same shortcuts cause no behavior change and no crash on a device with no hardware keyboard.
- In the regular horizontal size class (full-screen iPad), both the raw editor text and the rendered preview are constrained to ~700pt and centered, with no horizontal layout change in the compact size class (iPhone, Slide Over).
- No regression to existing open/render/edit/save/conflict behavior.

## Shape touched

- **Mode switcher** — ⌘P drives the existing rendered ↔ raw transition.
- **Raw editor** — receives ⌘S (save), ⌘N (new), ⌘W (close), and the centered max-width constraint.
- **Rendered view** — receives the same shortcuts where applicable and the centered max-width constraint.
- **Host** (document browser entry / scene) — ⌘W returns to the browser; ⌘N invokes the existing new-document creation flow; shortcuts are registered at a level where the discoverability overlay sees them.

All four are existing Shape components; this feature adds no new component.

## Out of scope

- **Formatting shortcuts** (⌘B / ⌘I / ⌘K) and any formatting toolbar — roadmap item 12 imagined these; this feature deliberately excludes text-mutating shortcuts and toolbar buttons.
- **⌘/ as the mode-toggle key** — the toggle is bound to ⌘P per this feature; ⌘/ (referenced in roadmap items 6 and 12) is not used.
- **⌘O / open** as a distinct shortcut — returning to the browser is covered by ⌘W; there is no separate open shortcut.
- **Conflict-sheet relayout verification** at iPad/Slide-Over widths (roadmap item 11) — the conflict sheet is a system-adaptive sheet with no reported relayout defect; deferred to a future patch if it proves janky in practice.
- **Sidebar or file-navigation panel**, **drag and drop**, **pointer/hover interactions**, and **Mac-aware entry flow** — none are part of this feature.
- **New document model or storage changes** — ⌘N and ⌘S invoke existing creation and save flows unchanged.
- The width constraint does **not** apply in the compact horizontal size class.
