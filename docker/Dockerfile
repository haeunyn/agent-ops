# Ubuntu 22.04 LTS — 과제가 요구하는 실습 환경
#
# 왜 컨테이너인가:
#   이 미션은 SSH 포트 변경, root 로그인 차단, 방화벽 활성화, 시스템 계정 생성처럼
#   호스트에 적용하면 되돌리기 어려운 설정을 요구한다. 컨테이너 안에서 하면
#   실제 리눅스와 똑같이 동작하면서도 내 노트북 설정은 전혀 건드리지 않는다.
#   망가뜨려도 docker rm 한 번이면 처음부터 다시 할 수 있다.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server \
      ufw \
      acl \
      cron \
      sudo \
      python3 \
      procps \
      iproute2 \
      net-tools \
      iptables \
      gzip \
      findutils \
      vim-tiny \
      ca-certificates \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

# sshd 가 실행되려면 이 디렉토리가 필요하다
RUN mkdir -p /var/run/sshd

WORKDIR /opt/agent-ops
COPY setup/ /opt/agent-ops/setup/
COPY bin/   /opt/agent-ops/bin/
COPY app/   /opt/agent-ops/app/
RUN chmod +x /opt/agent-ops/setup/*.sh /opt/agent-ops/bin/*.sh

# 컨테이너를 살아 있게 유지한다.
# bash 를 메인 프로세스로 두면 docker exec 이 끊길 때 함께 죽어버린다
# (실제로 겪었다). sleep infinity 는 아무 입출력에도 영향받지 않는다.
CMD ["sleep", "infinity"]
