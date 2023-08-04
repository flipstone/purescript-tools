FROM debian:bookworm-slim

ENV LANG="C.UTF-8" LANGUAGE="C.UTF-8" LC_ALL="C.UTF-8"

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y -qq --no-install-recommends \
      ca-certificates curl lsb-release gnupg apt-transport-https git && \
    apt-get clean

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs

RUN npm install -g npm@latest
RUN npm install -g purescript@0.15.10 purescript-psa spago grunt esbuild
