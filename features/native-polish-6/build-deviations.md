# Build deviations — native-polish-6

Per the build skill: when a test fails after genuine investigation reveals the
test was built on a false assumption about the library, the test may be
corrected and the change documented here. Requirements remain immutable.

---

## BD-1 — NP-1 font-name assertion narrowed to accept `monospacedSystemFont` internal name

**Tests affected:** `Markus_v3Tests/NativePolish6_SFMonoFontTests.swift`
- `rawEditorUsesSFMono`
- `rawEditorFontNameIsSFMono`
- `rawEditorTypingAttributesCarrySFMono`
- `rawEditorTextAssignmentRetainsSFMono`

**Original assertion:** `tv.font?.fontName.hasPrefix("SFMono-")` and that
`UIFont(name: "SFMono-Regular", size: 17)` resolves to a font with that name.

**What's wrong with the original:** On iOS (iPhone 17 Pro simulator, iOS 26.5),
`UIFont(name: "SFMono-Regular", size: 17)` returns `nil`. SF Mono is a
system-only font and is not loadable by name from a regular app process. The
documented Apple API for accessing SF Mono on iOS is
`UIFont.monospacedSystemFont(ofSize:weight:)`, which does return the SF Mono
typeface, but its internal `fontName` is `.AppleSystemUIFontMonospaced-Regular`
(`familyName` = `.AppleSystemUIFontMonospaced`). The test assertion's literal
string check was built on the assumption that SF Mono can be loaded by name
on iOS like a third-party font; that assumption is false.

The design itself acknowledges this in the C0 section:
> Today `configureAppearance()` calls `UIFont.monospacedSystemFont(ofSize:weight:)`
> which resolves to SF Mono on Apple hardware but whose documented contract
> does not guarantee it.

The fallback path was added to make the behavior more explicit, but in
practice the fallback is the only path that ever fires on iOS — the named
load always returns nil.

**Behavioral requirement satisfied:** NP-1.1 ("raw editor displays all text in
SF Mono") and NP-1.4 ("raw editor does not use SF Pro for any portion of the
editing surface") are satisfied. The font is SF Mono (the system monospace
typeface). NP-1.4's complementary test
(`rawEditorDoesNotUseSFPro` — checks the font name does NOT start with `.SF`,
`.SFPro`, or `.SFProText`) passes against the `.AppleSystemUIFontMonospaced-`
font without modification, confirming the actual typeface is monospaced and
not SF Pro.

**Correction:** The Xcode tests now accept either:
- `fontName.hasPrefix("SFMono-")` (the named-font path, if Apple ever exposes
  SF Mono by name in the app process), or
- `fontName.hasPrefix(".AppleSystemUIFontMonospaced-")` (the
  `monospacedSystemFont` fallback path, which is the documented public API for
  SF Mono on iOS).

Additionally, the tests verify `font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)`
as a structural assertion that the typeface is monospaced — this is what the
behavioral requirement (NP-1) actually constrains.

**Why not weaken the implementation:** The implementation in
`MarkdownEditorTextView.configureAppearance()` still attempts
`UIFont(name: "SFMono-Regular", size: 17)` first, in case a future iOS version
exposes the named SF Mono face to apps. The fallback to `monospacedSystemFont`
is the production path on current iOS and is correct per Apple's documented
SF Mono access API.

**Reference:** The spec tests in `features/native-polish-6/tests/BehavioralTests.swift`
(NP-1 suite) carry the original literal-string assertion as reference; the
Xcode tests in `Markus_v3Tests/NativePolish6_SFMonoFontTests.swift` are the
authoritative executable tests and were corrected to reflect the iOS reality
documented here.
