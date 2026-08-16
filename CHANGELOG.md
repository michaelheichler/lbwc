# Changelog
This file records user-visible LBWC releases. Keep the newest entry first.
## [1.0.3] - 2026-08-16
### Added
- Option 2 tmux spawn for vibe, build, and team: freeze a runtime snapshot, open schema 3 with matching backend flags, and dispatch bind-file children through `scripts/tmux-spawn-group.sh`.
- Child bus-loop template and native versus tmux execution choice after confirmation. Bind-file identity is the pane identity.
### Changed
- Destack of the tmux runtime already shipped on main. This release wires that runtime into the spawn path rather than leaving operators on native-only Agent calls.
- Interactive smoke rows stay PENDING. Automated coverage cites the spawn driver and command markdown contracts.
## [1.0.1] - 2026-08-11
### Fixed
- `AskUserQuestion` freeform handling no longer depends on a duplicated `Other` label. Any answer that is not a listed option now resolves as freeform in one step, matching the native contract.
- Re-derived the model-selector extraction in `claude-capabilities.sh` against the current Claude Code binary layout, restoring live model detection.
- Restored VBW-parity content that the initial port had summarized away (`report.md`, `research.md`, `config.md`, `map.md`, `debug.md`), and quoted bracketed `argument-hint` frontmatter values that were failing strict plugin validation.
- Removed dead legacy `config/model-profiles.json`, `config/model-pricing.json`, and `config/reasoning-profiles.json`, and the one ShellCheck error plus five warnings across `scripts/`.
### Changed
- A clean install of the plugin now includes command, script, reference, and test files that were missing from earlier 1.0.x checkouts, so the plugin's own commands and hooks can resolve everything they reference.
## [1.0.0] - 2026-08-09
### Added
- Shell-issued worker contracts, protected execution boundaries, and main-session telemetry.
- A local RTK lifecycle manager with checksummed project-local installs and read-only Claude Code smoke checks.
- Release verification that requires synchronized version metadata and a changelog entry before publication.
- Claude Code marketplace catalog for `claude plugin marketplace add michaelheichler/lbwc` and `claude plugin install lbwc@lbwc-marketplace`.
- Installation and update instructions for user, project, and local marketplace checks.
### Changed
- LBWC now treats generated agents as untrusted workers. The main session remains the only Git and release actor.
