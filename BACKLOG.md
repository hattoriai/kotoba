# Backlog

Known gaps in Kotoba, each to become an issue.

- Prompts: a label per prompt for the menu's accessible name (for example `prompts={[people: {fun, label: "People in the workshop"}]}`); today the listbox is named "<prompt> suggestions".
- `mix kotoba.install`: compare the package's directory with `Mix.Project.deps_path()`, not `deps/`, so a Hex dependency under a custom deps path (an umbrella child, `MIX_DEPS_PATH`) is not called a path dependency; with a test.
