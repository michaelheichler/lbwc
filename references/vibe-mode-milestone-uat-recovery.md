## Main-session Decision Handoffs

Only the main session may call `AskUserQuestion`. Before every confirmation or
checkpoint, follow `references/lbwc-brand-essentials.md`, then call it from the
main session. A worker that reaches a decision boundary returns
`user_decision_required` JSON defined in `references/subagent-contracts.md`. It does not mutate state, claim a todo, or start
the next stage until the main session supplies the response. A declined choice
preserves state and reports the documented Next Up command.

**Guard:** `milestone_uat_issues=true` from phase-detect.sh. Active phases dir is empty/all_done but the latest shipped milestone has unresolved UAT issues.

This mode handles the case where a milestone was archived before UAT issues were resolved (e.g., due to a missing audit gate in older versions).

**Steps:**
1. After milestone-recovery routing is selected, extract milestone UAT issues with this route-local block:
   ```bash
   MILESTONE_UAT_CONTEXT=$(
     SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
     L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"
     P="/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt"
     PD=""
     _PD_START_TS=$(date +%s 2>/dev/null || echo 0)
     _phase_detect_cache_fresh() {
       local m=""
       [ -f "$P" ] || return 1
       m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
       [ -n "$m" ] || return 1
       [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
     }
     _phase_detect_cache_retryable() {
       [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]
     }
     REAL_R=$(cd "$L" 2>/dev/null && pwd -P) || REAL_R=""
     if [ -n "$REAL_R" ]
     then
       bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
     fi
     i=0
     while [ $i -lt 100 ]
     do
       if _phase_detect_cache_fresh
       then
         PD=$(cat "$P")
         break
       fi
       sleep 0.1
       i=$((i+1))
     done
     if _phase_detect_cache_retryable && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]
     then
       LOCK="/tmp/.lbwc-phase-detect-live-${SESSION_KEY}.lock"
       i=0
       while [ $i -lt 100 ]
       do
         if _phase_detect_cache_fresh
         then
           PD=$(cat "$P")
           if ! _phase_detect_cache_retryable
           then
             break
           fi
         fi
         if mkdir "$LOCK" 2>/dev/null
         then
           PTMP="${P}.reader.$$.$RANDOM"
           PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
           if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]
           then
             printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
           fi
           rmdir "$LOCK" 2>/dev/null || true
           break
         fi
         sleep 0.1
         i=$((i+1))
       done
     fi
     [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
     if _phase_detect_cache_retryable
     then
       echo "milestone_extract_unavailable=true"
     elif printf '%s' "$PD" | grep -q '^---MILESTONE_UAT_EXTRACT_START---$'
     then
       printf '%s\n' "$PD" | awk '
         /^---MILESTONE_UAT_EXTRACT_START---$/ {
           found=1
           next
         }
         /^---MILESTONE_UAT_EXTRACT_END---$/ {
           exit
         }
         found {
           print
         }
       '
     else
       MS_UAT=$(printf '%s' "$PD" | grep '^milestone_uat_issues=' | head -1 | cut -d= -f2)
       if [ "$MS_UAT" = "true" ]
       then
         echo "milestone_extract_unavailable=true"
       else
         echo "not_milestone_recovery"
       fi
     fi
   )
   ```
   Each extracted block starts with `milestone_phase_dir=<path>` followed by `extract-uat-issues.sh` output (header line plus issue lines). Do NOT read UAT files from the milestone. All issue data is already in `MILESTONE_UAT_CONTEXT`.
   If `milestone_uat_count` > 1, multiple blocks are present, one per affected phase separated by `---`. If `milestone_uat_count` = 1, a single block is present.
2. Display the unresolved issues to the user with milestone context (milestone slug, affected phase count, severity mix). Then call AskUserQuestion with three options:
   - **"Create remediation phases"** (set `isRecommended` when `milestone_uat_major_or_higher=true`): Create one remediation phase per affected milestone phase. Auto-populate each phase goal from the UAT issue descriptions. Route to Plan mode for the first created phase.
   - **"Start fresh with new work"**: Acknowledge the stale UAT issues, mark them as acknowledged (`.remediated`) so they don't re-trigger archive blocking, then proceed as if all_done. The user can define new work via `/lbwc:vibe` with arguments.
   - **"Not now"**: Skip milestone UAT recovery without marking anything. The unresolved UAT issues will re-trigger on the next `/lbwc:vibe` invocation.
   **`--yolo` exception:** If `--yolo` was passed, skip the AskUserQuestion and auto-select "Create remediation phases" (the recommended action).
