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

# SPM 动态库会写入 DerivedData/PackageFrameworks 绝对 rpath，且排在
# @executable_path/../Frameworks 之前；运行时 perl 桥会去加载构建目录。
# 安装前剥掉绝对 PackageFrameworks rpath，强制走 App 内嵌 Frameworks。
strip_packageframeworks_rpaths() {
  local bin="$1"
  [[ -f "${bin}" ]] || return 0
  local rpaths
  rpaths="$(otool -l "${bin}" 2>/dev/null | awk '
    /cmd LC_RPATH/ { want=1; next }
    want && /path / {
      path=$2
      if (path ~ /PackageFrameworks/ && path ~ /^\//) print path
      want=0
    }
  ')"
  [[ -n "${rpaths}" ]] || return 0
  while IFS= read -r rp; do
    [[ -n "${rp}" ]] || continue
    echo "    strip rpath: ${rp}  ←  $(basename "${bin}")"
    install_name_tool -delete_rpath "${rp}" "${bin}" 2>/dev/null || true
  done <<< "${rpaths}"
}

echo "==> Fixing SPM absolute PackageFrameworks rpaths"
while IFS= read -r -d '' macho; do
  strip_packageframeworks_rpaths "${macho}"
done < <(find "${BUILT_APP}/Contents" \( -type f -perm +111 -o -name "*.dylib" \) -print0 2>/dev/null)
# 框架主二进制偶发无 +x，再显式扫一遍 Frameworks。
if [[ -d "${BUILT_APP}/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' fwbin; do
    strip_packageframeworks_rpaths "${fwbin}"
  done < <(find "${BUILT_APP}/Contents/Frameworks" -type f -print0 2>/dev/null)
fi

# actool 偶发打出残缺 AppIcon.icns（缺大尺寸），Dock / Finder 仍显示旧占位图。
# 用 design/AppIcon.icns（iconutil 全尺寸）覆盖后再签。
FULL_ICNS="${ROOT}/design/AppIcon.icns"
if [[ -f "${FULL_ICNS}" ]]; then
  echo "==> Injecting full AppIcon.icns ($(wc -c < "${FULL_ICNS}" | tr -d ' ') bytes)"
  mkdir -p "${BUILT_APP}/Contents/Resources"
  cp "${FULL_ICNS}" "${BUILT_APP}/Contents/Resources/AppIcon.icns"
fi

# 清掉未纳入签名的残留，否则 codesign --verify 报 sealed resource invalid，Launch Services 可能 open 失败。
rm -f "${BUILT_APP}/Contents/MacOS/${APP_NAME}.cstemp"
rm -rf "${BUILT_APP}/Contents/Resources/AppIcon.iconset"

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

# 嵌套 Framework 先签（改过 rpath 后签名已失效），再签主二进制与 bundle。
if [[ -d "${BUILT_APP}/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' fw; do
    echo "    codesign framework: $(basename "${fw}")"
    codesign --force --options runtime --timestamp=none --generate-entitlement-der \
      --sign "${CODESIGN_ID}" \
      "${fw}"
  done < <(find "${BUILT_APP}/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null)
fi

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
if ! printf '%s' "${ENT_DUMP}" | grep -q 'automation.apple-events'; then
  echo "error: apple-events entitlement missing after re-sign" >&2
  printf '%s\n' "${ENT_DUMP}" >&2
  exit 1
fi
echo "==> Entitlements OK (calendars + apple-events present)"

echo "==> Quitting existing ${APP_NAME}"
pkill -x "${APP_NAME}" 2>/dev/null || true
# MediaRemote perl 桥可能在主进程退出后残留，且仍握着旧 DerivedData 路径。
pkill -f "MediaRemoteAdapter_MediaRemoteAdapter.bundle/.*/run.pl" 2>/dev/null || true
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
pkill -9 -f "MediaRemoteAdapter_MediaRemoteAdapter.bundle/.*/run.pl" 2>/dev/null || true

echo "==> Installing to ${INSTALL_APP}"
mkdir -p "$(dirname "${INSTALL_APP}")"
ditto "${BUILT_APP}" "${INSTALL_APP}"
# ditto 会合并保留旧残留；清掉未签名文件，避免 Launch Services / codesign verify 异常。
rm -f "${INSTALL_APP}/Contents/MacOS/${APP_NAME}.cstemp"
rm -rf "${INSTALL_APP}/Contents/Resources/AppIcon.iconset"

# 刷掉系统图标缓存，否则 Dock / Finder 仍可能显示旧 App Icon。
touch "${INSTALL_APP}" "${INSTALL_APP}/Contents/Info.plist" || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_APP}" >/dev/null 2>&1 || true
rm -rf "${HOME}/Library/Caches/com.apple.iconservices.store" "${HOME}/Library/Caches/com.apple.iconservices" 2>/dev/null || true
killall Dock >/dev/null 2>&1 || true

echo "==> Opening ${INSTALL_APP}"
open "${INSTALL_APP}"

# 启动即崩时 0.4s 内仍可能短暂可见；多等一会再验收。
sleep 1.5
# pipefail 下 pgrep 无进程会非 0，不能直接进 $()。
COUNT="$(pgrep -x "${APP_NAME}" 2>/dev/null | wc -l | tr -d ' ' || true)"
COUNT="${COUNT:-0}"
PATHS="$(ps -axo pid=,command= | grep "/${APP_NAME}.app/" | grep -v grep || true)"
echo "==> Running processes (${COUNT}):"
echo "${PATHS:-"(none)"}"
if [[ "${COUNT}" != "1" ]]; then
  echo "error: expected exactly one live ${APP_NAME} process (got ${COUNT}); check Console / DiagnosticReports" >&2
  exit 1
fi
echo "Done. Installed at ${INSTALL_APP}"

# 可选：拉起项目释放验收用的演示进程（Ridge/Focal/daphnis-apps :8871-8873）
if [[ "${RIDGE_START_DEMOS:-}" == "1" ]]; then
  echo "==> Starting project-release demos"
  chmod +x "${ROOT}/scripts/start-project-demos.sh"
  "${ROOT}/scripts/start-project-demos.sh" || true
fi
