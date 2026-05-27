# State — native-polish-6

Tracks build progress. Updated by `/next` as tasks complete.

Valid status values: `pending`, `in-progress`, `complete`, `failed`, `deviation`

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | SF Mono font in MarkdownEditorTextView | 1 | complete | 35aa738; deviation BD-1 (SF Mono fontName prefix narrowed for iOS reality, see build-deviations.md) |
| T-002 | MarkdownLineBreakNormalizer new file | 1 | complete | 094b500 |
| T-003 | RecentsRegistrar + LaunchResumeBranch wiring | 1 | complete | b3571f5 |
| T-004 | Dynamic Type typography in RenderedView | 2 | complete | e2181d2 |
| T-005 | Wire MarkdownLineBreakNormalizer into RenderedView | 2 | complete | e2181d2 (atomic with T-004 in RenderedView.swift) |
| T-006 | HIG semantic colors + .bar material audit | 2 | complete | c600d0d |
| T-007 | Swipe gesture wiring (C3) | 3 | complete | a89b894 |
| T-008 | Share button + long-press text selection (C4 + C5) | 3 | complete | b1572ad |
