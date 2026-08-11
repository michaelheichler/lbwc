# LBWC execution adaptation

This is a behavior-preserving port. The main session owns task contracts, generated-agent admission, mutable planning state, verification persistence, telemetry, git, and user-facing output. A worker may change only the exact paths in its dispatched contract. `scripts/phase-detect.sh`, `scripts/qa-result-gate.sh`, `scripts/write-verification.sh`, `scripts/remediation-round.sh`, and `references/agent-spawn-protocol.md` replace source-specific routing, persistence, and lifecycle authority.

**Phase 3 rule:** an unavailable helper named below is a required Phase 3 dependency, not a command to emulate. The full surrounding guard, evidence, recovery, and output behavior remains mandatory once the helper is supplied. Existing LBWC helpers are the only commands that run today.

Assume `PLUGIN_ROOT` was resolved by `references/execute-protocol.md` before this fragment runs.

**QA skip guard:** Skip QA only when the user supplies an explicit supported skip option or an installed configuration rule explicitly names the selected command scope. Do not skip from workflow effort, task count, generated role, or a docs-only guess. Display `○ QA verification skipped ({reason})` and preserve the absence of a verification artifact. A skipped QA run still cannot proceed to UAT while the detector or known-issue gate reports a blocker.

After the main session persists VERIFICATION.md, run `scripts/qa-result-gate.sh`. Task-contract state, payload validation, the writer, and the deterministic QA gate replace the retired verification-threshold hard gate. Any failure stops before UAT.

**Dev-surfaced issues collection (before spawning QA):**
After all plans are complete (Step 3c verified), collect deviations and pre-existing issues from all SUMMARY.md files. This data is passed to QA in the task description so QA can treat deviations as FAIL checks and persist pre-existing issues in VERIFICATION.md.

```bash
# Collect deviations and pre-existing issues from all SUMMARY.md files
DEV_ISSUES=""
for summary_file in {phase-dir}/*-SUMMARY.md
do
  [ -f "$summary_file" ] || continue
  plan_id=$(basename "$summary_file" | sed 's/-SUMMARY\.md$//')

  # Extract deviations from YAML frontmatter AND the body ## Deviations section.
  # The shared helper merges both sources in stable order, drops placeholder
  # "none" values, and de-duplicates exact duplicates. Frontmatter must not
  # mask body-only deviation detail.
  devs=""
  if [ -f "${PLUGIN_ROOT}/scripts/summary-utils.sh" ]; then
    # shellcheck source=/dev/null
    . "${PLUGIN_ROOT}/scripts/summary-utils.sh"
  fi
  if type extract_summary_deviations >/dev/null 2>&1; then
    devs=$(extract_summary_deviations "$summary_file" 2>/dev/null | awk '
      NF { items = items (items ? "; " : "") $0 }
      END { print items }
    ')
  fi

  # Extract pre-existing issues from canonical SUMMARY.md frontmatter first.
  preex_key_present=false
  awk '
    BEGIN { in_fm=0; found=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit(found ? 0 : 1) }
    in_fm && /^pre_existing_issues:[[:space:]]*/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$summary_file" >/dev/null 2>&1 && preex_key_present=true

  preex=$(summary_extract_frontmatter_array_items "$summary_file" pre_existing_issues | while IFS= read -r issue_json
  do
    [ -n "$issue_json" ] || continue
    printf '%s' "$issue_json" | jq -er '
      select(type == "object")
      | if .file == .test then
          (.test + ": " + .error)
        else
          (.test + " (" + .file + "): " + .error)
        end
    ' 2>/dev/null || true
  done | awk '
    {
      items = items (items ? "; " : "") $0
    }
    END { print items }
  ' 2>/dev/null)

  # Brownfield fallback: extract pre-existing issues from the legacy body section.
  # Only use this when the canonical frontmatter key is absent. If the key is
  # present as `pre_existing_issues: []`, that explicit empty array is the
  # authoritative "no known issues" signal and must suppress stale body text.
  if [ -z "$preex" ] && [ "$preex_key_present" != true ]; then
    preex=$(awk '
      /^## Pre-existing Issues/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / { line=$0; sub(/^- /, "", line); items = items (items ? "; " : "") line }
      END { print items }
    ' "$summary_file" 2>/dev/null)
  fi

  if [ -n "$devs" ]; then
    printf -v _dev_line 'DEVIATIONS (Plan %s): %s\n' "$plan_id" "$devs"
    DEV_ISSUES="${DEV_ISSUES}${_dev_line}"
  fi
  if [ -n "$preex" ]; then
    printf -v _preex_line 'PREEXISTING (Plan %s): %s\n' "$plan_id" "$preex"
    DEV_ISSUES="${DEV_ISSUES}${_preex_line}"
  fi
done
```

If `DEV_ISSUES` is non-empty, include it in the QA task description:
```
Dev-surfaced issues (include in VERIFICATION.md):
${DEV_ISSUES}
DEVIATIONS are plan violations: treat each as a FAIL check.
PREEXISTING items go in the "Pre-existing Issues" section of VERIFICATION.md.
```

**Phase known-issues persistence (before QA):**
After collecting Dev-surfaced pre-existing issues from SUMMARY.md files, persist them to phase state so a later QA session does not forget them:

**Required Phase 3 dependency:** `scripts/track-known-issues.sh sync-summaries` and `promote-todos` are not installed commands. They must backfill root SUMMARY pre-existing issues before an interrupted first QA run and promote unresolved survivors after QA remediation. Until Phase 3 supplies them, preserve the collected issues in the QA brief, do not claim the registry was backfilled, and do not route to UAT without the installed deterministic gate.

