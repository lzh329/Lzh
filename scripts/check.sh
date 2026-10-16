#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# 简瘦 FitTrack — 提交门禁
# 用法（Git Bash）: bash scripts/check.sh
# 规矩：本脚本不绿，不许提交。
# ═══════════════════════════════════════════════════════════
set -uo pipefail

FLUTTER="${FLUTTER_BIN:-/d/dev/flutter/bin/flutter.bat}"

# 本机 Clash 系统代理（127.0.0.1:51650）会拦截 flutter_tester 的本地
# WebSocket 连接，导致测试报 "Invalid WebSocket upgrade request"。
# 分析和测试都是本地运行，无需网络，直接绕过代理。
export NO_PROXY="127.0.0.1,localhost"
export HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy=

echo "==> [1/2] 静态分析（要求 0 issue）"
if ! "$FLUTTER" analyze; then
  echo ""
  echo "❌ 静态分析未通过 —— 先修掉上面列出的问题，再提交"
  exit 1
fi

echo ""
echo "==> [2/2] 单元测试"
if ! "$FLUTTER" test; then
  echo ""
  echo "❌ 测试未通过 —— 修复后再提交"
  exit 1
fi

echo ""
echo "OK — 全部通过，可以提交"
