#!/usr/bin/env bash
# 只跑 docs/REGRESSION_CATALOG.md 中 recurring（occurrences ≥ 2）相关自动化。
# 改完 Ridge 代码后必须执行本脚本（通过后再 relaunch）；occurrences=1 的不必跑。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="${RIDGE_DERIVED_DATA:-$ROOT/build/DerivedData}"
RESULT="${RIDGE_RECURRING_RESULT:-/tmp/ridge-recurring-tests.xcresult}"
LOG="${RIDGE_RECURRING_LOG:-/tmp/ridge-recurring-tests.log}"
rm -rf "$RESULT"

echo "==> Recurring regression tests (RidgeTests)"
echo "    Manifest: RidgeTests/RecurringRegressionManifest.swift"
echo "    Catalog:  docs/REGRESSION_CATALOG.md 「重复出现问题」"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

# 整类跑：RegressionCatalogTests / IslandExpandedPanelPolicyTests / RecurringRegressionCoverageTests
# （类内夹杂的 occurrences=1 用例很轻，一并跑完可接受；新增 recurring 须进 Manifest）
# 用例通过后测试宿主 Ridge 常挂住不退；后台跑并在 Selected tests passed 后收尾。
set +e
xcodebuild test \
  -project Ridge.xcodeproj \
  -scheme Ridge \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULT" \
  -only-testing:RidgeTests/RegressionCatalogTests \
  -only-testing:RidgeTests/IslandExpandedPanelPolicyTests \
  -only-testing:RidgeTests/RecurringRegressionCoverageTests \
  >"$LOG" 2>&1 &
XCODE_PID=$!
set -e

# 最多等 4 分钟；用例本身通常数秒内结束。
DEADLINE=$((SECONDS + 240))
while kill -0 "$XCODE_PID" 2>/dev/null; do
  if rg -q "Test Suite 'Selected tests' passed|TEST FAILED|BUILD FAILED|\*\* TEST FAILED \*\*" "$LOG" 2>/dev/null; then
    sleep 2
    break
  fi
  if (( SECONDS >= DEADLINE )); then
    echo "error: recurring tests timed out waiting for xcodebuild. Log: $LOG" >&2
    kill "$XCODE_PID" 2>/dev/null || true
    pkill -x Ridge 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

# 收尾：杀仍挂着的 xcodebuild / 测试宿主，避免挡 relaunch。
kill "$XCODE_PID" 2>/dev/null || true
wait "$XCODE_PID" 2>/dev/null || true
pkill -f "Ridge.app/Contents/MacOS/Ridge.*NSTreatUnknownArgumentsAsOpen" 2>/dev/null || true

rg -n "passed|failed|error:|TEST SUCCEEDED|TEST FAILED|Executed|RecurringRegression" "$LOG" | tail -50 || true

if rg -q "BUILD FAILED|\*\* TEST FAILED \*\*" "$LOG"; then
  if rg -q " failed \(" "$LOG" && ! rg -q "with 0 failures" "$LOG"; then
    echo "error: recurring tests failed. Full log: $LOG" >&2
    exit 1
  fi
fi

if ! rg -q "Test Suite 'Selected tests' passed" "$LOG"; then
  echo "error: recurring tests did not report Selected tests passed. Log: $LOG" >&2
  exit 1
fi

if ! rg -q "RecurringRegressionCoverageTests" "$LOG"; then
  echo "error: RecurringRegressionCoverageTests 未执行（是否漏进工程？先 xcodegen generate）" >&2
  exit 1
fi

if ! rg -q "with 0 failures" "$LOG"; then
  echo "error: recurring tests reported failures. Log: $LOG" >&2
  exit 1
fi

echo "==> Recurring tests passed"
echo "    log: $LOG"
