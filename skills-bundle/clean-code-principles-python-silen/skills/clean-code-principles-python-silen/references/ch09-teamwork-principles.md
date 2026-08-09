# ch09: Teamwork Principles

> When this governs: any time you write code others will read, open or review a PR, decide what "done" means, document a component, choose/wrap a dependency, structure work so a team can develop in parallel, or hand a component off to someone else.

This chapter is process-and-people, not algorithms. As a coding agent you help teamwork through the *design choices* you make: write for the next reader, keep dependencies replaceable, structure code so concurrent work does not collide, and split review labor between machine and human correctly.

## Principle index

- **Use an agile framework**: Plan in small estimated stories, and make all work visible.
- **Define the done**: Agree an explicit, partly-automated checklist for "done".
- **You write code for other people**: Optimize for the next reader, including future you.
- **Avoid technical debt**: Design before coding, keep dependencies swappable, and reserve refactor time.
- **Software component documentation**: Document setup, domain, and design in-repo as Markdown.
- **Code review**: Review what machines cannot find, and gate the rest in CI.
- **Uniform code formatting**: Enforce one format with a tool, and never hand-format.
- **Highly concurrent development**: Structure code so each person edits different files.
- **Pair programming**: Pair to spread skill and catch design/bugs early. It is optional, not mandatory.
- **Well-defined team roles**: Give each member a clear specialty, not a jack-of-all-trades.
- **Competence transfer**: Hand off by demoing, explaining design, and proving the README.

## Principles

### Use an agile framework

- **Rule:** Plan features into small, estimated user stories, and make every kind of work visible.
- **Why:** Without a shared way of working, frequent team churn leaves no common process and estimates drift. Small estimated stories with a modified Fibonacci scale (1,2,3,5,8,13,…) acknowledge that estimation accuracy drops as work grows, and reserving explicit time for learning and refactoring keeps plans honest.
- **Python:** Mostly process, but the agent-facing piece is keeping work visible in code. A repo-level `TODO.md` or a `# TODO(story-1234): ...` marker turns "I'll refactor later" into a tracked item a linter can find.
  ```python
  # ✗ invisible debt: a vague comment nobody will ever act on
  # this is hacky, fix sometime

  # ✓ visible, greppable, tied to a backlog item
  # TODO(JIRA-482): replace linear scan with index once dataset > 10k rows
  ```
- **Anti-slop:** Do not invent precise hour/day estimates or sprint commitments for a user. You have no velocity data. Surface the *unknowns*, not fake numbers.

### Define the done

- **Rule:** Agree an explicit definition of done and automate every part of it that a machine can check.
- **Why:** Without a shared bar, quality varies per developer and per PR. The cheap half (formatting, lint, type-check, coverage, SAST, dependency CVEs) belongs in CI so humans never argue about it. The rest (design, docs, tests-as-spec) is the review's job.
- **Python:** A done-gate as a script the CI runs and a human can run locally:
  ```python
  # done_gate stages (each fails the pipeline on nonzero exit):
  #   ruff format --check .
  #   ruff check .
  #   mypy --strict src/
  #   pytest --cov=src --cov-fail-under=80
  #   pip-audit            # 3rd-party CVE scan
  ```
- **See also:** ```examples/teamwork-principles/pr_checklist.md``` (the machine-gate vs human-review split).
- **Anti-slop:** Do not claim a change is "done"/"production-ready"/"fully tested" without naming the checks that actually ran. Unverified completion claims are the canonical LLM failure here.

### You write code for other people

- **Rule:** Write for the next human reader, including yourself in two years, not for the interpreter.
- **Why:** Code is read far more often than written. One function may be read by many developers over many years. Every WTF/re-read/doubt while reading is a readability defect. A clear name and a contract-stating docstring cost minutes, but a cryptic one costs every future reader.
- **Python:** State the *contract* (when to call, what it guarantees, how it fails), not a paraphrase of the body.
  ```python
  # ✗ docstring restates the code, signature hides intent
  def proc(p, r):
      "refunds the payment"   # noqa (says nothing the body doesn't)

  # ✓ named types, named exception, contract in the docstring
  def refund(payment: Payment, requested: Decimal) -> Payment:
      """Add `requested` to the cumulative refund, raise RefundError on over-refund."""
  ```
- **See also:** ```examples/teamwork-principles/documented_function.py```, fluent-python ch08 (type hints), ch11 (a pythonic object).
- **Anti-slop:** Do not emit docstrings that restate the function name ("This function gets the user"), nor single-letter params on public APIs. The docstring earns its place only by adding contract/intent the signature cannot.

### Avoid technical debt

