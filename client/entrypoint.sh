#!/bin/sh
if [ -n "$TOKEN" ]; then
    exec clo set token $TOKEN
fi

if [ $# -eq 0 ]; then
    exec clo "$@"
fi