The human-readable Discovered Issues block is supplemental. The JSON registry remains the authoritative backlog only after an installed helper writes it.

**Tier resolution:** `config_verification_tier` from `scripts/phase-detect.sh` or an explicit QA command tier selects Quick, Standard, or Deep. An explicit tier wins. More than fifteen requirements or the final shipping phase requires Deep unless a higher-priority explicit policy says otherwise. An explicit QA skip does not make a verification artifact, does not clear known issues, and does not bypass the QA result gate.

**QA context:** `compile-context.sh` is the direct LBWC context boundary. The retired control plane is not part of this flow.

**Context compilation:** When `config_context_compiler=true`, run the installed helper before QA:

```bash
bash "${PLUGIN_ROOT}/scripts/compile-context.sh" {phase} qa {phases_dir}
```

This produces `{phase-dir}/.context-qa.md` with the phase goal, success criteria, requirements, and conventions. If compilation fails, include that failure in the QA brief and proceed with direct PLAN and SUMMARY reads.

Display `◆ Spawning QA agent ({generator model})...` only after contract dispatch. Select remediation scope from detector state before resolving the output path. `next_phase_state=needs_qa_remediation` selects `scripts/remediation-round.sh current "$PHASE_DIR" qa` and its exact `verif_path`. `next_phase_state=needs_uat_remediation` or `needs_reverification` selects `scripts/remediation-round.sh current "$PHASE_DIR" uat` and its exact `verif_path`. A root phase uses `resolve-artifact-path.sh verification`.

The UAT-round path is evidence for its planned Phase 3 validation work only. The current `qa-result-gate.sh` cannot gate it. Do not substitute the QA round path, call the QA gate, or report a UAT-round PASS as routable.

After a QA remediation round is complete, resolve the authoritative verification artifact only with:

```bash
AUTHORITATIVE_VERIFICATION_PATH=$(bash "${PLUGIN_ROOT}/scripts/resolve-verification-path.sh" authoritative "$PHASE_DIR")
```

Do not use the `phase` mode when claiming a post-remediation verification artifact is authoritative. `resolve-verification-path.sh` does not support UAT remediation scope. The UAT-round verification path and deterministic gate are a Phase 3 dependency until a tested UAT-aware resolver and gate exist.

**Per-wave QA:** The source concurrent per-wave QA schedule is a required Phase 3 dependency. LBWC exclusive admission does not permit overlapping a QA grouping with the next build grouping. Preserve the source evidence scope when Phase 3 adds it: a wave QA sees only completed-wave PLAN and SUMMARY artifacts, then final integration QA sees all plans and cross-plan behavior. Each artifact needs its own exact output path.

**Post-build QA:** Current LBWC QA runs after all selected plans are terminal. The brief includes phase context when compiled, every selected PLAN and SUMMARY, Dev-surfaced deviations, pre-existing issues, known-issue context, model settings emitted by the generator, and the resolved verification output path. QA must bootstrap from codebase testing, concerns, and architecture map artifacts when they exist. It runs the configured tier count and returns evidence only.

**QA contract and generator:** The main session creates a read-only command contract before the generator. Use the same exact brief in both calls. The contract has no write allowance.

```bash
CONTRACT_PATH=$(bash "${PLUGIN_ROOT}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "qa-{phase}-{scope}" --command qa --role qa --team solo --job "$QA_BRIEF")
TASK_ID=$(basename "$CONTRACT_PATH" .json)
QA_GENERATOR_OUTPUT=$(bash "${PLUGIN_ROOT}/scripts/agent-generator.sh" qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID")
QA_AGENT_NAME=$(printf '%s\n' "$QA_GENERATOR_OUTPUT" | awk '/^SPAWN_READY / {name=$2} END {print name}')
bash "${PLUGIN_ROOT}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched
```

Read the complete generator output. A missing `SPAWN_READY` name, generator error, stale contract, or dispatch failure stops QA. Use the emitted name as both `subagent_type` and `name`, with the exact model and other supported parameters emitted by the generator. Do not derive model, turns, or reasoning from a static profile.

**Spawn shape:** QA is a read-only solo. It receives no `team_name`, background option, isolation option, worktree cwd, or write allowance. A source true-team QA lifecycle is a required Phase 3 dependency. The LBWC superseder is the solo dispatched contract and manifest closure.

**Contract lifecycle, return, and persistence:** After the spawn guard admits QA, the main session advances the contract from `dispatched` to `running`. At QA return, apply the shared no-tool circuit breaker, then advance `running` to `awaiting_review` before payload validation. Validate result, tier, counters, check rows, plan references, complete `plans_verified`, and pre-existing issue shape. QA does not call the writer. The main session writes the validated payload to the selected root, QA-round, or UAT-round path.

```bash
printf '%s' "$QA_VERDICT_JSON" | bash "${PLUGIN_ROOT}/scripts/write-verification.sh" "$VERIFICATION_PATH"
```

A writer error, invalid payload, failed freshness check, unsupported UAT-round gate, or non-proceeding deterministic gate moves the QA contract from `awaiting_review` to `blocked` and stops execution. Do not hand-author a fallback verification file. Only writer success followed by a successful supported gate may advance `awaiting_review` to `verified`. The main session then syncs known issues and records the observed command result.

The writer and supported deterministic QA gate are the final verification threshold. There is no separate hard-gate call.
