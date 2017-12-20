#!/bin/sh
set -xe

hostname="$(hostname)"
MINOS_EDITION="$(hostname|cut -d- -f2)"

wget -q -O- minos.io/s | sh /dev/stdin "${MINOS_EDITION}"
dpkg -l minos-"${MINOS_EDITION}"
