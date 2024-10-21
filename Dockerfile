FROM debian:stable-20240904-slim

ENV LANG="C.UTF-8" LANGUAGE="C.UTF-8" LC_ALL="C.UTF-8"

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y -qq --no-install-recommends \
      ca-certificates curl lsb-release gnupg apt-transport-https git openssh-client && \
    apt-get clean

RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

ARG NODE_MAJOR=20
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
RUN apt-get update && \
    apt-get install -qq -y --no-install-recommends nodejs && \
    apt-get clean

RUN mkdir -p ~/.ssh/ && ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts

RUN npm install -g npm@10.5.2
RUN npm install -g spago@0.93.29 purescript@0.15.15 purescript-psa@0.9.0 grunt-cli@1.5.0 esbuild@0.23.1 purs-tidy@0.11.0
