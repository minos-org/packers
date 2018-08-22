#!/bin/sh
set -xe

#setup default python if non has been stablished
if [ ! -e /usr/bin/python ]; then
    if   [ -e /usr/bin/python3 ]; then
        ln -s /usr/bin/python3 /usr/bin/python
    elif [ -e /usr/bin/python2 ]; then
        ln -s /usr/bin/python2 /usr/bin/python
    fi
fi
