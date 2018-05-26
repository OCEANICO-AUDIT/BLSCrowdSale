#!/usr/bin/env bash
if [ ! -e "migrations" ] ; then
    mkdir migrations
fi
set -e
node_modules/.bin/truffle test "$@"