- **Rule:** Do domain + OO design before coding, keep 3rd-party components replaceable, and reserve refactor time.
- **Why:** Debt is the future rework you take on by choosing the quick path. The top causes are skipping design, not engaging senior devs, leaking vendor specifics into business logic (custom SQL, raw SDK calls), no tests (so refactoring is unsafe), and duplicate code. Each compounds: the longer it sits, the more code depends on the shortcut.
- **Python:** Put a Protocol seam between your logic and any vendor SDK, and inject the adapter.
  ```python
  # ✗ business logic married to boto3 (swapping clouds touches every call site)
  def archive(report_id: str, body: bytes) -> None:
      boto3.client("s3").put_object(Bucket="prod", Key=report_id, Body=body)

  # ✓ logic depends on a Protocol your team owns, vendor lives in one adapter
  def archive(store: ObjectStore, report_id: str, body: bytes) -> str:
      key = f"reports/{report_id}.bin"
      store.put(key, body)
      return key
  ```
- **See also:** ```examples/teamwork-principles/replaceable_dependency.py``` (adapter + DI), ```examples/teamwork-principles/open_closed_plugin.py``` (extend without editing), fluent-python ch08/ch13 (Protocols/ABCs), ch10 (patterns with first-class functions).
- **Anti-slop:** Do not reach for the newest/niche library by reflex, and do not inline a vendor SDK directly into domain code. Prefer mature, established dependencies and wrap them.

### Software component documentation

- **Rule:** Document setup, problem domain, and OO design in-repo as Markdown so newcomers onboard fast.
- **Why:** The main payoff of docs is onboarding speed. Docs that live beside the code stay in sync and version together. A wiki rots. Split into `README.md` + a `docs/` directory so simultaneous edits do not collide in one giant file.
- **Python:** Keep the doc set minimal and high-signal: purpose, architecture/data-flow, per-subdomain design diagrams (not one mega class diagram), how to set up the dev env, build, run unit/integration tests, deploy, config (env vars/files/secrets), and observability (log levels, metrics/SLIs, SLOs, alerts). Auto-generate API docs from source where possible.
- **Anti-slop:** Do not generate a single class diagram for a whole service, and do not write docs that duplicate facts already in code or Gherkin files. Link instead. Avoid filler "Overview" sections that repeat the title.

### Code review

- **Rule:** In review, focus on what a machine cannot find, and gate the machine-findable stuff in CI first.
- **Why:** Reviewer attention is scarce. Formatting, lint, type errors and many bugs are found by tools and tests, so spending human review on them wastes the chance to catch design flaws, missing test cases, and bad names, exactly the issues that are expensive later. You cannot review your own code. At least one reviewer should be senior/lead.
- **Python:** Concretely, in review focus on: OO design and subdomain boundaries, tests-as-spec (read tests first: is each error/security/edge path covered?), naming, readability, replaceability, and malicious-code detection. Do *not* raise premature optimization unless the PR's goal is optimization.
  ```python
  # Review starts with the test, asking "what's NOT here?"
  def test_refund_rejects_over_refund() -> None:   # error path covered ✓
      with pytest.raises(RefundError):
          refund(Payment(Decimal("100"), Decimal("80")), Decimal("30"))
  # missing? negative amount, zero amount, currency mismatch: flag those
  ```
- **See also:** ```examples/teamwork-principles/pr_checklist.md```.
- **Anti-slop:** Do not pad reviews with nitpicks a formatter already handles, and do not suggest micro-optimizations on non-optimization PRs. Lead with design/test-coverage/naming.

### Uniform code formatting

- **Rule:** Pick one formatter, enforce it in CI, and never format by hand.
- **Why:** If members format differently, one small edit can reformat a whole file and hand a teammate a massive, meaningless merge conflict that stalls delivery. A single enforced formatter makes diffs reflect real changes only.
- **Python:** Use `ruff format` (or Black) plus `ruff check`, pinned in CI and a pre-commit hook so formatting is decided, not debated.
  ```toml
  # pyproject.toml: one source of truth, no per-developer style
  [tool.ruff]
  line-length = 88
  [tool.ruff.format]
  quote-style = "double"
  ```
- **Anti-slop:** Do not invent a bespoke style or reformat unrelated lines in a diff. Apply the project's configured formatter and leave untouched lines untouched.

### Highly concurrent development

- **Rule:** Structure code so each person primarily edits different files, and design out merge conflicts.
- **Why:** Conflicts arise when several people change the *same* files. Resolving them is slow and error-prone. The structural fixes are: small microservices/microlibraries owned by one person, a large service split into subdomains (one directory each) with rotating ownership, and following SRP + open-closed so new behavior lands in *new* files rather than edits to shared ones.
- **Python:** A registry keyed on a Protocol lets each new format/handler be a new file. The dispatcher is append-only, so two developers adding two formats never touch the same lines.
  ```python
  # ✗ every new format edits this shared function -> conflict magnet
  def export(fmt, rows):
      if fmt == "csv":  ...
      elif fmt == "tsv": ...   # dev A and dev B both edit here

  # ✓ each format registers itself from its own module, dispatcher untouched
  @register
  class CsvExporter: ...
  ```
