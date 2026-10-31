#!/usr/bin/env bash
# agent-ops 실행 도우미 — Ubuntu 22.04 컨테이너에서 전부 수행한다
#
#   ./run.sh up        컨테이너 빌드 + 기동 + 전체 설정
#   ./run.sh app       앱 실행 (백그라운드)
#   ./run.sh monitor   monitor.sh 1회 실행
#   ./run.sh report    report.sh (보너스 1)
#   ./run.sh archive   log_archive.sh (보너스 2)
#   ./run.sh evidence  제출용 증거 전체 수집
#   ./run.sh shell     컨테이너 셸 접속
#   ./run.sh down      컨테이너 정리
set -uo pipefail
cd "$(dirname "$0")"

# OrbStack 또는 Docker Desktop 어느 쪽이든 찾아서 쓴다
if command -v docker >/dev/null 2>&1; then
    DOCKER=docker
elif [[ -x /Applications/OrbStack.app/Contents/MacOS/xbin/docker ]]; then
    DOCKER=/Applications/OrbStack.app/Contents/MacOS/xbin/docker
else
    echo "docker 를 찾을 수 없습니다. OrbStack 또는 Docker Desktop 을 실행하세요." >&2
    exit 1
fi

C=agent-ops
dc() { "$DOCKER" compose -f docker/docker-compose.yml "$@"; }
dex() { "$DOCKER" exec "$C" "$@"; }

case "${1:-up}" in
  up)
    dc up -d --build
    echo
    echo "=============== 설정 시작 ==============="
    for s in 01_users_groups 02_directories 03_ssh 04_firewall 05_env; do
        echo
        echo "───────── setup/${s}.sh ─────────"
        dex bash /opt/agent-ops/setup/${s}.sh
    done
    # monitor.sh 를 정해진 자리에 정해진 권한으로 배치한다
    echo
    echo "───────── monitor.sh 배치 ─────────"
    dex bash -lc '
      set -e
      . /etc/profile.d/agent-app.sh
      cp /opt/agent-ops/bin/*.sh "$AGENT_HOME/bin/"
      chown agent-dev:agent-core "$AGENT_HOME"/bin/*.sh
      chmod 750 "$AGENT_HOME"/bin/*.sh
      ls -l "$AGENT_HOME/bin/"
    '
    echo
    echo "───────── setup/06_cron.sh ─────────"
    dex bash -lc 'service cron start >/dev/null 2>&1; bash /opt/agent-ops/setup/06_cron.sh'
    dex bash -lc 'service ssh start 2>&1 | tail -1'
    echo
    echo "✅ 설정 완료. 다음: ./run.sh app"
    ;;
  app)
    dex bash -lc '
      . /etc/profile.d/agent-app.sh
      cp /opt/agent-ops/app/agent_app.py "$AGENT_HOME/"
      chown agent-admin:agent-core "$AGENT_HOME/agent_app.py"
      chmod 750 "$AGENT_HOME/agent_app.py"
      cp /opt/agent-ops/app/start_agent.sh "$AGENT_HOME/bin/"
      chown agent-admin:agent-core "$AGENT_HOME/bin/start_agent.sh"
      chmod 750 "$AGENT_HOME/bin/start_agent.sh"
      su - agent-admin -c "$AGENT_HOME/bin/start_agent.sh"
      sleep 2
      echo "--- Boot Sequence ---"
      cat /tmp/agent_app.out
    '
    ;;
  monitor)  dex bash -lc 'su - agent-admin -c "$AGENT_HOME/bin/monitor.sh"' ;;
  report)   dex bash -lc 'su - agent-admin -c "$AGENT_HOME/bin/report.sh"' ;;
  archive)  dex bash -lc 'su - agent-admin -c "$AGENT_HOME/bin/log_archive.sh"' ;;
  evidence) dex bash -lc 'bash /opt/agent-ops/setup/99_evidence.sh' ;;
  shell)    "$DOCKER" exec -it "$C" bash -l ;;
  down)     dc down ;;
  *) echo "사용법: ./run.sh [up|app|monitor|report|archive|evidence|shell|down]" >&2; exit 1 ;;
esac
