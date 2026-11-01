#!/bin/sh
# usage: npmlockdiff.sh <repo> <revA> <revB>   (needs git + jq; lockfileVersion 2/3 only)
# prints one line per node_modules path whose version changed: "name: old -> new" ("-" = absent)
# tested 2026-11-01 on freelance-automation (bd96ef4~1 bd96ef4: 33 changes)
{ git -C "$1" show "$2:package-lock.json" | jq -c '{r:"a",p:.packages}'
  git -C "$1" show "$3:package-lock.json" | jq -c '{r:"b",p:.packages}'; } |
jq -rs '(.[0].p // {}) as $a | (.[1].p // {}) as $b
  | ($a + $b | keys[]) | select(. != "") as $k
  | select(($a[$k].version) != ($b[$k].version))
  | "\($k | sub(".*node_modules/";"")): \($a[$k].version // "-") -> \($b[$k].version // "-")"' | sort
