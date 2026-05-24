# Requirements: editor-foundation-4

*Behavioral requirements in testable terms. No implementation detail.*

---

## User stories

### Story 1 — UITextView migration is transparent to the user

As a user editing a markdown file, the raw editing surface looks and behaves exactly as it did before this feature — same monospaced font, same text content, same dirty-state tracking — so the migration is invisible.

**Acceptance criteria**

- AC-1.1: When the user opens a markdown file and switches to raw mode, the editor displays the full raw markdown source with no content loss or mutation.
- AC-1.2: The raw editor uses a monospaced body font, matching the pre-migration appearance.
- AC-1.3: Every keystroke in the raw editor updates the document's in-memory text and marks the document dirty, exactly as before the migration.
- AC-1.4: The autosave behavior (500 ms idle debounce) is unaffected by the migration — edits are saved to disk within the same timing window as the walking skeleton.
- AC-1.5: The eye-icon toolbar button ("Show rendered") is still visible when in raw mode and transitions back to rendered view on tap.
- AC-1.6: No regression in any walking-skeleton acceptance criterion — the editor continues to open, edit, save, and render files from the system document browser.

**Edge cases**

- EC-1.1: A file that is empty displays an empty, focusable editing surface (no placeholder text, no crash, no layout collapse).
- EC-1.2: A file at or above the 500 KB large-file threshold opens directly in raw mode; the editor is fully editable.
- EC-1.3: If the user opens a file that contains Unicode characters (emoji, RTL text, multi-byte sequences), those characters are preserved without corruption through the edit–save cycle.

---

### Story 2 — Rendered → raw mode switch lands near the tapped location

As a user reading a long rendered document, when I tap to enter edit mode, the raw editor scrolls so that the content corresponding to my tap position is visible — I do not land at the top of a long file and have to scroll to find my place.

**Acceptance criteria**

- AC-2.1: When the user taps anywhere on the rendered view to enter raw mode, the raw editor's initial scroll position corresponds to the fractional y-position of the tap point within the rendered scroll content. Specifically: if the tap was at 40% of the rendered content height, the raw editor opens scrolled to approximately 40% of its own content height.
- AC-2.2: The fractional position used is the tap point's y-offset within the rendered scroll view's total content height at the moment of the tap — not the position within the viewport.
- AC-2.3: If the computed fractional position maps to a location within the last viewport-height of the raw content (i.e., not enough content below to fill the screen), the raw editor scrolls as far as possible without over-scrolling past the end.
- AC-2.4: If the tap point cannot be determined (e.g., mode switch triggered programmatically, not by a direct tap), the raw editor opens at the top (fractional position 0).
- AC-2.5: The scroll anchor is applied before the raw editor is visible to the user — there is no visible jump from the top to the target position after the view appears.

**Edge cases**

- EC-2.1: A tap at the very top of the rendered view (fractional y ≈ 0) places the raw editor at the top.
- EC-2.2: A tap at the very bottom of the rendered view (fractional y ≈ 1) places the raw editor at or near the bottom.
- EC-2.3: If the document source is short enough that the raw editor has no scrollable overflow (all content fits on screen), the scroll anchor is ignored and the full document is visible.
- EC-2.4: If the rendered content height is zero (empty document), the raw editor opens at the top with no error.

---

### Story 3 — Raw → rendered mode switch preserves reading position

As a user who has scrolled partway through a long document in the raw editor, when I switch to rendered view, the rendered view shows the section of the document I was looking at — I do not land at the top of a long file.

**Acceptance criteria**

- AC-3.1: When the user switches from raw mode to rendered mode (via the eye-icon toolbar button), the rendered view's initial scroll position corresponds to the fractional scroll position of the raw editor at the moment of the switch. Specifically: if the raw editor was scrolled to 60% of its content height, the rendered view opens scrolled to approximately 60% of its own content height.
- AC-3.2: The fractional position used is the raw editor's scroll content offset y divided by its total content height at the moment the mode switch is triggered.
- AC-3.3: If the computed fractional position maps to a location within the last viewport-height of the rendered content, the rendered view scrolls as far as possible without over-scrolling past the end.
- AC-3.4: The scroll anchor is applied before the rendered view is visible to the user — there is no visible jump from the top to the target position after the view appears.
- AC-3.5: A save is triggered on transition to rendered mode (per walking-skeleton AC-5.2); the scroll anchor is independent of the save and is not blocked by it.

**Edge cases**

