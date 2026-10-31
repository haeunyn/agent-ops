#!/usr/bin/env bash
# cron 등록 — monitor.sh 를 매분 자동 실행
#
# 왜 agent-admin 계정으로 등록하는가:
#   과제 지정이기도 하고, agent-admin 이 agent-core 그룹에 속해 있어서
#   monitor.sh(권한 750, 그룹 agent-core)를 실행할 수 있고
#   /var/log/agent-app 에도 쓸 수 있기 때문이다.
#   agent-test 로 등록하면 그룹에 없어서 실행 자체가 거부된다.
#
# cron 표기: 분 시 일 월 요일
#   * * * * *   → 매분
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
MONITOR="$AGENT_HOME/bin/monitor.sh"
CRON_USER=agent-admin

echo "== crontab 등록 ($CRON_USER) =="

# 기존 등록을 지우고 새로 넣는다(중복 방지)
existing="$(crontab -u "$CRON_USER" -l 2>/dev/null | grep -v 'monitor.sh' || true)"
{
    [[ -n "$existing" ]] && echo "$existing"
    # cron 은 PATH 가 최소한이라 명시해 준다.
    # 출력은 cron 메일로 가므로 별도 파일로 돌려 둔다.
    echo "* * * * * $MONITOR >> /var/log/agent-app/cron.out 2>&1"
} | crontab -u "$CRON_USER" -

echo
echo "== 확인 =="
crontab -u "$CRON_USER" -l
