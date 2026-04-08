#!/bin/bash
# nipa_cron.sh - NIPA 서버에서 cron으로 실행하는 래퍼 스크립트
# 1) 서버 상태 수집
# 2) git commit & push
#
# crontab 등록 예시 (1분마다):
#   * * * * * /home/ispl/gpu-dashboard/scripts/nipa_cron.sh >> /home/ispl/gpu-dashboard/logs/cron.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"

mkdir -p "$LOG_DIR"

echo "========================================"
echo "[$(date)] Starting collection..."
echo "========================================"

cd "$REPO_DIR"

# 1. 서버 상태 수집
bash "$SCRIPT_DIR/collect_status.sh"

# 2. 변경 사항이 있으면 git commit & push
if git diff --quiet data/server_status.json 2>/dev/null; then
    echo "[$(date)] No changes detected. Skipping push."
else
    git add data/server_status.json
    git commit -m "Update server status $(date -u +%Y-%m-%dT%H:%M:%SZ)" --no-gpg-sign 2>/dev/null || true
    git push origin main 2>/dev/null
    echo "[$(date)] Pushed updated status."
fi

echo "[$(date)] Done."
