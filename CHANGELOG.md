# Changelog

This file records user-visible LBWC releases. Keep the newest entry first.

## [1.0.0] - 2026-08-09

### Added

- Shell-issued worker contracts, protected execution boundaries, and main-session telemetry.
- A local RTK lifecycle manager with checksummed project-local installs and read-only Claude Code smoke checks.
- Release verification that requires synchronized version metadata and a changelog entry before publication.
- Claude Code marketplace catalog for `claude plugin marketplace add michaelheichler/lbwc` and `claude plugin install lbwc@lbwc-marketplace`.
- Installation and update instructions for user, project, and local marketplace checks.

### Changed

- LBWC now treats generated agents as untrusted workers. The main session remains the only Git and release actor.
