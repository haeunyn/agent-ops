# agent-ops

코디세이 본과정 미션 **B4-1 — 컴퓨터가 알아서 자기 상태를 점검하게 만들기**

Ubuntu 22.04 환경에서 **권한 관리 · 네트워크 보안 · 시스템 관제 자동화**를
직접 구성한 결과물입니다. 자동화 스크립트는 과제 제약대로 **Bash 로만** 작성했습니다.

## 빠른 시작

```bash
./run.sh up         # 컨테이너 빌드 + 전체 설정 (계정/권한/SSH/방화벽/cron)
./run.sh app        # 앱 실행 → Boot Sequence 확인
./run.sh monitor    # monitor.sh 1회 실행
./run.sh report     # 보너스 1 — 통계 리포트
./run.sh archive    # 보너스 2 — 로그 보존 정책
./run.sh evidence   # 제출용 증거 자료 전체 수집
./run.sh shell      # 컨테이너 접속
./run.sh down       # 정리
```

Docker(OrbStack 또는 Docker Desktop)만 있으면 됩니다.

## 왜 컨테이너인가

이 미션은 SSH 포트 변경, root 로그인 차단, 방화벽 활성화, 시스템 계정 생성을
요구합니다. 쓰던 노트북에 적용하면 되돌리기 어렵고, 잘못하면 내 컴퓨터에
접속하지 못하게 될 수도 있습니다.

컨테이너 안에서 하면 **실제 Ubuntu 와 똑같이 동작하면서**(진짜 `useradd`,
진짜 `ufw`, 진짜 `cron`) **호스트 설정은 전혀 건드리지 않고**, 망가뜨려도
`./run.sh down && ./run.sh up` 한 번이면 처음부터 다시 할 수 있습니다.
평가자가 같은 환경을 그대로 재현할 수 있다는 것도 장점입니다.

UFW 가 iptables 규칙을 넣으려면 권한이 필요해 `cap_add: [NET_ADMIN, SYS_ADMIN]`
을 부여했습니다.

## 구성

```
run.sh                  실행 도우미
docker/
├── Dockerfile          Ubuntu 22.04 + sshd, ufw, acl, cron
└── docker-compose.yml  포트 매핑(20022, 15034) + NET_ADMIN
setup/
├── 01_users_groups.sh  계정 3개 / 그룹 2개
├── 02_directories.sh   디렉토리 · 권한 · ACL · 키 파일
├── 03_ssh.sh           SSH 20022 + root 차단
├── 04_firewall.sh      UFW default deny + 2개 포트 + 최소권한 sudo
├── 05_env.sh           환경 변수 (/etc/profile.d)
├── 06_cron.sh          crontab 매분 등록
└── 99_evidence.sh      증거 자료 수집
bin/
├── monitor.sh          ★ 핵심 산출물 — 상태 수집 및 로깅
├── report.sh           보너스 1 — 통계 리포트
└── log_archive.sh      보너스 2 — 시간 기반 보존 정책
app/
├── agent_app.py        실행 대상 앱 (아래 참고)
└── start_agent.sh      백그라운드 실행
docs/
└── 수행내역서.md        ★ 필수 제출물
```

## monitor.sh 가 하는 일

| 단계 | 내용 | 실패 시 |
|---|---|---|
| Health Check | 앱 프로세스 / 포트 15034 LISTEN | **exit 1** |
| 상태 점검 | 방화벽 활성 여부 | 경고만 |
| 자원 수집 | CPU / MEM / DISK 사용률 | — |
| 임계값 | CPU>20%, MEM>10%, DISK>80% | 경고만 |
| 로그 기록 | `/var/log/agent-app/monitor.log` | exit 2 |
| 용량 관리 | 10MB 초과 시 회전, 10개 보관 | — |

```
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent_app.py'... [OK] (PID: 512)
Checking port 15034... [OK]
Checking firewall... [OK] (ufw active)

[RESOURCE MONITORING]
CPU Usage  : 0.7%
MEM Usage  : 9.1%
DISK Used  : 1%

[INFO] Log appended: /var/log/agent-app/monitor.log
```

**종료 코드를 나눈 이유** — cron 은 0이 아닌 종료 코드를 알림으로 올립니다.
"경고"와 "장애"를 같은 코드로 만들면 알림이 쏟아져 진짜 장애를 놓칩니다.

## 권한 설계

| 계정 | 역할 | agent-common | agent-core |
|---|---|:---:|:---:|
| agent-admin | 운영/관리, cron 실행자 | ✅ | ✅ |
| agent-dev | 개발/운영, 스크립트 작성자 | ✅ | ✅ |
| agent-test | QA/테스트 | ✅ | ❌ |

| 디렉토리 | 그룹 | 접근 |
|---|---|---|
| `upload_files` | agent-common | 셋 다 R/W |
| `api_keys` | agent-core | admin·dev 만 |
| `/var/log/agent-app` | agent-core | admin·dev 만 |

실제로 막히는지 확인했습니다:

```
$ su - agent-test -c "cat .../api_keys/t_secret.key"
cat: .../t_secret.key: Permission denied
```

## 실행 대상 앱에 관하여

`app/agent_app.py` 는 코디세이가 배포하는 `agent-app.zip`(과제 PDF 8쪽의
데이터 파일)의 **대역(stand-in)** 입니다. 실제 파일을 아직 받지 못해,
PDF 6~7쪽에 명시된 **Boot Sequence 5단계 검사와 출력 형식을 그대로 구현**해
`monitor.sh` 를 개발·검증했습니다.

**실제 제공 앱을 받으면 그것으로 바꿔 실행하면 되고, `monitor.sh` 는 고칠 필요가
없습니다.** 감시 대상 프로세스 이름을 `AGENT_PROC` 환경 변수로 받기 때문입니다.

```bash
# /etc/profile.d/agent-app.sh 에서 이 한 줄만 바꾸면 됩니다
export AGENT_PROC=agent-app-linux-arm64
```

## 수행 중 겪은 문제 4가지

실제로 막혔다가 해결한 것들입니다. 자세한 내용은 [수행내역서 7절](docs/수행내역서.md)에
있습니다.

1. **`pkill` 이 자기 자신을 죽였다** — `-f` 는 명령줄 전체를 보는데, pkill 을
   호출한 셸의 명령줄에도 대상 문자열이 있었다. 대괄호 트릭(`[a]gent_app`)으로 해결.
2. **방화벽이 켜져 있는데 거짓 경고** — `ufw status` 는 root 전용인데 cron 은
   일반 계정으로 돈다. 최소 권한 sudo 규칙 + 3단 폴백으로 해결.
3. **`report.sh` 가 로그를 못 읽었다** — Ubuntu 기본 awk 는 gawk 가 아니라
   **mawk** 이고 `{n}` 구간 수량자를 지원하지 않는다. `index`/`substr` 로 교체.
4. **컨테이너가 자꾸 꺼졌다** — PID 1 을 `bash` 로 두면 EOF 에 함께 죽는다.
   `sleep infinity` 로 교체.

## 제약 사항 준수

| 요구 | 지킨 방법 |
|---|---|
| 자동화 스크립트는 **Bash 로만** | `bin/*.sh`, `setup/*.sh` 전부 Bash |
| 가능한 일반 계정으로 | monitor/report/archive 모두 agent-admin 실행 |
| 앱은 일반 계정 실행 (루트 금지) | 앱이 `uid==0` 이면 스스로 거부 |
| 제공 앱은 실행 대상 | 핵심은 `monitor.sh`. 앱은 교체 가능하게 설계 |
