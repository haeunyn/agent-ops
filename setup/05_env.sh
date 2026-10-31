#!/usr/bin/env bash
# 환경 변수 — 실행 환경을 고정한다
#
# 왜 경로를 코드에 박지 않고 환경 변수로 빼는가:
#   ① "내 컴퓨터에선 되는데요" 를 막는다. 개발/스테이징/운영에서 경로가 달라도
#      코드는 그대로 두고 환경 변수만 바꾸면 된다.
#   ② cron 으로 실행할 때 특히 중요하다. cron 은 로그인 셸이 아니라서
#      .bashrc 를 읽지 않는다. PATH 조차 최소한만 주어진다.
#      그래서 스크립트가 자기 환경을 **스스로** 불러오도록 만들어야 한다.
#      (monitor.sh 가 맨 위에서 이 파일을 source 하는 이유)
#   ③ 키 파일 경로 같은 걸 소스에 박으면 저장소에 올라가 유출된다.
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
ENV_FILE=/etc/profile.d/agent-app.sh

echo "== 환경 변수 파일 생성: $ENV_FILE =="
cat > "$ENV_FILE" <<ENV
# Agent App 실행 환경 (setup/05_env.sh 가 생성)
export AGENT_HOME="$AGENT_HOME"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="\$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="\$AGENT_HOME/api_keys/t_secret.key"
export AGENT_LOG_DIR=/var/log/agent-app
# monitor.sh 가 감시할 프로세스 이름.
# 코디세이가 제공하는 실제 앱(agent-app-linux-arm64 등)을 쓸 때는 이 값만 바꾸면 된다.
export AGENT_PROC=agent_app.py
ENV
chmod 644 "$ENV_FILE"

echo
echo "== 확인 =="
# shellcheck disable=SC1090
. "$ENV_FILE"
for name in AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_KEY_PATH AGENT_LOG_DIR AGENT_PROC; do
    printf '  %-20s = %s\n' "$name" "${!name}"
done
