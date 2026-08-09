#!/usr/bin/env bash

lbwc_hash_path() {
  local root="$1"
  if command -v md5sum &>/dev/null; then
    printf '%s' "$root" | md5sum | cut -c1-8
  elif command -v md5 &>/dev/null; then
    printf '%s' "$root" | md5 -q | cut -c1-8
  else
    printf '%s' "$root" | cksum | cut -d' ' -f1
  fi
}

lbwc_model_cache_source() {
  local bin="${1:-}" pricing="${2:-}" bin_stamp="0:0" pricing_stamp="0:0"
  if [ -n "$bin" ] && [ -f "$bin" ]; then
    bin_stamp="$(stat -f '%m:%z' "$bin" 2>/dev/null || stat -c '%Y:%s' "$bin" 2>/dev/null || echo 0:0)"
  fi
  if [ -f "$pricing" ]; then
    pricing_stamp="$(stat -f '%m:%z' "$pricing" 2>/dev/null || stat -c '%Y:%s' "$pricing" 2>/dev/null || echo 0:0)"
  fi
  printf 'bin:%s:%s:pricing:%s' "${bin:-none}" "$bin_stamp" "$pricing_stamp"
}