- **See also:** ```examples/teamwork-principles/open_closed_plugin.py```, fluent-python ch13 (Protocols), ch10 (registration patterns).
- **Anti-slop:** When extending behavior, do not grow a long `if/elif`/`match` dispatcher in a shared file. Prefer a registry/plugin seam so additions are new files.

### Pair programming

- **Rule:** Pair to spread skill and catch design flaws and bugs early, but treat it as optional, per-person.
- **Why:** Four eyes find more design problems and bugs sooner, and a junior paired with a senior onboards far faster. It costs some throughput but usually yields better design, fewer bugs, and better tests. It is not one-size-fits-all. Chemistry between the pair matters.
- **Python:** No code artifact. As an agent, the analog is *narrate your reasoning* and propose alternatives so the human can play navigator. Surface the design choice rather than silently committing one path.
- **Anti-slop:** Do not assert pair programming must always be used or is always worth it. Present it as a context-dependent tradeoff.

### Well-defined team roles

- **Rule:** Give each team member a clear focus area instead of expecting everyone to do everything.
- **Why:** No one is a jack of all trades. Teams do best with specialists (PO, scrum master, dev at junior/medior/senior/lead, test-automation dev, DevOps, UI designer) and a deliberate seniority mix so knowledge flows both ways. Diffuse responsibility produces slower, lower-quality work.
- **Python:** The agent-relevant slice: respect the boundary of the role you are acting in. Test-automation work (Behave/Robot/pytest, JMeter) and DevOps work (CI/CD, IaC) are distinct from feature code. Keep them in their own modules/dirs and do not smear infra concerns into business logic.
- **Anti-slop:** Do not assume "the developer also writes the pipeline, the dashboards, and the UI design." When a task spans roles, name the boundary rather than silently doing all of it half-well.

### Competence transfer

- **Rule:** Hand off a component by demoing it, explaining its design, and *proving* the README end-to-end.
- **Why:** When the owner leaves, the receiver often knows little. A real transfer covers: a feature demo, architecture and OO design (subdomains, major interfaces/classes), key implementation decisions (algorithms, concurrency, error handling, security, performance), config, and crucially *following the README to set up, build, test, and deploy*, which simultaneously verifies the docs are correct and current.
- **Python:** The executable form of "prove the README" is a setup/smoke script that fails loudly when docs drift:
  ```python
  # scripts/verify_onboarding.py: run during handoff, nonzero exit = stale docs
  #   1. fresh venv from documented steps
  #   2. build + `pytest` (unit) + integration tests
  #   3. deploy to a test env per README
  # If any step needs an undocumented manual fix, the README is wrong. Fix the README.
  ```
- **Anti-slop:** Do not assume the README is correct because it exists. Treat onboarding docs as code: executable and verified, not trusted on faith.

## Anti-slop checklist

- No unverified completion claims ("done", "production-ready", "fully tested"). Name the checks that actually ran.
- No fabricated time/story-point estimates or sprint commitments. Surface unknowns instead.
- Docstrings must add contract/intent (when/guarantees/raises), never restate the function name or body.
- No single-letter params on public APIs. Fully type-hint public signatures.
- Never inline a vendor SDK into business logic. Wrap it behind a team-owned Protocol/adapter and inject it.
- Do not reach for the newest/niche dependency by reflex. Prefer mature, established ones and keep them replaceable.
- Extend via registry/plugin seams, not by growing a shared `if/elif`/`match` dispatcher (merge-conflict magnet).
- Don't hand-format or reformat unrelated lines. Rely on the configured formatter (`ruff format`/Black).
- In review feedback, lead with design, test-coverage gaps, and naming, not formatting nitpicks or premature optimization.
- Don't generate one giant class diagram for a whole service. Document per subdomain and link, don't duplicate.
- Don't assume one role does everything. Name role boundaries when a task spans them.
- Treat onboarding docs as executable and verifiable, not trusted on faith.

## Bundled examples

| File | Principle(s) demonstrated |
| --- | --- |
| `examples/teamwork-principles/documented_function.py` | You write code for other people, software component documentation |
| `examples/teamwork-principles/open_closed_plugin.py` | Highly concurrent development, open-closed, avoid technical debt |
| `examples/teamwork-principles/replaceable_dependency.py` | Avoid technical debt (adapter pattern + DI for replaceable dependencies) |
| `examples/teamwork-principles/pr_checklist.md` | Code review, define the done (machine-gate vs human-review split) |
