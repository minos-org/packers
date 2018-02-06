#!/bin/sh
set -xe

if ! command -v "docker-compose" >/dev/null 2>&1; then
    wget -O /usr/bin/docker-compose \
        https://github.com/docker/compose/releases/download/1.17.1/docker-compose-`uname -s`-`uname -m`
fi

chmod +x /usr/bin/docker-compose
docker-compose --version
