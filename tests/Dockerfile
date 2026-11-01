# Isolated environment for the AppMan2 test suites.
#
# The suites use a local HTTP fixture server and file:// repositories only;
# they never contact real installations, credentials or live APIs. The CI
# workflow runs them with `--network none` to make that guarantee explicit.
FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      coreutils \
      curl \
      findutils \
      git \
      python3 \
      sed \
      shellcheck \
      wget \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
