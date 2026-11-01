#!/bin/bash
# 清掉演示容器端口残留，并用 launchd 挂起一个左侧可监视进程（:8871）。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/build/ridge-dev-demo"
SRV="$ROOT/build/demo-servers"
PLIST="$ROOT/build/ridge-demo-ridge-a.plist"
LABEL="app.daphnis.ridge.demo.ridge-a"
uid="$(id -u)"
mkdir -p "$LOG_DIR" "$SRV"

echo "==> Stop demo containers"
if docker info >/dev/null 2>&1; then
  docker rm -f ridge-c1 ridge-c2 ridge-c3 focal-c1 focal-c2 daphnis-c1 ridge-demo-nginx 2>/dev/null || true
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
else
  echo "docker unavailable — skip rm"
fi

echo "==> Clear leftover container host ports :18081-18086"
for port in 18081 18082 18083 18084 18085 18086; do
  if pids=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true); then
    if [[ -n "${pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
      echo "killed :$port ($pids)"
    fi
  fi
done

echo "==> Stop other demo listeners :8872-8876 / keep-six"
pkill -f 'keep-six-procs.sh' 2>/dev/null || true
for port in 8872 8873 8874 8875 8876; do
  if pids=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true); then
    if [[ -n "${pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    fi
  fi
done

echo "==> Install LaunchAgent for ridge-a :8871"
cat >"$SRV/ridge-a-http.py" <<'PY'
# ridge-demo project=/Users/daphnis/project/Ridge tag=ridge-a
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
ThreadingHTTPServer(("127.0.0.1", 8871), SimpleHTTPRequestHandler).serve_forever()
PY

if pids=$(lsof -nP -iTCP:8871 -sTCP:LISTEN -t 2>/dev/null || true); then
  if [[ -n "${pids}" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
    sleep 0.2
  fi
fi

PYBIN="$(command -v python3)"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PYBIN}</string>
    <string>${SRV}/ridge-a-http.py</string>
  </array>
  <key>WorkingDirectory</key><string>${ROOT}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>${LOG_DIR}/ridge-a.out.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/ridge-a.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${uid}" "$PLIST"
launchctl enable "gui/${uid}/${LABEL}" 2>/dev/null || true
launchctl kickstart -k "gui/${uid}/${LABEL}"
sleep 0.6

echo "==> Result"
lsof -nP -iTCP:8871 -sTCP:LISTEN || echo "FAIL: :8871 not listening"
lsof -nP -iTCP:18081 -iTCP:18082 -iTCP:18083 -sTCP:LISTEN 2>/dev/null || echo "container ports clear"
echo "done — 控制台左侧找 Ridge / :8871，点监视后结束进程即可测提示"
