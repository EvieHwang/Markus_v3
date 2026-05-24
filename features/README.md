# Features

Artifacts for each feature live in their own folder.

**Naming convention:** `[feature-name]-[number]`
- Numbers are sequential per feature name, used for both ordering and disambiguation.
- Do not overwrite a previous version — create a new numbered folder.

Folders and the artifacts inside them are **populated by skills at runtime** (requirements, design, etc.). Do not pre-create empty placeholder files: several skills detect their pass number or re-run state by checking which artifacts already exist (e.g., `/requirements` checks for `design.md` to know if it's the first or second pass through the loop; `/adversarial` checks for `adversarial-review.md` to know if it's a fresh review or a re-verification). Empty placeholders confuse those checks.
