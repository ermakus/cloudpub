#!/bin/sh
if [ -n "$TOKEN" ]; then
/clo set token $TOKEN
fi
if [ -n "$SERVER" ]; then
./clo set server $SERVER
fi
/clo "$@"
