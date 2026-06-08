# State — mac-catalyst-shell-14

Tracks build progress. Initialized by `/dag`; updated by `/next` as tasks complete.

Valid status values: `pending`, `in-progress`, `complete`, `failed`, `deviation`

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | Enable the Mac (Catalyst) destination on the target so the project builds and launches as a Catalyst Mac app (target/config change; no new framework or deploy path); inherited iOS/iPad behavior unchanged | 1 | complete | 1e4edcd — SUPPORTS_MACCATALYST=YES on all three targets (Debug + Release); xcodebuild lists the Mac Catalyst destination; build succeeds. |
| T-002 | Catalyst menu bar (Component A) — File/Edit/View structure, ⌘-equivalents matching firing bindings, responder-chain enablement, each Markus item a trigger onto the existing EditorActions/presentDocument flow; no New | 2 | pending | |
| T-003 | File → Open adapter (Component B base) — system open panel constrained to MarkdownDocument.readableContentTypes funneling the chosen URL into the existing presentDocument(at:); cancel/fail/non-md/resume-target inherited; no second open path | 2 | pending | |
| T-004 | Open-while-open composed host operation (Component B, F-001) — load-success-gated load → conditional teardown → present; failed new open leaves the prior document fully intact (DC-10); single window | 3 | pending | |
| T-005 | Pointer / hover affordance layer (Component C) — hover feedback on the tap-to-edit surface and the eye control; clickable == tappable; click == tap; never the sole affordance; inert with no pointer | 2 | pending | |
| T-006 | Mac scene-restoration bridge (Component D) — relaunch defers document choice solely to LaunchResumeBranch/LastFileStore; single window; moved/deleted/first-launch fail closed to the browser with no error UI; no new identity store | 2 | pending | |
| T-007 | Mac app-icon slots (Component E) — populate the 12 empty idiom:mac slots in AppIcon.appiconset additively; iOS/iPad icon unregressed | 2 | deviation | D-001 (build-deviations.md): catalog actually declares 10 Mac slots (5 sizes × 2 scales), not 12 — corrected the count assertion. All 10 slots populated with sips-resized PNGs; iOS slots untouched. Tests pass. |
