# Agent Instructions

- Do not run builds by default.
- Only run a build when the change is a really big change, such as:
  - Multi-file or cross-module refactors
  - Project/build setting changes
  - Dependency updates
  - Changes that could impact multiple app targets (iOS/tvOS/shared)
- For small or localized edits, skip builds unless the user explicitly asks for one.