- EC-3.1: If the raw editor is at the very top (scroll offset 0), the rendered view opens at the top.
- EC-3.2: If the raw editor is scrolled to the very bottom, the rendered view opens at or near the bottom.
- EC-3.3: If the raw editor has no scrollable overflow (all content fits on screen), the fractional position is treated as 0 and the rendered view opens at the top.
- EC-3.4: If the rendered content height is zero (empty document), the rendered view opens at the top with no error.

**Out of scope for scroll anchoring**

- Heading-based anchor resolution (finding and scrolling to the nearest heading above the tap point) — this is a potential future enhancement, not part of this feature.
- Sub-line precision (character-level scroll target within a paragraph).
- Persistence of scroll position across app backgrounding or document close/reopen.

---

### Story 4 — Smart quotes and dashes are suppressed

As a user writing prose in the raw editor, when I type a straight quote character (`"` or `'`) or two hyphens (`--`), the editor preserves the literal character I typed and does not substitute a curly quote or em-dash — because markdown source must contain the characters the user typed, not OS-substituted typographic variants.

**Acceptance criteria**

- AC-4.1: Typing a double quote character (`"`) in the raw editor inserts a straight double quote (`"`) — the OS typographic substitution ("smart quotes") is suppressed.
- AC-4.2: Typing a single quote or apostrophe character (`'`) in the raw editor inserts a straight single quote (`'`) — the OS smart-quote substitution is suppressed.
- AC-4.3: Typing two hyphens (`--`) in the raw editor inserts two literal hyphens and does not substitute an em-dash (`—`) — the OS smart-dash substitution is suppressed.
- AC-4.4: These suppressions apply everywhere in the document, not just at the start of a word or after a space.
- AC-4.5: Pasting text that already contains curly quotes or em-dashes preserves those characters as-is — suppression applies only to input substitution, not to existing content.

**Edge cases**

- EC-4.1: Typing a sequence like `"hello"` inserts two straight double quotes with the word between them (no substitution of opening/closing curly pairs).
- EC-4.2: Typing `don't` inserts a straight apostrophe in the contraction.

---

### Story 5 — Spell check and autocorrect are active

As a user writing prose in the raw editor, the editor provides real-time spell-check underlining and autocorrect suggestions — because the target user is a prose writer, not a developer, and typo correction is expected iOS editing behavior.

**Acceptance criteria**

- AC-5.1: Misspelled words are underlined with the system spell-check indicator while the user is typing.
- AC-5.2: The autocorrect suggestion bar (QuickType) is active and offers word completions and corrections.
- AC-5.3: Accepting an autocorrect suggestion updates the document text and marks the document dirty.
- AC-5.4: Spell check and autocorrect operate on the natural-language content; they are not disabled by the presence of markdown syntax characters (`#`, `*`, `_`, etc.) in the document.

**Edge cases**

- EC-5.1: A word immediately adjacent to a markdown delimiter (e.g., `**bold**`) may or may not be spell-checked depending on system tokenization behavior — no specific behavior is required; the feature must only ensure the spell-check system is enabled, not override system tokenization.

---

### Story 6 — Unordered list continuation on return

As a user writing a bullet list in the raw editor, when I press Return at the end of a list item, the next line automatically starts with the same list prefix (`- `, `* `, or `+ `) — so I can continue the list without manually typing the prefix.

**Acceptance criteria**

- AC-6.1: When the cursor is at the end of a line that begins with `- ` (hyphen-space), pressing Return inserts a newline followed by `- ` on the new line, placing the cursor after the prefix.
- AC-6.2: When the cursor is at the end of a line that begins with `* ` (asterisk-space), pressing Return inserts a newline followed by `* `.
- AC-6.3: When the cursor is at the end of a line that begins with `+ ` (plus-space), pressing Return inserts a newline followed by `+ `.
- AC-6.4: List continuation applies only when the cursor is at or after the last non-whitespace character on the line — pressing Return mid-line does not trigger continuation.
- AC-6.5: Pressing Return on a line that contains only the list prefix (e.g., `- ` with no other content) removes the prefix and the continuation, inserting a plain newline — this exits the list (the "empty item exits list" convention).
- AC-6.6: The continuation prefix is inserted as a single atomic edit for undo purposes — a single Undo removes both the newline and the continuation prefix, returning the cursor to the end of the preceding list item.

**Edge cases**

