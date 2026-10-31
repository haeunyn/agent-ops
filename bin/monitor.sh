#!/usr/bin/env bash
#
# monitor.sh — 시스템 상태 수집 및 로깅
#
# 미션 B4-1 "컴퓨터가 알아서 자기 상태를 점검하게 만들기"
#
# 하는 일
#   1) Health Check   앱 프로세스와 포트. 하나라도 죽었으면 exit 1 (= 장애)
#   2) 상태 점검      방화벽. 꺼져 있으면 경고만 하고 계속 진행
#   3) 자원 수집      CPU / MEM / DISK 사용률
#   4) 임계값 경고    기준을 넘으면 [WARNING]
#   5) 로그 기록      /var/log/agent-app/monitor.log 에 한 줄 누적
#   6) 용량 관리      10MB 넘으면 돌려 쓰고 10개까지만 보관
#
# 종료 코드
#   0  정상 (경고가 있어도 0 — 경고는 장애가 아니다)
#   1  Health Check 실패 (프로세스 또는 포트 이상)
#   2  환경 문제 (로그 디렉토리에 쓸 수 없는 등)
#
# 왜 exit 코드를 나누는가:
#   cron 은 스크립트가 0이 아닌 값을 돌려주면 그걸 메일이나 로그로 알린다.
#   "경고"와 "장애"를 같은 코드로 만들면 알림이 쏟아져 진짜 장애를 놓친다.

set -uo pipefail
# set -e 를 쓰지 않는 이유:
#   이 스크립트는 "실패를 감지해서 보고하는" 것이 일이다.
#   명령 하나가 실패했다고 즉시 죽어버리면 로그를 남기지 못한 채 끝난다.
#   그래서 실패를 직접 확인하고 처리한다.

# ── 환경 불러오기 ────────────────────────────────────────────────
# cron 은 로그인 셸이 아니라 .bashrc 를 읽지 않는다. PATH 조차 최소한이다.
# 그래서 스크립트가 자기 환경을 스스로 불러와야 한다. 이게 cron 작업이
# "손으로 하면 되는데 자동 실행만 하면 안 되는" 가장 흔한 원인이다.
if [[ -r /etc/profile.d/agent-app.sh ]]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/agent-app.sh
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_PROC="${AGENT_PROC:-agent_app.py}"
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="$LOG_DIR/monitor.log"

# 임계값 (과제 지정)
CPU_THRESHOLD=20
MEM_THRESHOLD=10
DISK_THRESHOLD=80

# 로그 보존 (과제 지정: 최대 10MB / 10개)
MAX_LOG_BYTES=$((10 * 1024 * 1024))
MAX_LOG_FILES=10

WARNINGS=0

# ── 도우미 ──────────────────────────────────────────────────────
warn() {
    echo "[WARNING] $*"
    WARNINGS=$((WARNINGS + 1))
}

die() {
    echo "[FAIL] $*"
    exit "${2:-1}"
}

# ── 1) Health Check — 프로세스 ──────────────────────────────────
# pgrep -f 는 명령줄 전체에서 찾는다. 'python3 agent_app.py' 처럼
# 인터프리터로 실행되면 프로세스 이름이 python3 라서 -f 없이는 못 찾는다.
check_process() {
    printf "Checking process '%s'... " "$AGENT_PROC"
    local pid
    pid="$(pgrep -f -- "$AGENT_PROC" | head -n 1)"
    if [[ -z "$pid" ]]; then
        echo "[FAIL]"
        return 1
    fi
    echo "[OK] (PID: $pid)"
    APP_PID="$pid"
    return 0
}

