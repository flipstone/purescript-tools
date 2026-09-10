# Docker Hardened Images node (Community tier). Pinned to an exact node
# version plus digest; Dependabot bumps both together. Pulling requires
# `docker login dhi.io` (Docker Hub credentials).
FROM dhi.io/node:26.8.2-debian13-dev@sha256:78ce3a9a15da054a721e2635b20ac8ab344451b1871b27415f54c58e65a87eb1

LABEL org.opencontainers.image.source="https://github.com/flipstone/purescript-tools"

# The DHI base sets en_US.UTF-8; keep the C.UTF-8 locale the previous
# image had so downstream builds see no change.
ENV LANG="C.UTF-8" LANGUAGE="C.UTF-8" LC_ALL="C.UTF-8"

# DEBIAN_FRONTEND=noninteractive is baked into the DHI base as a persistent
# ENV; restore it if this ever moves off DHI.
#
# The trailing ldconfig is the same workaround haskell-tools carries: the
# DHI base ships without /etc/ld.so.cache and apt does not regenerate it,
# so anything probing libraries via `ldconfig -p` would see an empty cache.
RUN apt-get update \
    && apt-get install -qq -y --no-install-recommends \
        ca-certificates curl git openssh-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ldconfig

RUN mkdir -p ~/.ssh/ && ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts

# The toolchain -- including the npm version itself -- is declared in
# package.json and locked in package-lock.json, so Dependabot tracks every
# tool the same way it tracks the base image. It is installed as an ordinary
# project under /opt and its .bin directory put first on PATH; the pinned npm
# therefore shadows the one bundled with node.
WORKDIR /opt/purescript-tools
COPY package.json package-lock.json .npmrc ./
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force
ENV PATH="/opt/purescript-tools/node_modules/.bin:$PATH"

# The image tag embeds the PureScript version, which scripts/build-image.sh
# reads from package.json and passes in here. Refuse to build an image whose
# installed compiler disagrees with the version its tag will claim.
ARG PURS_VERSION
RUN test -n "$PURS_VERSION" \
    && test "$(purs --version)" = "$PURS_VERSION" \
    || { echo "purs --version is '$(purs --version)' but PURS_VERSION is '$PURS_VERSION'"; exit 1; }

WORKDIR /
