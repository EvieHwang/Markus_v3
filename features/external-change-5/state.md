# State: external-change-5

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | `ContentEqualityGate` (DC-11) — byte-or-newline-normalized equality | 1 | pending | |
| T-002 | `LastKnownDiskState` (DC-9, DC-10) — clean/dirty authority on the document model | 1 | pending | |
| T-003 | `ConflictResolution` (DC-13) — Keep Mine / Keep Theirs / Discard Mine end-states | 1 | pending | |
| T-004 | `ChangeClassifier` (DC-4) — four exclusive outcomes, presence-first | 2 | pending | |
| T-005 | `SettleGate` (DC-6, DC-7, DC-8) — 2s window + in-flight suppression, delay-not-discard | 2 | pending | |
| T-006 | `ApplyEdgeRevalidation` (DC-21) + `SaveSuspensionLatch` (DC-22) — apply-edge integrity | 2 | pending | |
| T-007 | Change detector (DC-1/2/3/5) — single coordinated-read authority reconciled with `SaveStatusObserver` | 3 | pending | |
| T-008 | Conflict sheet (DC-14, DC-15) — three-option modal driven by `collision` | 4 | pending | |
| T-009 | Deletion banner + Save As + follow-on-move (DC-16/17/18/19/20) | 4 | pending | |
| T-010 | `ForegroundReconciler` (DC-23) + lifecycle wiring + failure-path reuse | 4 | pending | |
