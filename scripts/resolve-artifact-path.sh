#!/bin/bash
set -euo pipefail

TYPE="${1:-}"
PHASE_DIR="${2:-}"
PLAN_NUMBER=""

if [ $# -ge 2 ]; then
  shift 2
else
  shift $#
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --plan-number)
      PLAN_NUMBER="${2:-}"
      shift 2 2>/dev/null || { echo "error: --plan-number requires a value" >&2; exit 1; }
      ;;
    --plan-number=*)
      PLAN_NUMBER="${1#--plan-number=}"
      shift
      ;;
    *)
      echo "error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

case "$TYPE" in
  plan|summary|research|phase-research|context|uat|verification) ;;
  "")
    echo "usage: resolve-artifact-path.sh <type> <phase-dir> [--plan-number MM]" >&2
    exit 1
    ;;
  *)
    echo "error: unknown type: $TYPE (expected: plan, summary, research, phase-research, context, uat, verification)" >&2
    exit 1
    ;;
esac

if [ -z "$PHASE_DIR" ]; then
  echo "error: phase-dir is required" >&2
  exit 1
fi
if [ ! -d "$PHASE_DIR" ]; then
  echo "error: phase-dir does not exist: $PHASE_DIR" >&2
  exit 2
fi

PHASE_DIR="${PHASE_DIR%/}"
_base=$(basename "$PHASE_DIR")
PHASE_NUM=$(echo "$_base" | sed 's/^\([0-9]*\).*/\1/')
if [ -z "$PHASE_NUM" ]; then
  echo "error: cannot extract phase number from directory: $_base" >&2
  exit 1
fi
PHASE_NUM=$(printf "%02d" "$((10#$PHASE_NUM))")

case "$TYPE" in
  phase-research)
    echo "${PHASE_NUM}-RESEARCH.md"
    exit 0
    ;;
  context)
    echo "${PHASE_NUM}-CONTEXT.md"
    exit 0
    ;;
  uat)
    echo "${PHASE_NUM}-UAT.md"
    exit 0
    ;;
  verification)
    echo "${PHASE_NUM}-VERIFICATION.md"
    exit 0
    ;;
esac

if [ -n "${PLAN_NUMBER:-}" ]; then
  case "$PLAN_NUMBER" in
    *[!0-9]*)
      echo "error: --plan-number must be numeric, got: $PLAN_NUMBER" >&2
      exit 1
      ;;
  esac
  if [ "$((10#$PLAN_NUMBER))" -lt 1 ]; then
    echo "error: --plan-number must be >= 1, got: $PLAN_NUMBER" >&2
    exit 1
  fi
fi


next_plan_number() {
  local dir="$1"
  local max_num=0
  local fname num

  for f in "$dir"/*-PLAN.md; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")

    num=$(echo "$fname" | sed -n 's/^[0-9][0-9]*-\([0-9][0-9]*\)-PLAN\.md$/\1/p')

    if [ -z "$num" ]; then
      num=$(echo "$fname" | sed -n 's/^\([0-9][0-9]*\)-PLAN\.md$/\1/p')
    fi

    [ -z "$num" ] && continue
    num=$((10#$num))
    if [ "$num" -gt "$max_num" ]; then
      max_num=$num
    fi
  done

  printf "%02d" $((max_num + 1))
}

case "$TYPE" in
  plan)
    if [ -n "$PLAN_NUMBER" ]; then
      MM=$(printf "%02d" "$((10#$PLAN_NUMBER))")
    else
      MM=$(next_plan_number "$PHASE_DIR")
    fi
    echo "${PHASE_NUM}-${MM}-PLAN.md"
    ;;
  summary)
    if [ -z "$PLAN_NUMBER" ]; then
      echo "error: --plan-number is required for type 'summary'" >&2
      exit 1
    fi
    MM=$(printf "%02d" "$((10#$PLAN_NUMBER))")
    echo "${PHASE_NUM}-${MM}-SUMMARY.md"
    ;;
  research)
    if [ -z "$PLAN_NUMBER" ]; then
      echo "error: --plan-number is required for type 'research'" >&2
      exit 1
    fi
    MM=$(printf "%02d" "$((10#$PLAN_NUMBER))")
    echo "${PHASE_NUM}-${MM}-RESEARCH.md"
    ;;
esac
