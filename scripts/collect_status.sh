#!/bin/bash
# collect_status.sh - SSH로 각 서버에 접속하여 GPU/CPU/Memory 상태를 수집
# NIPA 서버에서 cron으로 실행됨

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_DIR/data"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ============================================================
# 설정 파일 로드 (servers.conf)
# ============================================================
CONF_FILE="$SCRIPT_DIR/servers.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found."
    echo "Copy servers.conf.example to servers.conf and fill in your server IPs."
    exit 1
fi
source "$CONF_FILE"

# SSH 명령 생성 헬퍼
build_ssh_cmd() {
    local host="$1"
    local port="$2"
    local user="$3"
    local ssh_opts="-o ConnectTimeout=15 -o StrictHostKeyChecking=no -o BatchMode=yes"

    echo "ssh $ssh_opts -p $port $user@$host"
}

collect_gpu_server() {
    local name="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local gpu_count="$5"
    local gpu_mem="$6"

    echo "Collecting from $name..." >&2

    local ssh_cmd
    ssh_cmd=$(build_ssh_cmd "$host" "$port" "$user")

    local raw_data
    raw_data=$($ssh_cmd bash <<'REMOTE_SCRIPT'
echo "===GPU_INFO==="
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "GPU_UNAVAILABLE"
echo "===CPU_INFO==="
nproc
cat /proc/loadavg | awk '{print $1}'
top -bn1 | grep "Cpu(s)" | awk '{print $2}' 2>/dev/null || echo "0"
echo "===MEM_INFO==="
free -m | awk 'NR==2{printf "%d %d %.1f", $3, $2, $3*100/$2}'
echo ""
echo "===DISK_INFO==="
df -h / | awk 'NR==2{print $3, $2, $5}'
echo "===USERS==="
who | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//'
echo ""
echo "===PROCESSES==="
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null || echo "NONE"
REMOTE_SCRIPT
    ) 2>/dev/null

    if [ $? -ne 0 ] || [ -z "$raw_data" ]; then
        cat <<EOF
{
  "name": "$name",
  "type": "gpu",
  "status": "offline",
  "timestamp": "$TIMESTAMP",
  "gpu_count": $gpu_count,
  "gpu_memory_gb": $gpu_mem,
  "gpus": [],
  "cpu": {},
  "memory": {},
  "disk": {},
  "users": [],
  "gpu_processes": []
}
EOF
        return
    fi

    # Parse GPU info
    local gpu_json="["
    local gpu_section=$(echo "$raw_data" | sed -n '/===GPU_INFO===/,/===CPU_INFO===/p' | grep -v '===' )
    local first=true
    while IFS=',' read -r idx gpu_name util mem_used mem_total temp; do
        [ -z "$idx" ] && continue
        [[ "$idx" == "GPU_UNAVAILABLE" ]] && break
        idx=$(echo "$idx" | xargs)
        gpu_name=$(echo "$gpu_name" | xargs)
        util=$(echo "$util" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        temp=$(echo "$temp" | xargs)
        if [ "$first" = true ]; then first=false; else gpu_json+=","; fi
        gpu_json+="{\"index\":$idx,\"name\":\"$gpu_name\",\"utilization\":$util,\"memory_used_mb\":$mem_used,\"memory_total_mb\":$mem_total,\"temperature\":$temp}"
    done <<< "$gpu_section"
    gpu_json+="]"

    # Parse CPU info
    local cpu_section=$(echo "$raw_data" | sed -n '/===CPU_INFO===/,/===MEM_INFO===/p' | grep -v '===')
    local cpu_cores=$(echo "$cpu_section" | sed -n '1p')
    local load_avg=$(echo "$cpu_section" | sed -n '2p')
    local cpu_usage=$(echo "$cpu_section" | sed -n '3p')

    # Parse Memory info
    local mem_section=$(echo "$raw_data" | sed -n '/===MEM_INFO===/,/===DISK_INFO===/p' | grep -v '===')
    local mem_used_mb=$(echo "$mem_section" | awk '{print $1}')
    local mem_total_mb=$(echo "$mem_section" | awk '{print $2}')
    local mem_percent=$(echo "$mem_section" | awk '{print $3}')

    # Parse Disk info
    local disk_section=$(echo "$raw_data" | sed -n '/===DISK_INFO===/,/===USERS===/p' | grep -v '===')
    local disk_used=$(echo "$disk_section" | awk '{print $1}')
    local disk_total=$(echo "$disk_section" | awk '{print $2}')
    local disk_percent=$(echo "$disk_section" | awk '{print $3}' | tr -d '%')

    # Parse Users
    local users_raw=$(echo "$raw_data" | sed -n '/===USERS===/,/===PROCESSES===/p' | grep -v '===' | head -1)
    local users_json="["
    local ufirst=true
    IFS=',' read -ra UARR <<< "$users_raw"
    for u in "${UARR[@]}"; do
        u=$(echo "$u" | xargs)
        [ -z "$u" ] && continue
        if [ "$ufirst" = true ]; then ufirst=false; else users_json+=","; fi
        users_json+="\"$u\""
    done
    users_json+="]"

    # Parse GPU processes
    local proc_section=$(echo "$raw_data" | sed -n '/===PROCESSES===/,$p' | grep -v '===')
    local proc_json="["
    local pfirst=true
    while IFS=',' read -r pid pname pmem; do
        [ -z "$pid" ] && continue
        [[ "$pid" == "NONE" ]] && break
        pid=$(echo "$pid" | xargs)
        pname=$(echo "$pname" | xargs)
        pmem=$(echo "$pmem" | xargs)
        if [ "$pfirst" = true ]; then pfirst=false; else proc_json+=","; fi
        proc_json+="{\"pid\":$pid,\"name\":\"$pname\",\"memory_mb\":$pmem}"
    done <<< "$proc_section"
    proc_json+="]"

    cat <<EOF
{
  "name": "$name",
  "type": "gpu",
  "status": "online",
  "timestamp": "$TIMESTAMP",
  "gpu_count": $gpu_count,
  "gpu_memory_gb": $gpu_mem,
  "gpus": $gpu_json,
  "cpu": {"cores": ${cpu_cores:-0}, "load_avg": ${load_avg:-0}, "usage_percent": ${cpu_usage:-0}},
  "memory": {"used_mb": ${mem_used_mb:-0}, "total_mb": ${mem_total_mb:-0}, "percent": ${mem_percent:-0}},
  "disk": {"used": "${disk_used:-0}", "total": "${disk_total:-0}", "percent": ${disk_percent:-0}},
  "users": $users_json,
  "gpu_processes": $proc_json
}
EOF
}

collect_cpu_server() {
    local name="$1"
    local host="$2"
    local port="$3"
    local user="$4"

    echo "Collecting from $name..." >&2

    local ssh_cmd
    ssh_cmd=$(build_ssh_cmd "$host" "$port" "$user")

    local raw_data
    raw_data=$($ssh_cmd bash <<'REMOTE_SCRIPT'
echo "===CPU_INFO==="
nproc
cat /proc/loadavg | awk '{print $1}'
top -bn1 | grep "Cpu(s)" | awk '{print $2}' 2>/dev/null || echo "0"
echo "===MEM_INFO==="
free -m | awk 'NR==2{printf "%d %d %.1f", $3, $2, $3*100/$2}'
echo ""
echo "===DISK_INFO==="
df -h / | awk 'NR==2{print $3, $2, $5}'
echo "===USERS==="
who | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//'
echo ""
REMOTE_SCRIPT
    ) 2>/dev/null

    if [ $? -ne 0 ] || [ -z "$raw_data" ]; then
        cat <<EOF
{
  "name": "$name",
  "type": "cpu",
  "status": "offline",
  "timestamp": "$TIMESTAMP",
  "cpu": {},
  "memory": {},
  "disk": {},
  "users": []
}
EOF
        return
    fi

    local cpu_section=$(echo "$raw_data" | sed -n '/===CPU_INFO===/,/===MEM_INFO===/p' | grep -v '===')
    local cpu_cores=$(echo "$cpu_section" | sed -n '1p')
    local load_avg=$(echo "$cpu_section" | sed -n '2p')
    local cpu_usage=$(echo "$cpu_section" | sed -n '3p')

    local mem_section=$(echo "$raw_data" | sed -n '/===MEM_INFO===/,/===DISK_INFO===/p' | grep -v '===')
    local mem_used_mb=$(echo "$mem_section" | awk '{print $1}')
    local mem_total_mb=$(echo "$mem_section" | awk '{print $2}')
    local mem_percent=$(echo "$mem_section" | awk '{print $3}')

    local disk_section=$(echo "$raw_data" | sed -n '/===DISK_INFO===/,/===USERS===/p' | grep -v '===')
    local disk_used=$(echo "$disk_section" | awk '{print $1}')
    local disk_total=$(echo "$disk_section" | awk '{print $2}')
    local disk_percent=$(echo "$disk_section" | awk '{print $3}' | tr -d '%')

    local users_raw=$(echo "$raw_data" | sed -n '/===USERS===/,$p' | grep -v '===' | head -1)
    local users_json="["
    local ufirst=true
    IFS=',' read -ra UARR <<< "$users_raw"
    for u in "${UARR[@]}"; do
        u=$(echo "$u" | xargs)
        [ -z "$u" ] && continue
        if [ "$ufirst" = true ]; then ufirst=false; else users_json+=","; fi
        users_json+="\"$u\""
    done
    users_json+="]"

    cat <<EOF
{
  "name": "$name",
  "type": "cpu",
  "status": "online",
  "timestamp": "$TIMESTAMP",
  "cpu": {"cores": ${cpu_cores:-0}, "load_avg": ${load_avg:-0}, "usage_percent": ${cpu_usage:-0}},
  "memory": {"used_mb": ${mem_used_mb:-0}, "total_mb": ${mem_total_mb:-0}, "percent": ${mem_percent:-0}},
  "disk": {"used": "${disk_used:-0}", "total": "${disk_total:-0}", "percent": ${disk_percent:-0}},
  "users": $users_json
}
EOF
}

# ============================================================
# 서버 수집 실행
# ============================================================

echo "Starting collection at $TIMESTAMP"

# GPU Servers
NIPA_JSON=$(collect_gpu_server "NIPA_server" "$NIPA_IP" "$NIPA_PORT" "$NIPA_USER" 1 80)
ISPL_JSON=$(collect_gpu_server "ISPL" "$ISPL_IP" "$ISPL_PORT" "$ISPL_USER" 8 48)

# CPU Servers
CPU1_JSON=$(collect_cpu_server "CPU1" "$CPU1_IP" "$CPU1_PORT" "$CPU_USER")
CPU2_JSON=$(collect_cpu_server "CPU2" "$CPU2_IP" "$CPU2_PORT" "$CPU_USER")
CPU3_JSON=$(collect_cpu_server "CPU3" "$CPU3_IP" "$CPU3_PORT" "$CPU_USER")
CPU4_JSON=$(collect_cpu_server "CPU4" "$CPU4_IP" "$CPU4_PORT" "$CPU_USER")

# 전체 JSON 조합
mkdir -p "$OUTPUT_DIR"
cat <<EOF > "$OUTPUT_DIR/server_status.json"
{
  "last_updated": "$TIMESTAMP",
  "servers": [
    $NIPA_JSON,
    $ISPL_JSON,
    $CPU1_JSON,
    $CPU2_JSON,
    $CPU3_JSON,
    $CPU4_JSON
  ]
}
EOF

echo "Collection complete. Output: $OUTPUT_DIR/server_status.json"
