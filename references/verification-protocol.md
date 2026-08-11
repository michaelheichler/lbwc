# LBWC execution adaptation

This is a behavior-preserving port. The main session owns task contracts, generated-agent admission, mutable planning state, verification persistence, telemetry, git, and user-facing output. A worker may change only the exact paths in its dispatched contract. `scripts/phase-detect.sh`, `scripts/qa-result-gate.sh`, `scripts/write-verification.sh`, `scripts/remediation-round.sh`, and `references/agent-spawn-protocol.md` replace source-specific routing, persistence, and lifecycle authority.

**Phase 3 rule:** an unavailable helper named below is a required Phase 3 dependency, not a command to emulate. The full surrounding guard, evidence, recovery, and output behavior remains mandatory once the helper is supplied. Existing LBWC helpers are the only commands that run today.

# LBWC Verification Protocol

Authoritative spec for the LBWC verification pipeline. QA returns structured evidence only. The main session validates that evidence and persists `VERIFICATION.md` with `scripts/write-verification.sh`.

## 1. Contexts

- **Post-build:** Automatic after `/lbwc:vibe` execute mode unless an explicit `--skip-qa` option or installed configuration rule applies
- **On-demand:** Triggered by `/lbwc:vibe`, `/lbwc:debug`, or the hidden internal `/lbwc:qa` protocol command

## 1.5 Known-Issues Lifecycle (VRFY-KI)

- The phase-scoped registry is `{phase-dir}/known-issues.json`.
- Dev/execute-discovered pre-existing issues are persisted there during normal phase execution.
- QA still writes `VERIFICATION.md` first. Only **after** `write-verification.sh` succeeds should the orchestrator sync `pre_existing_issues` from that artifact into the registry.
- Phase-level `VERIFICATION.md` merges new known issues into the registry without clearing execution-time issues.
- Round-scoped remediation verification (`R{RR}-VERIFICATION.md`) is authoritative for unresolved known issues and may prune or clear the registry.
- Known issues do **not** directly change QA PASS/FAIL/PARTIAL verdict semantics, they change lifecycle routing through `qa-result-gate.sh`.
- UAT must not proceed while unresolved entries remain in `{phase-dir}/known-issues.json`.

## 2. Three-Tier Verification (VRFY-01)

### Quick (5-10 checks)
- Artifact existence: each `must_haves.artifacts` path exists
- Frontmatter validity: YAML parses, required fields present
- Key string presence: each `contains` value found via grep
- No placeholder text: no `{placeholder}`, `TBD`, `Phase N` stubs

### Standard (15-25 checks)
Quick, plus:
- Content structure: expected sections/headings present
- Key link verification: each `must_haves.key_links` confirmed via grep
- Import/export chain: referenced files exist, cross-refs resolve
- Frontmatter cross-consistency: field values align across related artifacts
- Line count thresholds: files meet minimum size for type
- Convention compliance: check against `CONVENTIONS.md` if it exists (see §5 / VRFY-06)
- Skill-augmented checks: domain-specific checks from installed quality skills

### Deep (30+ checks)
Standard, plus:
- Anti-pattern scan (see §6 / VRFY-07)
- Requirement-to-artifact mapping (see §7 / VRFY-08)
- Cross-file consistency: shared constants/enums/types match everywhere
- Detailed convention verification: every new/modified file checked
- Skill-augmented deep checks: thorough domain-specific verification
- Completeness audit: no partial implementations, no untracked TODO/FIXME

## 3. Auto-Selection Heuristic (VRFY-01)

**LBWC superseder:** the command supplies an explicit tier or reads `config_verification_tier` from the detector output. A generated name, model, reasoning setting, or workflow effort never selects verification scope.

| Evidence | Tier |
|----------|------|
| Explicit command tier | Explicit tier |
| Configured verification tier | Configured tier |
| Debug or standalone QA without an explicit tier | Standard |
| More than fifteen requirements or final shipping phase | Deep, unless an explicit higher-priority policy says otherwise |
| Explicit QA skip policy | Skipped, but never while unresolved known issues block UAT |

Precedence is explicit tier, then command context policy, then configuration, then Standard default. A skip leaves no fake verification artifact and cannot override the deterministic known-issue gate.

## 4. Goal-Backward Methodology (VRFY-02)

Start from desired outcomes, derive testable conditions, verify against artifacts. Catches code that exists but doesn't fulfill its purpose.

1. **State goal:** Extract objective from plan + phase success criteria from ROADMAP.md
2. **Derive truths:** Each entry in `must_haves.truths` must be verifiably true in the codebase.
3. **Verify at three levels:**
   - **Truth checks:** Observable condition per truth. Execute (grep/read/match). PASS/FAIL/PARTIAL with evidence
   - **Artifact checks:** File exists at `path`, contains each `contains` string, provides declared capability
   - **Key link checks:** `from` file references `to` file, pattern matches `via`
4. **Classify:** Each check gets PASS/FAIL/PARTIAL with file paths, line numbers, grep output

## 5. Convention Verification (VRFY-06)

Active when `.lbwc-planning/codebase/CONVENTIONS.md` exists. Silently skipped otherwise.

