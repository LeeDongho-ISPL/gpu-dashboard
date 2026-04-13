#!/bin/bash
# run_collector.sh - Windows Git Bash에서 실행하는 수집 루프
# 사용법: Git Bash에서 실행
#   cd ~/gpu-dashboard
#   bash scripts/run_collector.sh
#
# 종료: Ctrl+C

INTERVAL=900  # 수집 간격 (초). 15분 = 900초

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

cd "$REPO_DIR"

echo "==========================================="
echo " ISPL GPU Dashboard Collector"
echo " Interval: ${INTERVAL}s"
echo " Press Ctrl+C to stop"
echo "==========================================="

while true; do
    echo ""
    echo "[$(date)] Collecting server status..."

    # 1. 수집
    bash "$SCRIPT_DIR/collect_status.sh" 2>&1

    # 2. 변경 사항 있으면 push
    if git diff --quiet data/server_status.json 2>/dev/null; then
        echo "[$(date)] No changes. Skipping push."
    else
        git add data/server_status.json
        git commit -m "Update server status $(date -u +%Y-%m-%dT%H:%M:%SZ)" --no-gpg-sign 2>/dev/null || true
        git push origin main 2>/dev/null && echo "[$(date)] Pushed." || echo "[$(date)] Push failed."
    fi

    echo "[$(date)] Next collection in ${INTERVAL}s..."
    sleep $INTERVAL
done
