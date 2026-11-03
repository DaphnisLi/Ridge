#!/bin/bash
set -euo pipefail
echo "== Ridge process =="
pgrep -lf '/Applications/Ridge.app' || true
echo "== Battery / listening logs (15m) =="
log show --style compact --predicate 'subsystem == "app.daphnis.Ridge"' --last 15m 2>&1 \
  | grep -iE '聆听|listening|Battery|withListening|mode=|ANC|transparency|外设电量|IOBluetooth|raw=' \
  | tail -150