| Tier | Behavior |
|------|----------|
| Quick | Skipped |
| Standard | Spot-check naming patterns + file placement for new files |
| Deep | Systematic: every new file vs naming, every modified file vs conventions, code patterns vs documented idioms |

Categories: naming patterns, file placement, import ordering, export patterns.

## 6. Anti-Pattern Scanning (VRFY-07)

| Anti-Pattern | Detection | Severity | Tier |
|---|---|---|---|
| TODO/FIXME without tracking | `grep -rn "TODO\|FIXME"` not linked to tracker | WARN | Deep |
| Placeholder text | `{placeholder}`, `TBD`, `Phase N` stubs, `lorem ipsum` | FAIL | Standard+ |
| Empty function bodies | Functions with no implementation | FAIL | Deep |
| Generic reasoning filler | Empty exhortations in agent, reference, or command files | FAIL | Standard+ |
| Unwired code | Exported symbols never imported elsewhere | WARN | Deep |
| Dead imports | Imported symbols never used | WARN | Deep |
| Hardcoded secrets | Known credential prefixes and password or secret assignments | FAIL | Standard+ |

Severities: FAIL = must fix before ship. WARN = review, may be intentional.

Notes: placeholder detection excludes template files, filler detection applies to agent/ref/command files only, secret detection uses pattern matching (known prefixes + common patterns).

## 7. Requirement Mapping (VRFY-08)

Deep tier only. Traces requirement IDs to implementing artifacts.

1. **Extract** requirement IDs from phase section of ROADMAP.md
2. **Trace** each ID to PLAN.md files (must_haves, task descriptions, success criteria) and SUMMARY.md files. Prefer `ac_results` frontmatter when present, fall back to prose sections (What Was Built, Files Modified) for pre-existing summaries.
3. **Classify:** Mapped (plan+summary) = OK. Planned only (plan, no summary) = WARN. Unmapped (neither) = FAIL

Scope: current phase only. Cross-phase requirements noted but not flagged.

## 8. Test Execution Best Practices (VRFY-09)

When running a project's test suite during verification:

- **Capture full output:** Redirect test output to a file (`> /tmp/test-results.txt 2>&1`) rather than piping through `tail` or `head`. Truncated output hides failures that appear early in the run.
- **Search for failures:** After capturing, search the output for failure patterns (`grep -E 'FAIL|ERROR|error:|failed' /tmp/test-results.txt`) to find all failures regardless of position.
- **Report tail for summary:** Display the last 30-50 lines for the summary/statistics, but base your verdict on the full failure search.
- **Clean up:** Remove temp files after verification completes.

## 9. Continuous Verification Hooks (VRFY-03, VRFY-04, VRFY-05)

Protocol instructions in agent definitions (not JS hooks or event handlers).

- **VRFY-03 Worker return:** Run the configured linter or type checker on contract-limited modified files before accepting the handoff.
- **VRFY-04 Main-session commit:** Verify commit format `{type}({scope}): {description}` and stage only task-related files. Generated agents do not commit.
- **VRFY-05 Main-session completion:** Verify SUMMARY.md has required frontmatter (`phase`, `plan`, `status`, `completed`, `pre_existing_issues`) and sections (What Was Built, Files Modified, Deviations). If PLAN has `must_haves`, verify `ac_results` with valid verdicts (`pass`, `fail`, or `partial`). Report issues.

**Caveman review format (conditional):** If `caveman_review` is `true` in config, format verification findings using the review format in `references/caveman-review.md`. Use `L<line>:` prefixes and severity indicators. Standard frontmatter and pass/fail verdicts are unchanged. Caveman format applies only to finding descriptions and comments.

## 9. Output Format

### Frontmatter

```yaml
---
phase: {phase-id}
tier: {quick|standard|deep}
result: {PASS|FAIL|PARTIAL}
passed: {N}
failed: {N}
total: {N}
date: {YYYY-MM-DD}
---
```

### Structure

Check tables use **5-column** or **6-column** format depending on category-specific fields.

**5-column** (must_have, anti_pattern, or fallback): `# | ID | {col} | Status | Evidence`
**6-column** (when category-specific fields present):
- Artifact: `# | ID | Artifact | Exists | Contains | Status`
- Key Link: `# | ID | From | To | Via | Status`
- Requirement: `# | ID | Requirement | Plan Ref | Evidence | Status`
- Convention: `# | ID | Convention | File | Status | Detail`

```markdown
# Verification: Phase {NN}
## Must-Have Checks
| # | ID | Truth/Condition | Status | Evidence |
## Artifact Checks
| # | ID | Artifact | Exists | Contains | Status |
## Key Link Checks
| # | ID | From | To | Via | Status |
## Anti-Pattern Scan (standard+)
| # | ID | Pattern | Status | Evidence |
## Requirement Mapping (deep only)
| # | ID | Requirement | Plan Ref | Evidence | Status |
## Convention Compliance (standard+, if CONVENTIONS.md)
| # | ID | Convention | File | Status | Detail |
## Skill-Augmented Checks (if quality skills)
| # | ID | Skill Check | Status | Evidence |
## Summary
Tier: / Result: / Passed: N/total / Failed: [list]
```

Result classification: PASS = all pass (WARNs OK). PARTIAL = some fail but core verified. FAIL = critical checks fail.
