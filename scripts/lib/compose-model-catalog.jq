def first_seen:
  reduce .[] as $item ([]; if index($item) == null then . + [$item] else . end);

def parsed_arrays:
  map(select(length > 0) | try fromjson catch null)
  | map(select(. != null and type == "array" and length > 0 and (all(.[]; type == "string" and length > 0))));

(if ($records | length) > 0 then $records[0] else [] end) as $raw
| ([ $raw[].group | select(. != null and . != "") ] | first_seen) as $families
| (if ($families | length) < 2 then 1 else 2 end) as $min_hits
| (
    ($lines | parsed_arrays)
    | map(select((.[0] as $head | $families | index($head)) != null))
    | map(select(
        ([.[] as $member | $families | index($member)] | map(select(. != null)) | length) >= $min_hits
      ))
    | if length == 0 then [] else max_by(length) end
  ) as $extracted
| (if ($extracted | length) > 0 then $extracted else $families end) as $enum
| def host_id($sel; $fam):
    if ($enum | index($sel)) != null then $sel
    elif ($fam != null and $fam != "" and ($enum | index($fam)) != null) then $fam
    else null
    end;
reduce $raw[] as $r ({models: [], agent_model_ids: {}};
  .models += [{selector: $r.selector, label: $r.label, description: $r.description}]
  | (host_id($r.selector; $r.group)) as $hid
  | if $hid != null then .agent_model_ids[$r.selector] = $hid else . end
)
| reduce $enum[] as $member (.;
    if any(.models[]; .selector == $member) then .
    else .models += [{selector: $member, label: $member, description: $member}]
    end
    | .agent_model_ids[$member] = $member
  )
| .host_agent_enum = $enum
