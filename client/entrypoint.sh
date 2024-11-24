#!/bin/sh
if [ -n "$TOKEN" ]; then
/clo set token $TOKEN
fi

if [ -n "$SERVER" ]; then
/clo set server $SERVER
fi

if [ -n "$HTTP" ]; then
for i in $(echo $HTTP | tr "," "\n")
do
echo "Add HTTP port $i"
/clo register http $i
done
fi

if [ -n "$HTTPS" ]; then
for i in $(echo $HTTPS | tr "," "\n")
do
echo "Add HTTPS port $i"
/clo register https $i
done
fi

if [ -n "$MINECRAFT" ]; then
for i in $(echo $MINECRAFT | tr "," "\n")
do
echo "Add MINECRAFT port $i"
/clo register minecraft $i
done
fi

if [ -n "$WEBDAV" ]; then
for i in $(echo $WEBDAV | tr "," "\n")
do
echo "Add WEBDAV port $i"
/clo register webdav $i
done
fi

if [ -n "$TCP" ]; then
for i in $(echo $TCP | tr "," "\n")
do
echo "Add TCP port $i"
/clo register tcp $i
done
fi

if [ -n "$UDP" ]; then
for i in $(echo $UDP | tr "," "\n")
do
echo "Add UDP port $i"
/clo register udp $i
done
fi

/clo "$@"