- EC-6.1: A line beginning with `  - ` (indented unordered prefix) — list continuation behavior for indented items is out of scope; behavior is unspecified (the feature does not need to preserve or strip the indentation).
- EC-6.2: A line whose first character is a list prefix character but which is not a list item (e.g., `---` horizontal rule, `***` thematic break) — no continuation is triggered because these patterns do not match the `<prefix><space>` form.
- EC-6.3: A line beginning with `- ` followed only by whitespace (e.g., `- ` + spaces) counts as an empty list item and exits the list on Return.

---

### Story 7 — Ordered list continuation on return

As a user writing a numbered list in the raw editor, when I press Return at the end of a numbered list item, the next line automatically starts with the next sequential number followed by `. ` — so I can continue the list without manually numbering.

**Acceptance criteria**

- AC-7.1: When the cursor is at the end of a line that begins with a positive integer followed by `. ` (e.g., `1. `, `3. `, `12. `), pressing Return inserts a newline followed by the next integer and `. `, placing the cursor after the prefix.
- AC-7.2: Auto-increment produces consecutive integers: a line starting with `3. ` produces `4. ` on the next line; a line starting with `99. ` produces `100. `.
- AC-7.3: List continuation applies only when the cursor is at or after the last non-whitespace character on the line (same rule as AC-6.4).
- AC-7.4: Pressing Return on a line that contains only the ordered prefix (e.g., `1. ` with no other content) removes the prefix and inserts a plain newline, exiting the list (same "empty item exits" convention as AC-6.5).
- AC-7.5: The continuation prefix is inserted as a single atomic edit for undo purposes (same rule as AC-6.6).

**Edge cases**

- EC-7.1: A leading zero (e.g., `01. `) — this pattern is not a standard ordered list item; behavior is unspecified. The feature only needs to handle plain positive integers.
- EC-7.2: The number `0` followed by `. ` (i.e., `0. `) — not a valid GFM ordered list item; behavior is unspecified.
- EC-7.3: A line whose integer prefix is immediately followed by `)` instead of `.` (e.g., `1) `) — out of scope; behavior is unspecified.

---

### Story 8 — List continuation does not interfere with non-list content

As a user writing paragraphs or headings in the raw editor, pressing Return always inserts a plain newline — the list continuation logic does not trigger on lines that are not list items.

**Acceptance criteria**

- AC-8.1: Pressing Return at the end of a plain paragraph line inserts a plain newline with no prefix.
- AC-8.2: Pressing Return at the end of a heading line (`# `, `## `, etc.) inserts a plain newline with no prefix.
- AC-8.3: Pressing Return at the end of a fenced code block line (``` ` ```-prefixed or `~`-prefixed) inserts a plain newline with no prefix.
- AC-8.4: Pressing Return on an empty line (no content) inserts a plain newline with no prefix.
- AC-8.5: Pressing Return inside a line (not at the end) inserts a plain newline at the cursor position with no prefix, splitting the line at that point.

---

## Global failure modes and edge cases

- **GF-1 — Undo across list continuation:** The user can undo a list-continuation insert (the auto-inserted newline + prefix) with a single Undo action. Multiple consecutive continuations can each be undone individually.
- **GF-2 — Paste at list position:** Pasting multi-line text onto a list line does not trigger list continuation logic — continuation only fires on a Return key press, not on programmatic text insertion.
- **GF-3 — Very long lines:** A line longer than the viewport width wraps visually; scroll anchoring uses character/content offset, not visual line count, so a very long wrapping line does not distort the fractional position calculation.
- **GF-4 — Mode switch during active text selection:** If the user has an active text selection when switching from raw to rendered mode, the scroll anchor is derived from the visible scroll position at the time of the switch, not from the selection endpoints.
- **GF-5 — Rapid mode switching:** Switching raw → rendered → raw in quick succession does not accumulate scroll error; each transition calculates the anchor from the current state at the moment of the switch.
- **GF-6 — Scroll anchoring with empty document:** Mode switches on an empty document do not crash or produce NaN/infinity fractional values; the anchor defaults to position 0.

---

## Out of scope

- Syntax highlighting or visual formatting in the raw editor.
- Markdown auto-pairing (`**`, `_`, brackets) or auto-completion.
- `Cmd+/` keyboard shortcut.
- Tab / shift-tab list indentation.
- Swipe-to-switch-mode gesture.
- Heading-based scroll anchoring (jump to nearest heading above the anchor point).
- User-configurable toggles for any editor behavior (smart-quote suppression is always on, list continuation is always on, etc.).
- Accessibility labeling pass (Roadmap #7).
- Indented (nested) list continuation.
- Ordered lists using `)` delimiter (`1) item`).

---

Requirements stable — no architectural feedback to incorporate
