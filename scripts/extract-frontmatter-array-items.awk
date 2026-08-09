function trim(v) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
  return v
}
function strip_quotes(v, first, last) {
  first = substr(v, 1, 1)
  last = substr(v, length(v), 1)
  if (first == "\"" && last == "\"") {
    return substr(v, 2, length(v) - 2)
  }
  if (first == squote && last == squote) {
    v = substr(v, 2, length(v) - 2)
    gsub(squote squote, squote, v)
    return v
  }
  return v
}
function emit_value(v) {
  v = trim(v)
  if (v == "") return
  v = strip_quotes(v)
  if (v != "") print v
}
function parse_flow_array(rest, i, ch, current, quote) {
  rest = trim(rest)
  if (rest !~ /^\[/) return 0
  sub(/^\[/, "", rest)
  sub(/\][[:space:]]*$/, "", rest)
  current = ""
  quote = ""
  for (i = 1; i <= length(rest); i++) {
    ch = substr(rest, i, 1)
    if (quote == "") {
      if (ch == "\"" || ch == squote) {
        quote = ch
        current = current ch
        continue
      }
      if (ch == ",") {
        emit_value(current)
        current = ""
        continue
      }
    } else if (ch == quote && quote == squote && substr(rest, i + 1, 1) == squote) {
      current = current ch squote
      i++
      continue
    } else if (ch == quote) {
      quote = ""
      current = current ch
      continue
    }
    current = current ch
  }
  emit_value(current)
  return 1
}
BEGIN {
  in_fm = 0
  in_arr = 0
  squote = sprintf("%c", 39)
}
NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
in_fm && /^---[[:space:]]*$/ { exit }
in_fm && $0 ~ ("^" key ":[[:space:]]*") {
  rest = $0
  sub("^" key ":[[:space:]]*", "", rest)
  if (parse_flow_array(rest)) exit
  in_arr = 1
  next
}
in_fm && in_arr && /^[[:space:]]+- / {
  line = $0
  sub(/^[[:space:]]+- /, "", line)
  emit_value(line)
  next
}
in_fm && in_arr && /^[^[:space:]]/ { exit }
