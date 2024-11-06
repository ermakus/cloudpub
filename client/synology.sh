#/bin/bash -e

docker volume create cloudpub-cfg

CLO="docker run -v cloudpub-cfg:/home/cloudpub --net=host -it cloudpub/cloudpub:latest"

$CLO set token $1
$CLO register http 5000
$CLO register tcp 6690
$CLO run
