def native:
  type == "string" and length > 0 and (contains(":") | not);

([( .host_agent_enum // [] )[] | select(native)]) as $native
| if ($native | index("sonnet")) != null then
    "sonnet"
  elif ($native | length) > 0 then
    $native[0]
  else
    ([((.models // [])[].selector) | select(type == "string" and startswith("claude-"))]) as $claude
    | (.agent_model_ids // {}) as $ids
    | ([$claude[] | $ids[.] | select(native)] | first) as $mapped
    | if $mapped != null then $mapped
      elif ($claude | length) > 0 then $claude[0]
      else empty
      end
  end
