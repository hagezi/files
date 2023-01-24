#!/bin/bash

# Description : Exports the domains blocked by AdGuard Home with the number of blockings.
# Parameter $1: AdGuard Home workdir data directory in which the querylog.json is located (sudo find / -name querylog.json)
# Example: ./adguardBlocked.sh docker/adguardhome/workdir/data/
# Requires: jq (sudo apt insatll jq)

jq -r '. | select(.Result.IsFiltered==true) | [.QH] | @csv' $1/querylog.json | sed 's/"//g'| sort | uniq -c | sort -nr -k1
