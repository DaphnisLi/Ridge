#!/bin/bash
# 项目释放验收演示：6 进程 + 6 容器。
# 进程分布：Ridge×3 / Focal×2 / daphnis-apps×1（覆盖同项目多进程）。
# 容器同分布，带 compose working_dir label 方便归属。
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PY="$(command -v python3)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRV="$ROOT/build/demo-servers"
LOG_DIR="$ROOT/build/ridge-dev-demo"
mkdir -p "$SRV" "$LOG_DIR"

PORTS=(8871 8872 8873 8874 8875 8876)
TAGS=(ridge-a ridge-b ridge-c focal-a focal-b daphnis-a)
DIRS=(
  "$HOME/project/Ridge"
  "$HOME/project/Ridge"
  "$HOME/project/Ridge"
  "$HOME/project/Focal"
  "$HOME/project/Focal"
  "$HOME/project/daphnis-apps"
)

echo "==> Clearing old demo listeners :8871-8876"
pkill -f 'keep-six-procs.sh' 2>/dev/null || true
pkill -f 'build/demo-servers/.*-http.py' 2>/dev/null || true
for port in "${PORTS[@]}"; do
  if old=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null); then
    # shellcheck disable=SC2086
    kill $old 2>/dev/null || true
  fi
done
sleep 0.35

echo "==> Writing process scripts"
for i in 0 1 2 3 4 5; do
  port="${PORTS[$i]}"
  tag="${TAGS[$i]}"
  proj="${DIRS[$i]}"
  cat >"$SRV/${tag}-http.py" <<PY
# ridge-demo project=${proj} tag=${tag}
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
ThreadingHTTPServer(("127.0.0.1", ${port}), SimpleHTTPRequestHandler).serve_forever()
PY
done

cat >"$SRV/keep-six-procs.sh" <<KEEP
#!/bin/bash
set -euo pipefail
PY="$(command -v python3)"
ROOT="$ROOT"
LOG="$LOG_DIR"
SRV="$SRV"
PORTS=(8871 8872 8873 8874 8875 8876)
TAGS=(ridge-a ridge-b ridge-c focal-a focal-b daphnis-a)
DIRS=(
  "$HOME/project/Ridge"
  "$HOME/project/Ridge"
  "$HOME/project/Ridge"
  "$HOME/project/Focal"
  "$HOME/project/Focal"
  "$HOME/project/daphnis-apps"
)
children=()
for i in 0 1 2 3 4 5; do
  port="\${PORTS[\$i]}"; tag="\${TAGS[\$i]}"; proj="\${DIRS[\$i]}"
  work="\$proj"; [[ -d "\$work" ]] || work="\$ROOT"
  ( cd "\$work" && exec "\$PY" "\$SRV/\${tag}-http.py" "\$proj" "\$tag" ) >>"\$LOG/\${tag}.out.log" 2>>"\$LOG/\${tag}.err.log" &
  children+=(\$!)
  echo "proc \$tag pid=\$! port=\$port cwd=\$work"
done
echo "KEEPALIVE procs=\${children[*]}"
while true; do
  alive=0
  for p in "\${children[@]}"; do kill -0 "\$p" 2>/dev/null && alive=\$((alive+1)) || true; done
  echo "\$(date +%H:%M:%S) procs_alive=\$alive/6"
  [[ \$alive -gt 0 ]] || exit 1
  sleep 25
done
KEEP
chmod +x "$SRV/keep-six-procs.sh"

echo "==> Starting 6 processes"
nohup bash "$SRV/keep-six-procs.sh" >"$LOG_DIR/keep-six.out.log" 2>&1 &
echo "keeper_pid=$!"
sleep 1.0

echo "==> Process listen"
lsof -nP -iTCP:8871 -iTCP:8872 -iTCP:8873 -iTCP:8874 -iTCP:8875 -iTCP:8876 -sTCP:LISTEN || true

echo "==> Containers (Colima/Docker)"
if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI missing; skip containers"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  if command -v colima >/dev/null 2>&1; then
    echo "colima start..."
    colima start --cpu 2 --memory 2 --disk 20 || true
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon unavailable; skip containers"
  exit 0
fi

IMG=nginx:alpine
docker image inspect "$IMG" >/dev/null 2>&1 || docker pull "$IMG"

NAMES=(ridge-c1 ridge-c2 ridge-c3 focal-c1 focal-c2 daphnis-c1)
CPORTS=(18081 18082 18083 18084 18085 18086)
CPROJS=(Ridge Ridge Ridge Focal Focal daphnis-apps)
CDIRS=(
  "$HOME/project/Ridge"
  "$HOME/project/Ridge"
  "$HOME/project/Ridge"
  "$HOME/project/Focal"
  "$HOME/project/Focal"
  "$HOME/project/daphnis-apps"
)

docker rm -f ridge-demo-nginx "${NAMES[@]}" 2>/dev/null || true
for i in 0 1 2 3 4 5; do
  name="${NAMES[$i]}"
  port="${CPORTS[$i]}"
  proj="${CPROJS[$i]}"
  dir="${CDIRS[$i]}"
  docker run -d --name "$name" \
    --label com.docker.compose.project="$proj" \
    --label com.docker.compose.project.working_dir="$dir" \
    -p "${port}:80" \
    "$IMG" >/dev/null
  echo "container $name :$port → $proj"
done

echo "==> docker ps"
docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Label "com.docker.compose.project"}}'
echo "demos ready"
