#!/usr/bin/env bash
# 방화벽 — 필요한 포트만 연다 (기본 차단, 예외 허용)
#
# 왜 '기본 차단'부터 시작하는가:
#   열어둔 포트 하나하나가 공격 표면이다. "일단 다 열고 위험한 것만 막자"는
#   무엇이 위험한지 다 알아야 하므로 불가능하다. 반대로 "다 막고 필요한 것만 열자"는
#   내가 아는 것만 열면 되므로 실수해도 안전한 쪽으로 실패한다.
#   이것을 'default deny' 정책이라고 한다.
#
# UFW 를 고른 이유:
#   Ubuntu 기본 도구이고 iptables 를 쉬운 말로 감싸준 것이라 규칙이 읽기 쉽다.
#   firewalld 는 RHEL 계열에서 주로 쓴다. 둘 중 하나만 쓰면 되고 섞으면 충돌한다.
set -euo pipefail

echo "== UFW 설정 =="

# 기본 정책: 들어오는 건 전부 차단, 나가는 건 허용
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing

# 과제 요구: 이 둘만 허용
ufw allow 20022/tcp comment 'SSH (changed from 22)'
ufw allow 15034/tcp comment 'Agent App'

ufw --force enable

echo
echo "== 확인 =="
ufw status verbose

# ── 방화벽 상태 조회 권한 (최소 권한 sudo) ──────────────────────
# 문제: ufw status 는 root 만 실행할 수 있다. 그런데 monitor.sh 는
#       cron 에서 agent-admin 으로 돌기 때문에 상태를 읽지 못하고
#       "방화벽이 꺼져 있다"는 **거짓 경고**를 낸다.
#       모니터링에서 거짓 경고는 단순한 흠이 아니다. 경고에 무뎌지게 만들어서
#       진짜 장애가 왔을 때 아무도 안 보게 된다(alert fatigue).
#
# 해결: agent-admin / agent-dev 에게 'ufw status' **딱 하나만**
#       비밀번호 없이 실행할 수 있게 허용한다.
#       `NOPASSWD: ALL` 로 다 열어주면 사실상 root 를 준 것이나 같다.
#       명령 하나만 지정하는 것이 최소 권한 원칙이다.
echo
echo "== 방화벽 조회용 sudo 규칙 등록 =="
SUDOERS=/etc/sudoers.d/agent-monitor
UFW_BIN="$(command -v ufw || echo /usr/sbin/ufw)"
cat > "$SUDOERS" <<RULE
# monitor.sh 가 방화벽 상태만 읽을 수 있도록 허용 (setup/04_firewall.sh 생성)
agent-admin ALL=(root) NOPASSWD: ${UFW_BIN} status
agent-dev   ALL=(root) NOPASSWD: ${UFW_BIN} status
RULE
chmod 440 "$SUDOERS"
visudo -cf "$SUDOERS"
echo "  등록: $SUDOERS"
