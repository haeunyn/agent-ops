#!/usr/bin/env bash
# SSH 기본 보안 — 포트 변경 + root 원격 로그인 차단
#
# 왜 포트를 바꾸는가:
#   22번은 전 세계가 아는 기본 포트다. 인터넷에 서버를 올려두면 몇 분 안에
#   자동 스캐너가 22번을 두드리며 아이디/비밀번호를 무작위로 시도한다.
#   포트를 바꾸면 그 '자동화된 소음'이 거의 사라진다.
#   ※ 이건 보안의 완성이 아니라 '소음 제거'다. 포트 스캔으로 찾아낼 수 있으므로
#     키 인증, 방화벽과 **함께** 써야 의미가 있다. (security by obscurity 한계)
#
# 왜 root 원격 로그인을 막는가:
#   공격자 입장에서 root 는 '아이디를 맞힐 필요가 없는' 계정이다.
#   비밀번호만 뚫으면 끝이고, 성공하면 즉시 시스템 전체를 잡는다.
#   일반 계정으로 로그인한 뒤 sudo 를 쓰게 하면
#   ① 아이디까지 맞혀야 하고 ② 누가 무슨 명령을 했는지 로그에 남는다.
set -euo pipefail

SSHD_CONFIG=/etc/ssh/sshd_config

echo "== SSH 설정 변경 =="
cp -n "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" 2>/dev/null || true

# 기존 줄이 있으면 바꾸고, 없으면 덧붙인다 (주석 처리된 줄도 포함해 처리)
set_option() {
    local key="$1" value="$2"
    if grep -qE "^[#[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
        sed -i -E "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
    echo "  ${key} ${value}"
}

set_option Port 20022
set_option PermitRootLogin no
set_option PasswordAuthentication yes   # 실습 환경 기준. 실제 서버는 키 인증 권장

echo
echo "== 확인 =="
grep -E "^(Port|PermitRootLogin)" "$SSHD_CONFIG"
