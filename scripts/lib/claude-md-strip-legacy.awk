function should_remove_section(    remove_section) {
  remove_section = 0

  if (section_header == "## Active Context" ||
      section_header == "## LBWC Rules" ||
      section_header == "## Code Intelligence" ||
      section_header == "## Plugin Isolation") {
    remove_section = 1
  } else if (section_header == "## State") {
    if (index(section_body, "Planning directory: `.lbwc-planning/`") > 0) {
      remove_section = 1
    }
  } else if (section_header == "## Project Conventions") {
    if (index(section_body, "None yet. Run /lbwc:teach to add project conventions.") > 0 ||
        index(section_body, "These conventions are enforced during planning and verified during QA.") > 0) {
      remove_section = 1
    }
  } else if (section_header == "## Commands") {
    if (index(section_body, "Run /lbwc:status for current progress.") > 0 &&
        index(section_body, "Run /lbwc:help for all available commands.") > 0) {
      remove_section = 1
    }
  }

  return remove_section
}

function fence_length(line, char,    i) {
  i = 1
  while (substr(line, i, 1) == char) {
    i++
  }
  return i - 1
}

function is_fence_line(line,    trimmed, char, run_length) {
  trimmed = line
  sub(/^[[:space:]]*/, "", trimmed)
  char = substr(trimmed, 1, 1)
  if (char != "`" && char != "~") {
    return 0
  }
  run_length = fence_length(trimmed, char)
  if (run_length < 3) {
    return 0
  }
  return run_length >= 3
}

function update_fence(line,    trimmed, char, run_length, remainder) {
  trimmed = line
  sub(/^[[:space:]]*/, "", trimmed)
  char = substr(trimmed, 1, 1)
  run_length = fence_length(trimmed, char)
  remainder = substr(trimmed, run_length + 1)
  if (!in_fence) {
    in_fence = 1
    fence_char = char
    fence_length_active = run_length
  } else if (char == fence_char && run_length >= fence_length_active && remainder !~ /[^[:space:]]/) {
    in_fence = 0
    fence_char = ""
    fence_length_active = 0
  }
}

function flush_section() {
  if (!in_section) {
    return
  }

  if (!should_remove_section()) {
    printf "%s", section_buffer
  }

  in_section = 0
  section_header = ""
  section_buffer = ""
  section_body = ""
}

BEGIN {
  in_fence = 0
  fence_char = ""
  fence_length_active = 0
  in_section = 0
  section_header = ""
  section_buffer = ""
  section_body = ""
}

{
  if (is_fence_line($0)) {
    if (in_section) {
      section_buffer = section_buffer $0 ORS
    } else {
      print
    }
    update_fence($0)
    next
  }

  if (!in_fence && $0 ~ /^##[[:space:]]+/) {
    flush_section()
    in_section = 1
    section_header = $0
    sub(/[[:space:]]+$/, "", section_header)
    section_buffer = $0 ORS
    section_body = ""
    next
  }

  if (in_section) {
    section_buffer = section_buffer $0 ORS
    if (!in_fence) {
      section_body = section_body $0 ORS
    }
  } else {
    print
  }
}

END {
  flush_section()
}
