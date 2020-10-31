#!/bin/bash

nc -luk 7355 | ./sondereceive.sh -w &>/dev/stdout
#nc -luk 7355 | ./sondereceive.sh -w &>/dev/stdout |
#  grep --line-buffered -E '^{'
