#!/usr/bin/env bash

import_adapter_gsd_name() {
  printf '%s\n' gsd
}

import_adapter_gsd_normalize() {
  local source="$1" output="$2" config_version project_name requirements='[]' milestones='[]' phases='[]' plans='[]' decisions='[]' provenance='[]'
  local requirement_line phase_dir phase_name phase_number phase_slug plan_path plan_name plan_title plan_content summary_path phase_plans='[]' phase_status

  [ -d "$source" ] || import_fail "GSD source is not a directory: $source"
  [ -d "$source/phases" ] || import_fail "GSD source is missing phases/: $source"
  import_source_metadata "$source"

  config_version=$(jq -r '.version // empty' "$source/config.json" 2>/dev/null || true)
  project_name=$(import_adapter_read_heading "$source/PROJECT.md")

  if [ -f "$source/PROJECT.md" ] && [ -n "$project_name" ]; then
    provenance=$(jq -c --arg field project.name --arg path PROJECT.md --arg value "$project_name" \
      '. + [{field:$field,source_path:$path,extraction_method:"markdown-heading",value:$value}]' <<< "$provenance")
  fi

  if [ -f "$source/REQUIREMENTS.md" ]; then
    while IFS= read -r requirement_line || [ -n "$requirement_line" ]; do
      if [[ "$requirement_line" =~ ^[[:space:]]*-[[:space:]]+\[([xX[:space:]])\][[:space:]]+([^:]+):[[:space:]]*(.+)$ ]]; then
        local requirement_mark="${BASH_REMATCH[1]}" requirement_id="${BASH_REMATCH[2]}" requirement_text="${BASH_REMATCH[3]}" requirement_status
        if [[ "$requirement_mark" =~ [xX] ]]; then requirement_status=complete; else requirement_status=pending; fi
        requirements=$(jq -c --arg id "$requirement_id" --arg text "$requirement_text" --arg status "$requirement_status" \
          '. + [{id:($id|gsub("^[[:space:]]+|[[:space:]]+$";"")),text:$text,status:$status}]' <<< "$requirements")
        provenance=$(jq -c --arg id "$requirement_id" --arg status "$requirement_status" \
          '. + [{field:("requirements[" + ($id|gsub("^[[:space:]]+|[[:space:]]+$";"")) + "].status"),source_path:"REQUIREMENTS.md",extraction_method:"checkbox",value:$status}]' <<< "$provenance")
      fi
    done < "$source/REQUIREMENTS.md"
  fi

  while IFS= read -r milestone_name || [ -n "$milestone_name" ]; do
    [ -n "$milestone_name" ] || continue
    milestones=$(jq -c --arg name "$milestone_name" '. + [{name:$name}]' <<< "$milestones")
    provenance=$(jq -c --arg name "$milestone_name" --argjson index "$(jq 'length' <<< "$milestones")" \
      '. + [{field:("milestones[" + (($index - 1)|tostring) + "].name"),source_path:"ROADMAP.md",extraction_method:"h2-heading",value:$name}]' <<< "$provenance")
  done < <([ -f "$source/ROADMAP.md" ] && awk '/^##[[:space:]]+/ {sub(/^##[[:space:]]+/, ""); print}' "$source/ROADMAP.md" || true)

  while IFS= read -r phase_dir; do
    [ -n "$phase_dir" ] || continue
    phase_name=$(basename "$phase_dir")
    if [[ "$phase_name" =~ ^([0-9]+)-(.*)$ ]]; then
      phase_number="${BASH_REMATCH[1]}"
      phase_slug="${BASH_REMATCH[2]}"
    else
      phase_number=''
      phase_slug="$phase_name"
    fi
    phase_plans='[]'
    while IFS= read -r plan_path; do
      [ -n "$plan_path" ] || continue
      plan_name=$(basename "$plan_path")
      plan_title=$(import_adapter_read_heading "$plan_path")
      plan_content=$(import_adapter_bounded_content "$plan_path")
      if [[ "$plan_name" =~ ^([0-9]+)-([0-9]+)-PLAN\.md$ ]]; then
        local plan_number="${BASH_REMATCH[2]}"
      else
        plan_number=''
      fi
      summary_path="${plan_path%-PLAN.md}-SUMMARY.md"
      local summary_present=false plan_status=''
      if [ -f "$summary_path" ]; then summary_present=true; plan_status=complete; fi
      local plan_json
      plan_json=$(import_adapter_plan_json "${plan_path#"$source"/}" "$plan_title" "$plan_status" "$plan_content" "$phase_number" "$plan_number" "$summary_present")
      plans=$(jq -c --argjson plan "$plan_json" '. + [$plan]' <<< "$plans")
      phase_plans=$(jq -c --argjson plan "$plan_json" '. + [$plan]' <<< "$phase_plans")
      local plan_index=$(( $(jq 'length' <<< "$plans") - 1 ))
      if [ -n "$plan_title" ]; then
        provenance=$(jq -c --arg field "plans[$plan_index].title" --arg path "${plan_path#"$source"/}" --arg value "$plan_title" \
          '. + [{field:$field,source_path:$path,extraction_method:"markdown-heading",value:$value}]' <<< "$provenance")
      fi
      if [ "$summary_present" = true ]; then
        provenance=$(jq -c --arg field "plans[$plan_index].status" --arg path "${summary_path#"$source"/}" \
          '. + [{field:$field,source_path:$path,extraction_method:"summary-file-presence",value:"complete"}]' <<< "$provenance")
      fi
    done < <(find "$phase_dir" -maxdepth 1 -type f \( -name 'PLAN.md' -o -name '*-PLAN.md' \) -print 2>/dev/null | LC_ALL=C sort)
    if [ "$(jq 'length' <<< "$phase_plans")" -gt 0 ]; then
      if [ "$(jq '[.[] | select(.status == "complete")] | length' <<< "$phase_plans")" -eq "$(jq 'length' <<< "$phase_plans")" ]; then phase_status=complete; else phase_status=''; fi
    else
      phase_status=''
    fi
    local phase_json
    phase_json=$(jq -n --arg slug "$phase_slug" --arg number "$phase_number" --arg status "$phase_status" --argjson phase_plans "$phase_plans" \
      '{number:(if $number == "" then null else ($number|tonumber) end),slug:$slug,status:(if $status == "" then null else $status end),plans:$phase_plans}')
    phases=$(jq -c --argjson phase "$phase_json" '. + [$phase]' <<< "$phases")
    if [ "$phase_status" = complete ]; then
      local phase_index=$(( $(jq 'length' <<< "$phases") - 1 ))
      provenance=$(jq -c --arg field "phases[$phase_index].status" --arg path "${phase_name}" \
        '. + [{field:$field,source_path:("phases/" + $path),extraction_method:"summary-file-presence",value:"complete"}]' <<< "$provenance")
    fi
  done < <(find "$source/phases" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | LC_ALL=C sort)

  if [ -f "$source/STATE.md" ]; then
    while IFS= read -r decision_line || [ -n "$decision_line" ]; do
      [ -n "$decision_line" ] || continue
      decisions=$(jq -c --arg text "$decision_line" '. + [{text:$text}]' <<< "$decisions")
      local decision_index=$(( $(jq 'length' <<< "$decisions") - 1 ))
      provenance=$(jq -c --arg field "decisions[$decision_index].text" \
        '. + [{field:$field,source_path:"STATE.md",extraction_method:"key-decisions-list",value:$text}]' --arg text "$decision_line" <<< "$provenance")
    done < <(awk '
      /^##[[:space:]]+(Key[[:space:]]+)?Decisions[[:space:]]*$/ {inside=1; next}
      inside && /^##[[:space:]]+/ {exit}
      inside && /^[[:space:]]*-[[:space:]]+/ {sub(/^[[:space:]]*-[[:space:]]+/, ""); if ($0 != "_(No decisions yet)_") print}
    ' "$source/STATE.md")
  fi

  jq -n \
    --arg system gsd --arg trust verified-adapter --arg root .planning --arg digest "$SOURCE_DIGEST" \
    --arg gsd_version "$config_version" --arg project_name "$project_name" \
    --argjson requirements "$requirements" --argjson milestones "$milestones" --argjson phases "$phases" \
    --argjson plans "$plans" --argjson decisions "$decisions" --argjson provenance "$provenance" \
    --argjson file_count "$SOURCE_FILE_COUNT" --argjson total_bytes "$SOURCE_TOTAL_BYTES" \
    '{schema_version:1,source:{system:$system,trust_tier:$trust,root:$root,digest:$digest,gsd_version:(if $gsd_version == "" then null else $gsd_version end),file_count:$file_count,total_bytes:$total_bytes},project:{name:(if $project_name == "" then null else $project_name end),description:null},requirements:$requirements,milestones:$milestones,phases:$phases,plans:$plans,decisions:$decisions,warnings:[],conflicts:[],provenance:$provenance}' > "$output"
}
