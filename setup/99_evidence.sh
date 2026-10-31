#!/usr/bin/env bash
# 99_evidence.sh — 제출용 증거 자료를 한 번에 수집한다.
#
# 과제 2절 "필수 증거 자료 체크리스트" 8항목을 순서대로 출력한다.
# 터미널 출력을 그대로 캡처하거나 파일로 저장해 수행 내역서에 붙이면 된다.
#
#   ./run.sh evidence                    화면 출력
#   ./run.sh evidence > evidence.txt     파일 저장
set -uo pipefail

# shellcheck disable=SC1091
[[ -r /etc/profile.d/agent-app.sh ]] && . /etc/profile.d/agent-app.sh
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

section() {
    echo
    echo "════════════════════════════════════════════════════════════"
    echo " $*"
    echo "════════════════════════════════════════════════════════════"
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  미션 B4-1 증거 자료                                      ║"
echo "║  수집 시각: $(date '+%Y-%m-%d %H:%M:%S')                         ║"
echo "║  호스트   : $(hostname)  /  $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "╚══════════════════════════════════════════════════════════╝"

section "① SSH 포트 변경(20022) 및 Root 원격 접속 차단"
echo "--- /etc/ssh/sshd_config ---"
grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config
echo
echo "--- 포트 리슨 상태 (ss -tulnp) ---"
ss -tulnp 2>/dev/null | grep -E "sshd|:20022" || echo "(sshd 미실행 — service ssh start 필요)"

section "② 방화벽 활성화 및 20022/tcp, 15034/tcp 만 허용"
ufw status verbose 2>/dev/null || echo "(root 권한 필요)"

section "③ 계정/그룹 생성 (agent-admin/dev/test, agent-common/core)"
for u in agent-admin agent-dev agent-test; do
    echo "--- id $u ---"
    id "$u"
done
echo
echo "--- 그룹 구성원 ---"
getent group agent-common
getent group agent-core

section "④ 디렉토리 구조 및 권한 (ACL 포함)"
echo "--- 구조 ---"
ls -ld "$AGENT_HOME" "$AGENT_HOME"/{upload_files,api_keys,bin} "$LOG_DIR"
echo
echo "--- getfacl: upload_files (공유 / agent-common) ---"
getfacl -p "$AGENT_HOME/upload_files" 2>/dev/null | grep -v '^#'
echo
echo "--- getfacl: api_keys (보안 / agent-core ONLY) ---"
getfacl -p "$AGENT_HOME/api_keys" 2>/dev/null | grep -v '^#'
echo
echo "--- getfacl: $LOG_DIR (보안 / agent-core ONLY) ---"
getfacl -p "$LOG_DIR" 2>/dev/null | grep -v '^#'
echo
echo "--- 권한 분리 실증: agent-test 가 api_keys 를 읽을 수 있는가? ---"
if su - agent-test -c "cat '$AGENT_HOME/api_keys/t_secret.key'" 2>&1 | grep -qi 'denied\|permission'; then
    echo "  [기대대로] agent-test 는 접근 거부됨"
else
    su - agent-test -c "cat '$AGENT_HOME/api_keys/t_secret.key'" 2>&1 | head -2
fi
echo
echo "--- monitor.sh 권한 (소유자 agent-dev / 그룹 agent-core / 750) ---"
ls -l "$AGENT_HOME/bin/"

section "⑤ 앱 Boot Sequence 5단계 [OK] 및 Agent READY"
if [[ -r /tmp/agent_app.out ]]; then
    cat /tmp/agent_app.out
else
    echo "(앱 미실행 — ./run.sh app 으로 실행하세요)"
fi

section "⑥ monitor.sh 실행 결과"
su - agent-admin -c "$AGENT_HOME/bin/monitor.sh" 2>&1
echo "(종료 코드: $?)"

section "⑦ monitor.log 누적 기록 (최근 10줄)"
echo "--- 총 줄 수: $(wc -l < "$LOG_DIR/monitor.log" 2>/dev/null || echo 0) ---"
tail -10 "$LOG_DIR/monitor.log" 2>/dev/null || echo "(로그 없음)"

section "⑧ crontab 매분 실행 등록 및 자동 실행 확인"
echo "--- agent-admin crontab ---"
crontab -u agent-admin -l 2>/dev/null || echo "(등록 없음)"
echo
echo "--- cron 데몬 상태 ---"
service cron status 2>&1 || true
echo
echo "--- 자동 실행 증거: 로그의 마지막 3줄 타임스탬프 간격을 보세요 ---"
tail -3 "$LOG_DIR/monitor.log" 2>/dev/null | awk '{print "   " $1, $2}'

section "보너스 ① report.sh 통계 리포트"
su - agent-admin -c "$AGENT_HOME/bin/report.sh" 2>&1

section "보너스 ② 로그 보존 정책 (현재 상태)"
echo "--- 로그 디렉토리 ---"
ls -l "$LOG_DIR" 2>/dev/null
echo "--- 아카이브 디렉토리 ---"
ls -l /var/log/monitor/agent-app/archive 2>/dev/null || echo "(아직 아카이브 없음)"

echo
echo "════════════════════════════════════════════════════════════"
echo " 수집 완료"
echo "════════════════════════════════════════════════════════════"
