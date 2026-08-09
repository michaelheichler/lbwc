function skip_ws(   ch) {
  while (pos <= len) {
    ch = substr(txt, pos, 1)
    if (ch ~ /[ \t\r\n]/) {
      pos++
    } else {
      break
    }
  }
}

function parse_string(   ch, out) {
  if (substr(txt, pos, 1) != "\"") {
    parse_failed = 1
    return ""
  }

  pos++
  out = ""
  while (pos <= len) {
    ch = substr(txt, pos, 1)
    if (ch == "\\") {
      out = out ch substr(txt, pos + 1, 1)
      pos += 2
      continue
    }
    if (ch == "\"") {
      pos++
      return out
    }
    out = out ch
    pos++
  }

  parse_failed = 1
  return ""
}

function parse_value(   ch, start, nesting, in_string, escaped) {
  start = pos
  ch = substr(txt, pos, 1)

  if (ch == "\"") {
    pos++
    escaped = 0
    while (pos <= len) {
      ch = substr(txt, pos, 1)
      if (escaped) {
        escaped = 0
        pos++
        continue
      }
      if (ch == "\\") {
        escaped = 1
        pos++
        continue
      }
      if (ch == "\"") {
        pos++
        return substr(txt, start, pos - start)
      }
      pos++
    }
    parse_failed = 1
    return substr(txt, start, pos - start)
  }

  if (ch == "{" || ch == "[") {
    nesting = 1
    in_string = 0
    escaped = 0
    pos++
    while (pos <= len && nesting > 0) {
      ch = substr(txt, pos, 1)
      if (in_string) {
        if (escaped) {
          escaped = 0
        } else if (ch == "\\") {
          escaped = 1
        } else if (ch == "\"") {
          in_string = 0
        }
        pos++
        continue
      }

      if (ch == "\"") {
        in_string = 1
        pos++
        continue
      }

      if (ch == "{" || ch == "[") {
        nesting++
      } else if (ch == "}" || ch == "]") {
        nesting--
      }
      pos++
    }

    if (nesting != 0) {
      parse_failed = 1
    }
    return substr(txt, start, pos - start)
  }

  while (pos <= len) {
    ch = substr(txt, pos, 1)
    if (ch ~ /[ \t\r\n,}]/) {
      break
    }
    pos++
  }

  return substr(txt, start, pos - start)
}

{
  txt = txt $0 ORS
}

END {
  len = length(txt)
  pos = 1
  parse_failed = 0

  skip_ws()
  if (substr(txt, pos, 1) != "{") {
    exit 0
  }

  pos++
  while (pos <= len) {
    skip_ws()
    if (substr(txt, pos, 1) == "}") {
      exit 0
    }

    current_key = parse_string()
    if (parse_failed) {
      exit 0
    }

    skip_ws()
    if (substr(txt, pos, 1) != ":") {
      exit 0
    }

    pos++
    skip_ws()
    current_value = parse_value()
    if (parse_failed) {
      exit 0
    }

    if (current_key == target) {
      print current_value
      exit 0
    }

    skip_ws()
    if (substr(txt, pos, 1) == ",") {
      pos++
      continue
    }
    if (substr(txt, pos, 1) == "}") {
      exit 0
    }
    exit 0
  }
}
