# Spec Summary — iPad Expansion (ipad-expansion-13)

## Feature

Markus is a markdown editor that acts as a lens over a writer's existing files. Today it runs on iPad as a stretched-up iPhone app: every action needs a screen tap, and text runs the full width of a large display, producing long, tiring lines. This feature makes the iPad experience feel intentional through two bounded, self-contained improvements — hardware keyboard shortcuts for the core document actions, and a comfortable reading/writing column width — without adding any new product surface (no library, no settings, no toolbar) and without touching how files are stored.

## What it does

- **Keyboard shortcuts.** On an iPad with a hardware keyboard, three shortcuts drive the document actions a writer reaches for without leaving the keyboard:
  - **⌘P** toggles between rendered and raw editing modes.
  - **⌘W** closes the editor and returns to the file browser, saving the current document first so no edits are lost.
  - **⌘S** triggers an explicit save.
  Each appears in the iPad discoverability overlay (hold ⌘) with a clear, action-describing name. Each routes through the app's existing action — there is no second, parallel way to save, toggle, or close, so the keyboard and the on-screen controls can never drift apart. On a device with no hardware keyboard (typically iPhone), the shortcuts simply never fire — no behavior change, no special-casing.
- **Readable column width.** On a full-screen iPad, both the raw editor and the rendered preview are capped at a comfortable reading width (~700pt) and centered, with the surrounding margin as inert background — text is never clipped and the full column stays usable. In tight horizontal space (iPhone, or iPad Slide Over) the layout is unchanged, full-width. The treatment updates live as available width changes (rotation, entering/leaving Slide Over) without reopening the document or losing the writer's place.

## Risks carried

No risks acknowledged. The adversarial review surfaced one MEDIUM finding (⌘N new-document creation had no workable invocation path from inside the editor) and it was **resolved by removing ⌘N from the feature**, not deferred — so no open or acknowledged risk is carried into the build.

## Out of scope

- **⌘N / new-document creation** — dropped. The existing creation flow is the system browser's create control, which has no programmatic trigger reachable from inside the editor, and Markus deliberately removed its own programmatic create path (a prior project decision). Reintroducing one would reverse that decision and add storage-write scope this feature excludes; a no-op shortcut would mislead. ⌘N may return in a future feature if a programmatic create is reconsidered.
- **Formatting shortcuts** (⌘B/⌘I/⌘K) and any formatting toolbar — no text-mutating shortcuts.
- **⌘/ as the toggle key** (⌘P is used instead) and **⌘O / open** as a separate shortcut (⌘W covers returning to the browser).
- **Conflict-sheet relayout verification** at iPad widths — the conflict sheet already adapts; deferred to a future patch if it proves janky.
- **Sidebar / file-navigation panel, drag and drop, pointer/hover interactions, Mac-aware entry flow** — none are part of this feature.
- **New document model or storage changes** — ⌘S reuses the existing save flow unchanged; no new creation, model, or storage path is added.
- The width cap does **not** apply in the compact horizontal size class.

## Build preview

- **Waves:** 1
- **Tasks:** 2 — T-001 (editor key-command provider routing ⌘P/⌘W/⌘S to the existing toggle/save/close flows) and T-002 (shared ~700pt centered content column on both editor surfaces, regular width only, live on transition). The two are genuinely independent and run in parallel.
- **Session-budget assessment:** Comfortable. Each task fits one build session with margin; no new framework, dependency, or deploy path (existing UIKit key-command + responder chain, and size-class-conditional SwiftUI layout). The DAG fits one screen and one wave. It is a small two-task DAG — deliberately so for a focused two-part feature — with each task carrying a distinct behavioral contract and its own unit + UI spec-test pair, so it is not a single-task one-liner.

## Next step

Start a new session and run `/build feature-name: ipad-expansion-13`.
