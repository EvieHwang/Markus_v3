# Adversarial Review — save-bridge-hardening-9

requirements.md @ 16e01906b8436e3ce1596c51e86ca1c94fa3fda7 · design.md @ dd92651e037de724f5ecc1ebdee0075520a7f4e5 · Mode: fresh review

## Summary

Zero open findings. Requirements and design are coherent, traceable, and ready to build.

The spec extends two existing seams (`MarkdownDocumentSaveBridge`, `ChangeDetector.reconcileOnForeground()`) and one existing UI surface (`ActiveAlert.saveFailed`), all marked `Extends seam:` / `Reuses pattern:` / `Reuses seam:` in design.md. Per the pattern-reuse scoping rule, security and failure-mode lenses on those surfaces were held to HIGH severity only; nothing rose to that bar.

## Lens-by-lens

- **Integrity.** Every BR (BR-1 through BR-3) maps to a DC cluster (DC-1–DC-4 for BR-1, DC-5–DC-9 for BR-2, DC-16–DC-20 for BR-3). Every edge case (BR-4 through BR-12) has an explicit DC anchor (BR-4 → DC-13, BR-5 → DC-11, BR-6 → DC-12, BR-7 → DC-6, BR-8 → DC-7, BR-9 → DC-18, BR-10 → DC-20, BR-11 → DC-14, BR-12 → DC-5/DC-13). Non-regressions (NR-1 through NR-7) are reaffirmed in DC-9, DC-4, DC-15, DC-19 and the test-anchor list.
- **Coverage.** Both success-only side effects called out in BR-1.5 (lastKnownDiskContent update, settle-window open) are explicitly gated on success in DC-2. Both lift sub-paths (content-identity, moved-successor) covered (DC-16, DC-17). Re-present branch explicitly preserved (DC-19).
- **Security (HIGH-only, pattern-reuse scope).** No new attack surface. Security-scoped resource discipline explicitly preserved across success/failure paths (DC-8). No findings.
- **Standards compliance (constitution.md).** Apple HIG: reuse of single-alert surface follows platform alert conventions. Swift 6 strict concurrency addressed in the Ground-truth check (main-actor only; error hops back to main before touching alert state or `lastKnownDiskContent`). Constitution registers no Swift-specific pattern this feature would violate.
- **Failure modes.** Coordinator acquisition failure (DC-6), atomic-write throw inside coordinated block (DC-7), background failure with no view alive (DC-13), conflict-sheet precedence over save-failed alert (DC-14), double-fire suppression with `SaveStatusObserver` (DC-15), disk-read failure during reconciliation (DC-20). All named failure modes have explicit behavioral resolutions.
- **Scope drift.** Design stays inside the declaration's three-change envelope. Out-of-scope items (retry queues, sidecar files, `UIDocument` migration, open-path hardening, resume/detector hardening) are reaffirmed in OOS-1–OOS-10 and not encroached upon in the design.

## Findings

None open.

## Prescription feedback

None. The design explicitly anticipates the prescription-vs-property tension and resolves it in its own "Prescription-feedback resolution" section: the three named implementation specifics (`NSFileCoordinator.coordinate(writingItemAt:)`, `MarkdownDocumentSaveBridge.writeNow()`, `ActiveAlert.saveFailed`) are kept as orientation while the test surface is restated as observable properties. No additional prescription-only material was identified during this review.
