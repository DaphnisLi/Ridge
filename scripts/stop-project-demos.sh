#!/bin/bash
set -euo pipefail
LABEL_PREFIX="app.daphnis.ridge.demo"
NAMES=(ridge focal daphnis-apps)
AGENTS_DIR="$HOME/Library/LaunchAgents"
uid="$(id -u)"

for name in "${NAMES[@]}"; do
  label="${LABEL_PREFIX}.${name}"
  launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
  rm -f "$AGENTS_DIR/${label}.plist"
  echo "stopped $label"
done

for port in 8871 8872 8873; do
  if pid=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1); then
    kill "$pid" 2>/dev/null || true
  fi
done
echo "done"
