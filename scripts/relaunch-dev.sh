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

# 必须用 Apple Development 稳定签名（同一 Team + bundle id）。
# 若用 ad-hoc（CODE_SIGN_IDENTITY=-），每次编译 CDHash 变化，TCC 日历/辅助功能会当成新 App，要重新授权。
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-444ULG6V8C}"

echo "==> Building ${SCHEME} (team ${DEVELOPMENT_TEAM})"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -derivedDataPath "${DERIVED}" \
  -destination "platform=macOS" \
  build \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development"

BUILT_APP="${DERIVED}/Build/Products/Debug/${APP_NAME}.app"
ENTITLEMENTS="${ROOT}/Ridge/Ridge.entitlements"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "error: built app not found at ${BUILT_APP}" >&2
  exit 1
fi
if [[ ! -f "${ENTITLEMENTS}" ]]; then
  echo "error: entitlements missing at ${ENTITLEMENTS}" >&2
  exit 1
fi

# Automatic 签名会把 calendars 等 entitlement 剥掉，导致授权弹窗无反应；构建后用完整 entitlements 再签一次。
echo "==> Re-signing with full entitlements"
if ! grep -q 'personal-information.calendars' "${ENTITLEMENTS}"; then
  echo "error: ${ENTITLEMENTS} lacks calendars entitlement" >&2
  cat "${ENTITLEMENTS}" >&2 || true
  exit 1
fi
CODESIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [[ -z "${CODESIGN_ID}" ]]; then
  echo "error: no Apple Development identity found" >&2
  exit 1
fi
# 先签主可执行文件，再签 bundle（避免空 entitlements 被嵌进 Mach-O）。
MAIN_BIN="${BUILT_APP}/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime --timestamp=none --generate-entitlement-der \
  --sign "${CODESIGN_ID}" \
  --entitlements "${ENTITLEMENTS}" \
  "${MAIN_BIN}"
if [[ -f "${MAIN_BIN}.debug.dylib" ]]; then
  codesign --force --options runtime --timestamp=none --generate-entitlement-der \
    --sign "${CODESIGN_ID}" \
    --entitlements "${ENTITLEMENTS}" \
    "${MAIN_BIN}.debug.dylib"
fi
codesign --force --options runtime --timestamp=none --generate-entitlement-der \
  --sign "${CODESIGN_ID}" \
  --entitlements "${ENTITLEMENTS}" \
  "${BUILT_APP}"

ENT_DUMP="$(codesign -d --entitlements - "${BUILT_APP}" 2>/dev/null || true)"
if ! printf '%s' "${ENT_DUMP}" | grep -q 'personal-information.calendars'; then
  echo "error: calendars entitlement missing after re-sign" >&2
  printf '%s\n' "${ENT_DUMP}" >&2
  exit 1
fi
echo "==> Entitlements OK (calendars present)"

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
