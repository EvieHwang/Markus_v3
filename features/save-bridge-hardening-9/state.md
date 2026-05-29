# State — save-bridge-hardening-9

Build state for `dag.md`. Updated by `/next` as each task transitions. See
constitution.md → Artifact formats → State file for the schema.

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | `WriteOutcomeBus` + success-only side-effect gating (DC-1/2/3) | 1 | complete | bfa4714 |
| T-002 | `ReconciliationLiftRefresh` on `reconcileOnForeground()` lift branch (DC-16/17/18/19/20) | 1 | complete | bfa4714 |
| T-003 | Coordinated write + save-back gate + scoped-resource discipline on the live bridge (DC-4/5/6/7/8/9) | 2 | complete | (sha pending) |
| T-004 | `SaveFailedAlertRouter` — single-alert lifecycle, background latch, conflict precedence, no double-fire (DC-10/11/12/13/14/15) | 3 | pending | |
