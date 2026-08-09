# Model PR / Code-Review Checklist (Python)

Demonstrates: **Code Review** + **Define the Done** principles. Drop this in
`.github/pull_request_template.md`. The split is deliberate: a machine handles
the top block so humans spend their attention on the bottom block.

## Automated gate (CI must be green before review, do NOT review by eye)

- [ ] `ruff format --check` and `ruff check` pass (formatting & lint are not human work)
- [ ] `mypy --strict` / `pyright` passes: no new `# type: ignore` without a reason
- [ ] Tests pass, coverage ≥ team threshold (e.g. 80%)
- [ ] Static analysis / SAST: no new blocker/critical/major findings
- [ ] Dependency scan: no new known vulnerabilities (`pip-audit`)

## Human review (what a machine CANNOT find, spend your time here)

- [ ] **Object-oriented design:** subdomain boundaries, interfaces (Protocols/ABCs),
      single responsibility. Design flaws are cheapest to fix now.
- [ ] **Tests as spec:** read the tests first. Is there a test for each error path,
      security case, and edge/corner case, not just the happy path?
- [ ] **Naming:** classes, functions, variables read clearly and consistently.
      Renames are cheap, confusing names compound forever.
- [ ] **Readability:** any WTF / re-read / "what does this do?" moment is a defect
      in the code, not the reader.
- [ ] **Replaceability:** vendor SDKs sit behind an adapter, no DB-specific SQL leaks
      into business logic.
- [ ] **Malicious / dangerous code:** no exfiltration, no `eval`/`exec` on input,
      no unexpected network calls or new opaque dependencies.
- [ ] **Docs updated** if behavior, config, or setup changed (README/docs/).

## Reviewer rules

- You cannot approve your own PR.
- At least one reviewer is senior/lead.
- Do **not** flag premature optimization unless the PR's stated goal is optimization
  (optimize only after measuring).
- A design flaw with no time to fix now -> file a refactoring story, do not silently merge debt.
