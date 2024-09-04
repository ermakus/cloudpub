#!/bin/sh
RATE="1 1000 2000 3000 4000"
DURATION="60s"

cloudpub="http://127.0.0.1:5202"
FRP="http://127.0.0.1:5203"

echo warming up frp
echo GET $FRP | vegeta attack -duration 10s > /dev/null
for rate in $RATE; do
        name="frp-${rate}qps-$DURATION.bin"
        echo $name
        echo GET $FRP | vegeta attack -rate $rate -duration $DURATION > $name
        vegeta report $name
done

echo warming up cloudpub
echo GET $cloudpub | vegeta attack -duration 10s > /dev/null
for rate in $RATE; do
        name="cloudpub-${rate}qps-$DURATION.bin"
        echo $name
        echo GET $cloudpub | vegeta attack -rate $rate -duration $DURATION > $name
        vegeta report $name
done
