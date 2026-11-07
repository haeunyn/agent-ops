#!/usr/bin/env bash
# 디렉토리 구조와 권한 — 공유 영역과 보안 영역을 분리한다
#
# 핵심 정책:
#   upload_files  group=agent-common, 읽기/쓰기  → 셋 다 쓸 수 있다
#   api_keys      group=agent-core  ONLY         → test 는 접근 불가
#   /var/log/agent-app  group=agent-core ONLY    → 로그도 민감 정보다
#
# 권한 숫자 읽는 법:
#   2770 = rwxrws--- + setgid
#     7(소유자 rwx) 7(그룹 rwx) 0(그 외 접근 전면 차단)
#     앞의 2 는 'setgid' — 이 디렉토리 안에 새로 만들어지는 파일이
#     만든 사람의 기본 그룹이 아니라 **디렉토리의 그룹**을 물려받게 한다.
#     이게 없으면 agent-dev 가 만든 파일이 agent-dev 그룹이 되어
#     agent-admin 이 못 읽는 사고가 난다.
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

echo "== 디렉토리 생성 =="
mkdir -p "$AGENT_HOME"/{upload_files,api_keys,bin}
mkdir -p "$LOG_DIR"

# AGENT_HOME 자체는 admin 소유, core 그룹이 들어올 수 있어야 한다
chown agent-admin:agent-core "$AGENT_HOME"
chmod 2750 "$AGENT_HOME"

# 공유 영역 — 셋 다 읽고 쓴다
chown agent-admin:agent-common "$AGENT_HOME/upload_files"
chmod 2770 "$AGENT_HOME/upload_files"

# 보안 영역 — core 만
chown agent-admin:agent-core "$AGENT_HOME/api_keys"
chmod 2770 "$AGENT_HOME/api_keys"

chown agent-dev:agent-core "$AGENT_HOME/bin"
chmod 2750 "$AGENT_HOME/bin"

chown agent-admin:agent-core "$LOG_DIR"
chmod 2770 "$LOG_DIR"

echo "== ACL 설정 =="
# ACL(Access Control List)이 왜 추가로 필요한가:
#   전통적인 권한은 '소유자 / 그룹 하나 / 나머지' 세 칸뿐이다.
#   "이 그룹도 쓰게 해줘"처럼 대상이 둘 이상이면 표현할 방법이 없다.
#   ACL 은 그 제약을 풀어준다.
# -d 는 'default' — 앞으로 그 안에 만들어질 파일에 자동 적용되는 ACL이다.
setfacl -m  g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -dm g:agent-common:rwx "$AGENT_HOME/upload_files"

setfacl -m  g:agent-core:rwx   "$AGENT_HOME/api_keys"
setfacl -dm g:agent-core:rwx   "$AGENT_HOME/api_keys"
# test 는 명시적으로 차단한다(그룹에 없지만 의도를 문서화하는 효과)
setfacl -m  u:agent-test:---   "$AGENT_HOME/api_keys"

setfacl -m  g:agent-core:rwx   "$LOG_DIR"
setfacl -dm g:agent-core:rwx   "$LOG_DIR"

echo "== 키 파일 생성 =="
KEY_PATH="$AGENT_HOME/api_keys/t_secret.key"
# 제공 바이너리는 secret.key 라는 이름을 찾는다. PDF 4쪽은 t_secret.key 로 적혀 있어
# 두 이름을 모두 둔다(내용 동일). t_secret.key 는 ACL 차단 증거용으로 계속 사용.
KEY_PATH_REAL="$AGENT_HOME/api_keys/secret.key"
echo "agent_api_key_test" > "$KEY_PATH"
chown agent-admin:agent-core "$KEY_PATH"
chmod 640 "$KEY_PATH"    # 소유자 rw / 그룹 r / 나머지 없음

echo "agent_api_key_test" > "$KEY_PATH_REAL"
chown agent-admin:agent-core "$KEY_PATH_REAL"
chmod 640 "$KEY_PATH_REAL"

echo
echo "== 확인 =="
ls -ld "$AGENT_HOME" "$AGENT_HOME"/{upload_files,api_keys,bin} "$LOG_DIR"
echo
echo "-- getfacl: upload_files (공유) --"
getfacl -p "$AGENT_HOME/upload_files" 2>/dev/null | grep -v '^#'
echo "-- getfacl: api_keys (보안) --"
getfacl -p "$AGENT_HOME/api_keys" 2>/dev/null | grep -v '^#'
