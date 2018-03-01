#!/bin/sh
set -xe

if ! command -v "docker-compose" >/dev/null 2>&1; then
    wget -O /usr/bin/docker-compose \
        "$(wget -q -O- https://api.github.com/repos/docker/compose/releases/latest | \
            awk '/browser_download_url/ {gsub("\"", ""); print $2}' | \
            grep Linux | grep -v sha)"
fi

chmod +x /usr/bin/docker-compose
docker-compose --version
