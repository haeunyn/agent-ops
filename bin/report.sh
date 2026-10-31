#!/usr/bin/env bash
#
# report.sh — 보너스 1. monitor.log 를 분석해 요약 통계를 낸다.
#
# 사용법
#   ./report.sh                                  전체 기간
#   ./report.sh "2026-02-25 13:00" "2026-02-25 14:00"   구간 지정
#
# 왜 이런 게 필요한가:
#   monitor.log 는 1분에 한 줄씩 쌓인다. 하루면 1,440줄이다.
#   눈으로 훑어서 "평소보다 CPU 가 높았나"를 판단하는 건 불가능하다.
#   평균/최대/최소로 줄여야 사람이 읽을 수 있는 정보가 된다.
#   그리고 최대값이 **언제** 찍혔는지가 장애 원인 추적의 출발점이 된다.

set -uo pipefail

if [[ -r /etc/profile.d/agent-app.sh ]]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/agent-app.sh
fi

LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${1:-}"

# 첫 인자가 파일이면 그걸 쓰고, 아니면 기본 로그 파일 + 시간 구간으로 해석
if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
    shift
else
    LOG_FILE="$LOG_DIR/monitor.log"
fi

START="${1:-}"
END="${2:-}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "[ERROR] 로그 파일이 없습니다: $LOG_FILE" >&2
    exit 1
fi
if [[ ! -r "$LOG_FILE" ]]; then
    echo "[ERROR] 로그 파일을 읽을 수 없습니다(권한): $LOG_FILE" >&2
    exit 1
fi

awk -v start="$START" -v end="$END" -v src="$LOG_FILE" '
# 로그 한 줄 형식:
# [2026-02-25 13:58:01] PID:48291 CPU:10.2% MEM:3.2% DISK_USED:23%
{
    # 대괄호 안의 타임스탬프를 꺼낸다.
    #
    # ⚠️ 정규식 구간 수량자({4} 같은 것)를 쓰지 않는다.
    #    Ubuntu 기본 awk 는 gawk 가 아니라 **mawk** 인데, mawk 1.3.4 는
    #    {n} 문법을 지원하지 않아 아무것도 매치되지 않는다(실제로 겪었다).
    #    index/substr 만 쓰면 어느 awk 에서도 똑같이 동작한다.
    open_pos  = index($0, "[")
    close_pos = index($0, "]")
    if (open_pos != 1 || close_pos <= open_pos) next
    ts = substr($0, open_pos + 1, close_pos - open_pos - 1)
    if (length(ts) != 19) next   # "YYYY-MM-DD HH:MM:SS" 는 19글자

    # 구간 필터. 문자열 비교로 충분하다 —
    # "YYYY-MM-DD HH:MM:SS" 형식은 사전순 = 시간순이기 때문이다.
    if (start != "" && ts < start) next
    if (end   != "" && ts > end)   next

    cpu = extract($0, "CPU:")
    mem = extract($0, "MEM:")
    dsk = extract($0, "DISK_USED:")
    if (cpu == "" || mem == "" || dsk == "") next

    n++
    acc_cpu += cpu; acc_mem += mem; acc_dsk += dsk

    if (n == 1 || cpu > max_cpu) { max_cpu = cpu; max_cpu_ts = ts }
    if (n == 1 || cpu < min_cpu) { min_cpu = cpu; min_cpu_ts = ts }
    if (n == 1 || mem > max_mem) { max_mem = mem; max_mem_ts = ts }
    if (n == 1 || mem < min_mem) { min_mem = mem; min_mem_ts = ts }
    if (n == 1 || dsk > max_dsk) { max_dsk = dsk; max_dsk_ts = ts }
    if (n == 1 || dsk < min_dsk) { min_dsk = dsk; min_dsk_ts = ts }

    if (n == 1) first_ts = ts
    last_ts = ts
}

function extract(line, label,    pos, rest, val) {
    pos = index(line, label)
    if (pos == 0) return ""
    rest = substr(line, pos + length(label))
    # 숫자와 소수점만 앞에서부터 잘라낸다
    if (match(rest, /^[0-9]+(\.[0-9]+)?/) == 0) return ""
    val = substr(rest, RSTART, RLENGTH)
    return val + 0
}

function block(name, avg, mx, mx_ts, mn, mn_ts) {
    printf "  [%s]\n", name
    printf "    Average : %.1f%%\n", avg
    printf "    Maximum : %.1f%% at %s\n", mx, mx_ts
    printf "    Minimum : %.1f%% at %s\n", mn, mn_ts
}

END {
    print "====== STATISTICS REPORT ======"
    if (n == 0) {
        print "  분석할 데이터가 없습니다."
        if (start != "" || end != "") print "  (구간 필터에 걸리는 로그가 없습니다)"
        exit 0
    }
    block("CPU",    acc_cpu / n, max_cpu, max_cpu_ts, min_cpu, min_cpu_ts)
    block("Memory", acc_mem / n, max_mem, max_mem_ts, min_mem, min_mem_ts)
    block("Disk",   acc_dsk / n, max_dsk, max_dsk_ts, min_dsk, min_dsk_ts)
    print "  [Samples]"
    printf "    Data Points: %d samples\n", n
    printf "    Period     : %s ~ %s\n", first_ts, last_ts
    printf "    Source     : %s\n", src
}
' "$LOG_FILE"
