#!/usr/bin/env bash
set -euo pipefail


base="$(git merge-base HEAD '@{upstream}' 2>/dev/null || echo HEAD~1)"
changed="$(git diff --name-only --diff-filter=ACMR "$base"...HEAD || true)"

specs=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    spec/*_spec.rb)
      [[ -f "$f" ]] && specs+=("$f")
      ;;
    app/*.rb|lib/*.rb)
      candidate="spec/${f#app/}"
      candidate="spec/${candidate#spec/}"     
      candidate="${candidate%.rb}_spec.rb"
      libcandidate="spec/${f%.rb}_spec.rb"
      [[ -f "$candidate" ]] && specs+=("$candidate")
      [[ -f "$libcandidate" && "$libcandidate" != "$candidate" ]] && specs+=("$libcandidate")
      ;;
  esac
done <<< "$changed"

if [[ ${#specs[@]} -eq 0 ]]; then
  echo ""  
else
  printf "%s\n" "${specs[@]}" | sort -u | tr '\n' ' '
fi