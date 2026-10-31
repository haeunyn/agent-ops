#!/usr/bin/env bash
# 앱을 백그라운드로 띄우는 실행 스크립트.
#
# 왜 따로 파일로 뺐는가:
#   docker exec → bash -lc → su - → nohup 처럼 셸이 겹겹이 쌓이면
#   따옴표와 $ 가 어느 단계에서 풀릴지 예측하기 어렵다(실제로 한 번 틀렸다).
#   스크립트 파일로 만들면 셸 한 겹에서만 해석되므로 그 문제가 사라진다.
set -euo pipefail

# shellcheck disable=SC1091
. /etc/profile.d/agent-app.sh

LOG_OUT="${1:-/tmp/agent_app.out}"

# 돌고 있던 앱을 먼저 내린다.
#
# ⚠️ 대괄호 트릭에 주의: pkill -f 는 '명령줄 전체'에서 찾는데,
#    그냥 `pkill -f agent_app.py` 라고 쓰면 이 스크립트를 호출한 셸의
#    명령줄에도 그 문자열이 들어 있어서 **자기 자신을 죽인다**(exit 143).
#    `[a]gent_app` 으로 쓰면 정규식으로는 "agent_app" 에 매치되지만
#    문자열 자체는 "[a]gent_app" 이라 자기 명령줄과는 겹치지 않는다.
pkill -f '[a]gent_app\.py' 2>/dev/null || true
sleep 1

cd "$AGENT_HOME"
nohup python3 "$AGENT_HOME/agent_app.py" > "$LOG_OUT" 2>&1 &
echo "started pid=$!"
