#!/usr/bin/env bash
# 编译 → 杀光旧 Ridge → ditto 覆盖 /Applications/Ridge.app → 只开这一份
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Ridge"
INSTALL_APP="/Applications/${APP_NAME}.app"
DERIVED="${ROOT}/build/DerivedData"
SCHEME="${APP_NAME}"

cd "$ROOT"

if [[ -f project.yml ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
  else
    echo "error: xcodegen not found; install with: brew install xcodegen" >&2
    exit 1
  fi
fi

echo "==> Building ${SCHEME}"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -derivedDataPath "${DERIVED}" \
  -destination "platform=macOS" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO

BUILT_APP="${DERIVED}/Build/Products/Debug/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "error: built app not found at ${BUILT_APP}" >&2
  exit 1
fi

echo "==> Quitting existing ${APP_NAME}"
pkill -x "${APP_NAME}" 2>/dev/null || true
# 等进程退出
for _ in $(seq 1 20); do
  if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  pkill -9 -x "${APP_NAME}" 2>/dev/null || true
  sleep 0.2
fi

echo "==> Installing to ${INSTALL_APP}"
mkdir -p "$(dirname "${INSTALL_APP}")"
ditto "${BUILT_APP}" "${INSTALL_APP}"

echo "==> Opening ${INSTALL_APP}"
open "${INSTALL_APP}"

sleep 0.4
COUNT="$(pgrep -x "${APP_NAME}" | wc -l | tr -d ' ')"
PATHS="$(ps -axo pid=,command= | grep "/${APP_NAME}.app/" | grep -v grep || true)"
echo "==> Running processes (${COUNT}):"
echo "${PATHS:-"(none)"}"
if [[ "${COUNT}" != "1" ]]; then
  echo "warn: expected exactly one ${APP_NAME} process" >&2
fi
echo "Done. Installed at ${INSTALL_APP}"
