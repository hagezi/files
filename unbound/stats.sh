# Requires the bc command: sudo apt install bc

#!/usr/bin/env bash
set -euo pipefail

sudo unbound-control stats_noreset | awk -F= '
/^total\.num\.cachehits=/        { hits   = $2 }
/^total\.num\.cachemiss=/        { miss   = $2 }
/^total\.recursion\.time\.avg=/  { avg    = $2 }
/^total\.recursion\.time\.median=/{ median = $2 }

END {
    total = hits + miss
    hitrate = (total > 0) ? (hits * 100 / total) : 0

    printf "\n=== Cache Stats ===\n"
    printf "Hits:      %s\n", hits + 0
    printf "Misses:    %s\n", miss + 0
    printf "Total:     %s\n", total
    printf "Hit-Rate:  %.2f%%\n", hitrate
    printf "\n=== Recursion Stats ===\n"
    printf "Avg:    %.2fms\n", (avg + 0) * 1000
    printf "Median: %.2fms\n", (median + 0) * 1000
    printf "\n"
}'