# ── 1) Health Check — 포트 ──────────────────────────────────────
# ss 를 먼저 쓰고 없으면 netstat 으로 넘어간다.
# -t TCP / -u UDP / -l LISTEN 중인 것 / -n 숫자로 / -p 프로세스
check_port() {
    printf "Checking port %s... " "$AGENT_PORT"
    local listening=""
    if command -v ss >/dev/null 2>&1; then
        listening="$(ss -tuln 2>/dev/null | grep -E "[:.]${AGENT_PORT}[[:space:]]")"
    elif command -v netstat >/dev/null 2>&1; then
        listening="$(netstat -tuln 2>/dev/null | grep -E "[:.]${AGENT_PORT}[[:space:]]")"
    else
        echo "[SKIP] (ss/netstat 없음)"
        return 0
    fi
    if [[ -z "$listening" ]]; then
        echo "[FAIL]"
        return 1
    fi
    echo "[OK]"
    return 0
}

# ── 2) 상태 점검 — 방화벽 (경고만) ──────────────────────────────
# 과제 요구: 비활성이면 [WARNING] 을 내되 스크립트는 종료하지 않는다.
# 방화벽이 꺼진 건 "고쳐야 할 설정 문제"지 "앱이 죽은 장애"는 아니기 때문이다.
# ufw status 는 root 전용이다. cron 은 agent-admin 으로 돌므로 그냥 부르면
# "You need to be root" 가 나와 **켜져 있는데도 꺼진 것처럼** 보고된다.
# 그래서 ① root 면 그대로 ② 아니면 sudo -n (04_firewall.sh 가 등록한 규칙)
# ③ 그것도 안 되면 설정 파일을 직접 읽는 순서로 확인한다.
# -n 은 "비밀번호를 물어야 하면 그냥 실패하라"는 뜻 — cron 은 입력을 받을 수 없다.
ufw_status() {
    if [[ "$(id -u)" -eq 0 ]]; then
        ufw status 2>/dev/null
    elif sudo -n ufw status 2>/dev/null; then
        :
    elif [[ -r /etc/ufw/ufw.conf ]] && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then
        echo "Status: active"
    fi
}

check_firewall() {
    printf "Checking firewall... "
    if command -v ufw >/dev/null 2>&1; then
        if ufw_status | grep -qi '^Status: active'; then
            echo "[OK] (ufw active)"
        else
            echo ""
            warn "Firewall (ufw) is not active"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -qi running; then
            echo "[OK] (firewalld running)"
        else
            echo ""
            warn "Firewall (firewalld) is not running"
        fi
    else
        echo "[SKIP] (ufw/firewalld 없음)"
    fi
}

# ── 3) 자원 수집 — CPU ──────────────────────────────────────────
# /proc/stat 의 첫 줄은 부팅 이후 CPU 가 각 상태로 보낸 누적 시간이다.
# 누적값이므로 한 번만 읽으면 '지금 사용률'을 알 수 없다.
# 1초 간격으로 두 번 읽어 **차이**를 구해야 그 1초 동안의 사용률이 나온다.
#   사용률 = (전체 증가분 - idle 증가분) / 전체 증가분 × 100
read_cpu_usage() {
    local a b
    a="$(grep '^cpu ' /proc/stat)"
    sleep 1
    b="$(grep '^cpu ' /proc/stat)"
    awk -v l1="$a" -v l2="$b" '
    BEGIN {
        split(l1, p, " "); split(l2, c, " ");
        # 필드: cpu user nice system idle iowait irq softirq steal ...
        for (i = 2; i <= 9; i++) { prev += p[i]; cur += c[i] }
        prev_idle = p[5] + p[6];   # idle + iowait
        cur_idle  = c[5] + c[6];
        total = cur - prev;
        idle  = cur_idle - prev_idle;
        if (total <= 0) { printf "0.0"; exit }
        printf "%.1f", (total - idle) * 100 / total;
    }'
}

# ── 3) 자원 수집 — 메모리 ───────────────────────────────────────
# MemFree 가 아니라 MemAvailable 을 쓰는 이유:
#   리눅스는 남는 메모리를 디스크 캐시로 써 둔다. 그래서 MemFree 는 늘 작게 나오고
#   "메모리 부족"처럼 보인다. MemAvailable 은 "필요하면 캐시를 비워서 줄 수 있는 양"
#   까지 계산한 값이라 실제 여유에 가깝다.
read_mem_usage() {
    awk '
      /^MemTotal:/     { total = $2 }
      /^MemAvailable:/ { avail = $2 }
      END {
        if (total <= 0) { printf "0.0"; exit }
        printf "%.1f", (total - avail) * 100 / total;
      }' /proc/meminfo
}