3. If the user chooses remediation, create one remediation phase per affected milestone phase via the script:
   ```bash
   IFS='|' read -ra UAT_DIRS <<< "$milestone_uat_phase_dirs"
   for dir in "${UAT_DIRS[@]}"; do
     bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/create-remediation-phase.sh .lbwc-planning "$dir"
   done
   ```
   The script also writes a `.remediated` marker in each source milestone phase dir to prevent re-triggering on future sessions. After creating all phases, write a ROADMAP.md and update STATE.md reflecting the remediation phases.
   **Remediation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "create milestone remediation phases" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Then route to Plan mode for the first phase.
4. If the user chooses start-fresh: persist acknowledgement markers for all affected archived phases before continuing:
   ```bash
   TARGET_PHASE_DIRS="$milestone_uat_phase_dirs"
   if [ -z "$TARGET_PHASE_DIRS" ] && [ "$milestone_uat_phase_dir" != "none" ]; then
     TARGET_PHASE_DIRS="$milestone_uat_phase_dir"
   fi
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/mark-milestone-remediated.sh .lbwc-planning "$TARGET_PHASE_DIRS"
   ```
   **Re-route after marking (NON-NEGOTIABLE):** The pre-computed routing state is now stale because `.remediated` markers changed on-disk state. Re-run phase-detect to discover existing phases or new-work eligibility:
   ```bash
   FRESH_PD=$(bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh 2>/dev/null)
   ```
   **Error guard:** If `FRESH_PD` is empty or contains `phase_detect_error=true`, display "⚠ Phase detection failed after marking milestones. Run `/lbwc:vibe` again." and STOP.
   **Re-trigger guard:** If `FRESH_PD` still shows `milestone_uat_issues=true`, check whether `milestone_uat_slug` from `FRESH_PD` matches the slug that was just processed (the original `milestone_uat_slug` from the pre-computed state). If it matches, the marking failed for this milestone. Display "⚠ Some milestone UAT markers could not be written. Manually create `.remediated` files in the affected phase dirs, then run `/lbwc:vibe`." and STOP (prevents infinite loop). If it does NOT match, a different older milestone has unresolved UAT. Let routing continue (the priority table will handle it, which may route to Milestone UAT Recovery for that other milestone).
   Otherwise, parse all routing variables from `FRESH_PD` (`next_phase_state`, `phase_count`, `config_auto_uat`, `has_unverified_phases`, etc.) and apply the **full priority table above** (priorities 1 to 11) to determine the correct mode. Route inline in the same turn. Key outcomes:

   **Verification and remediation outcomes:**
   - `needs_uat_remediation` → UAT Remediation mode
   - `needs_reverification` → Re-verify mode
   - `milestone_uat_issues=true` (different milestone) → Milestone UAT Recovery mode
   - `needs_verification` → Verify mode (auto_uat)

   **Planning and milestone outcomes:**
   - `needs_discussion` → Discuss mode
   - `needs_plan_and_execute` → Plan + Execute mode
   - `needs_execute` → Execute mode
   - `phase_count=0` → Scope mode
   - `all_done` → Archive mode
   This list is illustrative. Always defer to the full priority table. Do NOT stop and ask "What would you like to build?" when phases already exist.
5. If the user chooses "Not now": display "Skipping milestone UAT recovery. Run `/lbwc:vibe` again when ready to address these issues." and STOP. No `.remediated` markers are written. The unresolved UAT issues will re-trigger on the next `/lbwc:vibe` invocation.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/create-remediation-phase.sh`
- `scripts/ensure-plugin-root-link.sh`
- `scripts/mark-milestone-remediated.sh`
- `scripts/planning-git.sh`
