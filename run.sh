#!/bin/bash
# Rebuilds and relaunches Floater, replacing any running copy.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -x Floater 2>/dev/null || true
sleep 0.3
open build/Floater.app
echo "Floater is running — look for the timer icon in your menu bar."
