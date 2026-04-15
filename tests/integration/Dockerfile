FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash coreutils findutils grep sed gawk \
      passwd adduser login util-linux \
      bats python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/claude-share
COPY . /opt/claude-share

RUN chmod +x /opt/claude-share/bin/claude-share \
 && ln -s /opt/claude-share/bin/claude-share /usr/local/bin/claude-share

CMD ["bats", "tests/integration/e2e.bats"]
