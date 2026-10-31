#!/usr/bin/env bash
# 계정/그룹 생성 — 역할 기반 접근 제어(RBAC)의 토대
#
# 왜 역할마다 계정을 나누는가:
#   한 계정을 돌려쓰면 "누가 무엇을 했는지" 로그로 추적할 수 없다.
#   또 한 계정이 뚫리면 전부 뚫린다. 역할별로 나누면 피해 범위가 그 역할로 제한된다.
#   이것을 '최소 권한 원칙(least privilege)'이라고 한다.
#
# 왜 그룹이 두 개인가:
#   agent-common — 셋 다. 업로드 파일처럼 같이 쓰는 것
#   agent-core   — admin, dev 만. API 키와 로그처럼 민감한 것
#   test 계정은 core 에 없으므로 api_keys 를 들여다볼 수 없다.
set -euo pipefail

echo "== 계정/그룹 생성 =="

# 그룹 먼저 (계정을 만들 때 그룹이 있어야 한다)
for grp in agent-common agent-core; do
    if getent group "$grp" >/dev/null; then
        echo "  그룹 $grp — 이미 있음"
    else
        groupadd "$grp"
        echo "  그룹 $grp — 생성"
    fi
done

# 계정
for user in agent-admin agent-dev agent-test; do
    if id "$user" >/dev/null 2>&1; then
        echo "  계정 $user — 이미 있음"
    else
        useradd --create-home --shell /bin/bash "$user"
        echo "  계정 $user — 생성"
    fi
done

# 그룹 소속
#   agent-common: admin, dev, test
#   agent-core  : admin, dev
usermod -aG agent-common agent-admin
usermod -aG agent-common agent-dev
usermod -aG agent-common agent-test
usermod -aG agent-core   agent-admin
usermod -aG agent-core   agent-dev

echo
echo "== 확인 =="
for user in agent-admin agent-dev agent-test; do
    id "$user"
done
