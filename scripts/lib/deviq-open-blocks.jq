group_by(if .id != null then .id else .trigger end)
| map(max_by(.ts))
| map(select(.status == "open"))
| sort_by(.ts)
