# Tests

bats-core is the test harness for all new `.bats` coverage in this repo, mirroring the convention documented in VBW's `testing/README.md` and `.github/workflows/ci.yml` (VBW's CI installs it via `git clone --depth 1 --branch <tag> https://github.com/bats-core/bats-core.git && sudo install.sh /usr/local`). Locally, `brew install bats-core` on macOS or the `bats` npm package are the standard equivalents.

Install locally with one of:

- `brew install bats-core`
- `npm install -g bats`

Then run a `.bats` file directly: `bats tests/some-thing.bats`.

## What stays as-is

- `tests/self-check.sh` and `scripts/tests/agent-generator-core.sh` are hand-rolled pass/fail scripts. They are not being ported to bats in this pass and keep working exactly as they do today (`bash tests/self-check.sh`, `bash scripts/tests/agent-generator-core.sh`).

## What's new

New test coverage for transferred or newly hardened scripts should be written as `.bats` files under `tests/`, not as additional hand-rolled shell scripts. This keeps future coverage on one harness instead of two.
