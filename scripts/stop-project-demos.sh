#!/bin/bash
# 卸掉 Ridge 验收用演示进程 / LaunchAgent，避免登录自启占满「运行中进程」。
set -euo pipefail

LABEL_PREFIX="app.daphnis.ridge.demo"
AGENTS_DIR="$HOME/Library/LaunchAgents"
uid="$(id -u)"

echo "==> Bootout + remove LaunchAgents (${LABEL_PREFIX}.*)"
shopt -s nullglob
for plist in "$AGENTS_DIR"/${LABEL_PREFIX}.*.plist; do
  label="$(basename "$plist" .plist)"
  launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
  rm -f "$plist"
  echo "stopped $label"
done
shopt -u nullglob

echo "==> Kill leftover demo python listeners"
pkill -f '/\.ridge-demo(-http\.py|/.*-http\.py)' 2>/dev/null || true
pkill -f 'build/demo-servers/.*-http\.py' 2>/dev/null || true
pkill -f 'keep-six-procs' 2>/dev/null || true

for port in 8871 8872 8873 8874 8875 8876; do
  if pid=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1); then
    kill "$pid" 2>/dev/null || true
    echo "killed :$port pid=$pid"
  fi
done

echo "done"