# ── 3) 자원 수집 — 디스크 ───────────────────────────────────────
# -P 는 POSIX 출력 형식. 장치 이름이 길면 df 가 줄을 바꿔버리는데,
# -P 를 주면 한 줄로 고정되어 awk 로 안전하게 자를 수 있다.
read_disk_usage() {
    df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

# ── 6) 로그 용량 관리 ───────────────────────────────────────────
# 과제 요구: 최대 10MB / 10개 유지.
# logrotate 를 쓸 수도 있지만, 스크립트 안에 넣으면 cron 만 돌면 되고
# 별도 설정 파일 의존이 없어 어디서든 똑같이 동작한다.
#
# 돌려 쓰는 방식(뒤에서부터 밀어낸다):
#   .9 삭제 → .8을 .9로 → ... → .1을 .2로 → monitor.log를 .1로
# 뒤에서부터 미는 이유: 앞에서부터 하면 .1 을 .2 로 옮기는 순간
#   원래 .2 를 덮어써서 없어진다.
rotate_log_if_needed() {
    [[ -f "$LOG_FILE" ]] || return 0
    local size
    size="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"
    [[ "$size" -lt "$MAX_LOG_BYTES" ]] && return 0

    local last=$((MAX_LOG_FILES - 1))
    rm -f "${LOG_FILE}.${last}"
    local i
    for (( i = last - 1; i >= 1; i-- )); do
        [[ -f "${LOG_FILE}.${i}" ]] && mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    done
    mv -f "$LOG_FILE" "${LOG_FILE}.1"
    : > "$LOG_FILE"
    echo "[INFO] Log rotated (>= ${MAX_LOG_BYTES} bytes)"
}

# ══════════════════════════════════════════════════════════════
# 본 실행
# ══════════════════════════════════════════════════════════════
echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

APP_PID=""
check_process || die "Process '$AGENT_PROC' is not running." 1
check_port    || die "Port $AGENT_PORT is not listening." 1
check_firewall

echo
echo "[RESOURCE MONITORING]"
CPU="$(read_cpu_usage)"
MEM="$(read_mem_usage)"
DISK="$(read_disk_usage)"

printf 'CPU Usage  : %s%%\n' "$CPU"
printf 'MEM Usage  : %s%%\n' "$MEM"
printf 'DISK Used  : %s%%\n' "$DISK"

# 임계값 비교. bash 는 소수 비교를 못 해서 awk 로 판정한다.
over() { awk -v v="$1" -v t="$2" 'BEGIN { exit !(v > t) }'; }

over "$CPU"  "$CPU_THRESHOLD"  && warn "CPU threshold exceeded (${CPU}% > ${CPU_THRESHOLD}%)"
over "$MEM"  "$MEM_THRESHOLD"  && warn "MEM threshold exceeded (${MEM}% > ${MEM_THRESHOLD}%)"
over "$DISK" "$DISK_THRESHOLD" && warn "DISK threshold exceeded (${DISK}% > ${DISK_THRESHOLD}%)"

# ── 5) 로그 기록 ────────────────────────────────────────────────
if [[ ! -d "$LOG_DIR" ]]; then
    echo "[FAIL] Log directory missing: $LOG_DIR"
    exit 2
fi
if [[ ! -w "$LOG_DIR" ]]; then
    echo "[FAIL] Log directory not writable: $LOG_DIR"
    exit 2
fi

rotate_log_if_needed

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
LINE="[$TIMESTAMP] PID:${APP_PID} CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK}%"
echo "$LINE" >> "$LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"
[[ "$WARNINGS" -gt 0 ]] && echo "[INFO] $WARNINGS warning(s) raised."
exit 0
