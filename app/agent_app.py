#!/usr/bin/env python3
"""Agent App — Boot Sequence 5단계를 거쳐 15034 포트를 여는 데모 애플리케이션.

⚠️ 이것은 코디세이가 배포하는 agent-app.zip 의 **대역(stand-in)** 이다.
   과제 PDF 8쪽의 데이터파일(agent-app-linux-x86 / agent-app-linux-arm64)을
   아직 받지 못한 상태에서 monitor.sh 를 개발·검증하기 위해 만들었다.
   PDF 6~7쪽에 적힌 Boot Sequence 출력 형식을 그대로 따른다.

   실제 제공 앱을 받으면 그것으로 바꿔 실행하면 된다.
   monitor.sh 는 감시 대상 프로세스 이름을 AGENT_PROC 환경변수로 받으므로
   스크립트를 고칠 필요가 없다.

과제 요구(3절)대로 다음 5가지를 검사한다:
    1. 서비스 계정으로 실행 중인가 (root 금지)
    2. 필요한 환경 변수가 모두 올바른가
    3. 키 파일이 있고 내용이 맞는가
    4. 포트를 쓸 수 있는가
    5. 로그 디렉토리에 쓸 수 있는가
"""

import os
import socket
import sys

REQUIRED_ENVS = ("AGENT_HOME", "AGENT_PORT", "AGENT_UPLOAD_DIR", "AGENT_KEY_PATH")
EXPECTED_KEY = "agent_api_key_test"
DEFAULT_LOG_DIR = "/var/log/agent-app"
LINE = "-" * 60


def step(index: int, title: str, ok: bool, detail: str) -> bool:
    """[n/5] 제목 ... [OK]/[FAIL] 형식으로 한 단계를 출력한다."""
    status = "[OK]" if ok else "[FAIL]"
    print(f"[{index}/5] {title:<38}{status}")
    print(f"... {detail}")
    return ok


def main() -> int:
    print("> Starting Agent Boot Sequence...")

    # 1) 루트로 실행하면 안 된다 — 앱이 뚫렸을 때 피해 범위를 줄이기 위해서다
    uid = os.getuid()
    user = os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
    if uid == 0:
        step(1, "Checking User Account", False,
             "Refusing to run as root. Use a service account.")
        return 1
    step(1, "Checking User Account", True,
         f"Running as service user '{user}' (uid={uid})")

    # 2) 환경 변수 — 실행 환경을 고정해 "내 컴퓨터에선 되는데" 를 막는다
    missing = [name for name in REQUIRED_ENVS if not os.environ.get(name)]
    if missing:
        step(2, "Verifying Environment Variables", False,
             f"Missing: {', '.join(missing)}")
        return 1
    step(2, "Verifying Environment Variables", True, "All required Envs correct")

    # 3) 키 파일
    key_path = os.environ["AGENT_KEY_PATH"]
    try:
        with open(key_path, encoding="utf-8") as handle:
            key = handle.read().strip()
    except OSError as exc:
        step(3, "Checking Required Files", False, f"Cannot read {key_path}: {exc}")
        return 1
    if key != EXPECTED_KEY:
        step(3, "Checking Required Files", False, "Key file content mismatch.")
        return 1
    step(3, "Checking Required Files", True,
         "Verified key file with correct key string.")

    # 4) 포트 — 미리 잡아두고 확인한다
    try:
        port = int(os.environ["AGENT_PORT"])
    except ValueError:
        step(4, "Checking Port Availability", False, "AGENT_PORT is not an integer.")
        return 1
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(("0.0.0.0", port))
        server.listen(16)
    except OSError as exc:
        step(4, "Checking Port Availability", False, f"Port {port} unavailable: {exc}")
        return 1
    step(4, "Checking Port Availability", True, f"Port {port} is available.")

    # 5) 로그 디렉토리 쓰기 권한
    log_dir = os.environ.get("AGENT_LOG_DIR", DEFAULT_LOG_DIR)
    if not os.path.isdir(log_dir) or not os.access(log_dir, os.W_OK):
        step(5, "Verifying Log Permission", False,
             f"Log directory not writable: {log_dir}")
        return 1
    step(5, "Verifying Log Permission", True,
         f"Log directory is writable: {log_dir}")

    print(LINE)
    print("All Boot Checks Passed!")
    print("Agent READY")
    sys.stdout.flush()

    # 과제 범위상 하는 일은 없다. 포트를 열어둔 채 대기한다(Ctrl+C 로 종료).
    try:
        while True:
            conn, _ = server.accept()
            conn.sendall(b"agent-app: OK\n")
            conn.close()
    except KeyboardInterrupt:
        print("\nAgent shutting down.")
        return 0
    finally:
        server.close()


if __name__ == "__main__":
    sys.exit(main())
