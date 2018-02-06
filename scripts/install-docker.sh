#!/bin/sh
set -xe

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
apt-get install -y software-properties-common apt-transport-https
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce

#don't require sudo to run docker
usermod -aG docker vagrant || :
