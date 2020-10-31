#!/bin/bash

# ./receivedecode.sh -f 404800000 -s 960000 -p 35 -g 0

./sondereceive.sh $@ &>/dev/stdout | \
  grep --line-buffered -E '^{' | \
  jq --unbuffered -rc 'select(.lat)'   

#./receivesonde2.sh $@ &>/dev/stdout 
