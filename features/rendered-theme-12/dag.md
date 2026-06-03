# DAG — Rendered Theme Polish (rendered-theme-12)

Generated: 2026-06-03

## Size check

Feature scope: one file (`MarkdownThemeFactory.swift`), one logical substitution
(change base theme, remove three overrides, remove margin calls from headings, verify
`.isHeader` trait is present). All edits are co-located in a single method and have
no mutual ordering dependencies. **1 task — within the expected 1–3 range.**

---

## Tasks

### T-001 — Migrate MarkdownThemeFactory to Theme.gitHub base

**Description:**
Edit `MarkdownThemeFactory.makeTheme()` to:
1. Change the base theme from `Theme()` to `Theme.gitHub`.
2. Remove the `.code { ... }`, `.strong { ... }`, and `.emphasis { ... }` overrides
   (subsumed by `Theme.gitHub`).
3. Remove the `.markdownMargin(top: 24, bottom: 16)` call from every heading builder
   (`heading1` through `heading6`), delegating margin behavior to `Theme.gitHub`.
4. Confirm `.accessibilityAddTraits(.isHeader)` is present in every heading builder
   (it already exists; must not be removed).

No changes to any other file.

**Inputs:**
- `Markus_v3/Views/MarkdownThemeFactory.swift` (read existing implementation)
- `features/rendered-theme-12/requirements.md` (AC-8.5, AC-8.6, FM-1, FM-7, FM-9)
- `features/rendered-theme-12/design.md` (component table, behavioral constraints BC-1 – BC-15)

**Outputs:**
- `Markus_v3/Views/MarkdownThemeFactory.swift` (modified)

**Dependencies:** none

**Wave:** 1

**Acceptance conditions (objectively checkable):**
1. `MarkdownThemeFactory.swift` contains the string `Theme.gitHub` as the chain root of `makeTheme()`.
2. `MarkdownThemeFactory.swift` does not contain `return Theme()`.
3. `MarkdownThemeFactory.swift` does not contain `.code {` or `.code{`.
4. `MarkdownThemeFactory.swift` does not contain `.strong {` or `.strong{`.
5. `MarkdownThemeFactory.swift` does not contain `.emphasis {` or `.emphasis{`.
6. `MarkdownThemeFactory.swift` does not contain `markdownMargin`.
7. `MarkdownThemeFactory.swift` contains exactly 6 occurrences of `.accessibilityAddTraits(.isHeader)`.
8. `MarkdownThemeFactory.swift` does not contain `.pt(` (no fixed point sizes in heading builders).
9. `MarkdownThemeFactory.swift` does not contain `Color(red:` or `UIColor(red:` (no hard-coded color literals).
10. `xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 17'` exits 0 with all tests passing.

---

## Wave Summary

| Wave | Tasks | Can run in parallel |
|------|-------|---------------------|
| 1    | T-001 | — (sole task)       |
