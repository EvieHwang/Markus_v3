# Build deviations — mac-catalyst-shell-14

Records adjustments made during the build where a test assertion or design call
shape did not match implementation reality. Each entry feeds back to the
req↔arch loop on the next adversarial pass.

---

## D-001 — Mac iconset slot count: 10, not 12

**Task:** T-007 (Mac app-icon slots — Component E)
**Affected:** `features/mac-catalyst-shell-14/tests/MacRestorationTests.swift`
(`macIconSlots_arePopulated` references `catalog.macSlots.count == 12`),
`features/mac-catalyst-shell-14/design.md` ("Existing seams confirmed → Icon
catalog" describes 12 `idiom:mac` slots).

**Original assertion in the spec test:**
```swift
#expect(catalog.macSlots.count == 12,
        "C-6.1: the catalog declares the 12 idiom:mac slots")
```

**What was wrong:** The pre-existing
`Markus_v3/Assets.xcassets/AppIcon.appiconset/Contents.json` declares **10**
`idiom:mac` slots, not 12. Apple's standard macOS iconset is five sizes
(16/32/128/256/512 pt) at two scales (1x, 2x), which is 10 slots total. The 64
and 1024 pt sizes are not idiomatic Mac iconset entries — 64 is rendered from
the 32@2x slot and 1024 is rendered from the 512@2x slot. Design.md inherited
the "12" miscount from a verbal description of "all the standard Mac sizes"
without verifying against the catalog. The spec test inherited the same number.

**Correction in the mirror (`Markus_v3Tests/MacCatalystShell14_AppIconTests.swift`):**
Asserts `macSlots.count == 10` to match the actual Mac iconset convention. The
spirit of the assertion — "every Mac slot must carry a filename, no empty
placeholders" — is preserved verbatim.

**Why the correction is safe:** The acceptance behavior (AC-6.1 — Dock/Finder/
switcher render a real Markus icon; no empty/placeholder slot) is invariant in
the slot count. The 10-slot catalog is exactly the standard Mac iconset that
macOS will render from at all required sizes. Populating all 10 satisfies the
behavioral requirement. The "12" was a verification error, not a behavioral
requirement.

**Adversarial follow-up:** Design.md "Existing seams confirmed → Icon catalog"
should be re-read against the live catalog in the next adversarial pass and
the "12" corrected to "10".
