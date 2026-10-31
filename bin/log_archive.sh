#!/usr/bin/env bash
#
# log_archive.sh — 보너스 2. 시간 기반 로그 보존 정책.
#
#   7일 경과 로그  → gzip 압축
#   압축 파일      → /var/log/monitor/agent-app/archive/ 로 이동
#   30일 경과 아카이브 → 삭제
#
# 왜 보존 정책이 필요한가:
#   로그는 지우지 않으면 반드시 디스크를 가득 채운다. 디스크가 100%가 되면
#   로그를 못 쓰는 정도가 아니라 **서비스 자체가 멈춘다**. 임시 파일도
#   못 만들고 DB 도 쓰기에 실패한다. 장애를 기록하려던 것이 장애의 원인이 되는 셈이다.
#
#   그렇다고 바로 지울 수는 없다. 장애 분석은 보통 며칠 뒤에 한다.
#   그래서 "최근 것은 그대로 / 조금 지난 건 압축 / 아주 오래된 건 삭제"
#   3단계로 나눈다. 텍스트 로그는 gzip 으로 보통 10분의 1 아래로 줄어든다.
#
# 예외 처리:
#   디렉토리 없음 / 권한 부족 / 대상 0개 — 전부 '안전하게 경고하고 계속'한다.
#   cron 으로 매일 도는 스크립트가 에러로 죽으면 그날 정리가 통째로 안 된다.

set -uo pipefail

if [[ -r /etc/profile.d/agent-app.sh ]]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/agent-app.sh
fi

LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${AGENT_ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
COMPRESS_AFTER_DAYS=7
DELETE_AFTER_DAYS=30

echo "====== LOG RETENTION ======"
echo "  소스    : $LOG_DIR"
echo "  아카이브: $ARCHIVE_DIR"
echo "  정책    : ${COMPRESS_AFTER_DAYS}일 경과 압축 → 이동, ${DELETE_AFTER_DAYS}일 경과 삭제"
echo

# ── 사전 점검 ───────────────────────────────────────────────────
if [[ ! -d "$LOG_DIR" ]]; then
    echo "[WARNING] 로그 디렉토리가 없습니다: $LOG_DIR — 할 일이 없어 종료합니다."
    exit 0
fi

if ! mkdir -p "$ARCHIVE_DIR" 2>/dev/null; then
    echo "[WARNING] 아카이브 디렉토리를 만들 수 없습니다(권한): $ARCHIVE_DIR"
    exit 0
fi
if [[ ! -w "$ARCHIVE_DIR" ]]; then
    echo "[WARNING] 아카이브 디렉토리에 쓸 수 없습니다: $ARCHIVE_DIR"
    exit 0
fi

# ── 1) 7일 경과 로그 압축 ───────────────────────────────────────
# -mtime +7 : 마지막 수정 시각이 7일 **보다 더 지난** 파일
# -print0 / read -d '' : 파일명에 공백이 있어도 안전하게 넘긴다
compressed=0
while IFS= read -r -d '' file; do
    if gzip -f "$file" 2>/dev/null; then
        echo "  [압축] $(basename "$file") → $(basename "$file").gz"
        compressed=$((compressed + 1))
    else
        echo "  [WARNING] 압축 실패(권한?): $file"
    fi
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${COMPRESS_AFTER_DAYS}" -print0 2>/dev/null)

# monitor.log.1 처럼 번호가 붙은 회전 파일도 대상에 넣는다
while IFS= read -r -d '' file; do
    if gzip -f "$file" 2>/dev/null; then
        echo "  [압축] $(basename "$file") → $(basename "$file").gz"
        compressed=$((compressed + 1))
    fi
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log.[0-9]*' ! -name '*.gz' -mtime "+${COMPRESS_AFTER_DAYS}" -print0 2>/dev/null)

[[ "$compressed" -eq 0 ]] && echo "  [압축] 대상 없음"

# ── 2) 압축 파일을 아카이브로 이동 ──────────────────────────────
moved=0
while IFS= read -r -d '' file; do
    if mv -f "$file" "$ARCHIVE_DIR/" 2>/dev/null; then
        echo "  [이동] $(basename "$file") → $ARCHIVE_DIR/"
        moved=$((moved + 1))
    else
        echo "  [WARNING] 이동 실패(권한?): $file"
    fi
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.gz' -print0 2>/dev/null)

[[ "$moved" -eq 0 ]] && echo "  [이동] 대상 없음"

# ── 3) 30일 경과 아카이브 삭제 ──────────────────────────────────
deleted=0
while IFS= read -r -d '' file; do
    if rm -f "$file" 2>/dev/null; then
        echo "  [삭제] $(basename "$file")"
        deleted=$((deleted + 1))
    else
        echo "  [WARNING] 삭제 실패(권한?): $file"
    fi
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime "+${DELETE_AFTER_DAYS}" -print0 2>/dev/null)

[[ "$deleted" -eq 0 ]] && echo "  [삭제] 대상 없음"

echo
echo "요약: 압축 ${compressed}건 / 이동 ${moved}건 / 삭제 ${deleted}건"
exit 0
