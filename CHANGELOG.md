# Changelog
This file records user-visible LBWC releases. Keep the newest entry first.
## [1.0.4] - 2026-08-17

### Teams that follow Claude, and questions you can close

Starting a team now follows your Claude settings and the models this Claude actually offers.

- If Agent Teams is already on, you are not asked again.
- A project setting that turns teams off wins over a personal setting that turns them on.
- A broken extra settings file is skipped. A file you pointed at on purpose still has to be valid.
- Close a choice dialog and work continues. The session is not stuck, and it is not pushed into a review you did not ask for.
- Teammates use the model names this Claude lists, including extra names from a router you installed.
- Starting a team refreshes that list so the short names Claude already uses are accepted.

## [1.0.3] - 2026-08-16

### TMUX agent panes

Run teammates as real Claude sessions in their own tmux panes. Your main session stays the orchestrator: visible, in charge, not taken over.

- Each teammate runs in its own tmux pane as a real Claude session.
- Choose in-process agents or tmux panes. LBWC asks once, or you can save the choice in config.
- The choice freezes for the phase, so it does not flip mid-run.
- Cancel a spawn and it stops. Nothing silently falls back to in-process agents.
- Doctor and status show whether the pane runtime is healthy.
- Pane messaging lets the lead hand off work and collect results.
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
