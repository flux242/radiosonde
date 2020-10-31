#!/bin/bash

# ./receiveandplot.sh -f 404800000 -s 960000 -p 36 -g 0
#pgrep -x rtl_tcp || rtl_tcp -a 127.0.0.1 &

[ -L "/tmp/virtualcom0" ] || ./vp1.sh &

sleep 1

./sondereceive.sh $@ &>/dev/stdout |
  grep --line-buffered -E '^{' |
  tee >(jq --unbuffered -rc 'select(.lat)' | tee /dev/stderr | ./json2nmea.pl 2>/dev/null >/tmp/virtualcom0) |
  jq --unbuffered -rc 'select(.samplerate)' | ./plotpowerjson.sh
 
#
#./sondereceive.sh $@ &>/dev/stdout | \
#  grep --line-buffered -E '^{' | \
#  tee >(grep --line-buffered datetime|sed -nur 's/(.*datetime":)([^\.]+)....(.*)/\1\2\3/p' - | tee /dev/stderr | \
#        jq --unbuffered -rc 'select(.lat)|[.datetime, .lat, .lon, .alt, .vel_h, .heading]|"\(.[0]|strptime("%Y-%m-%dT%H:%M:%SZ")|strftime("%Y-%m-%d %H:%M:%S.000"))  lat: \(.[1])  lon: \(.[2])  alt: \(.[3])  vH: \(.[4])  D: \(.[5])"' | \
#        tee /dev/stderr | \
#        ./pos2nmea.pl 2>/dev/null >/tmp/virtualcom0) | \
#  jq -rc 'select(.samplerate).result' | awk '{printf("%s", $0);fflush()}' | tr ' ' '\n' | \
#  awk '{printf("%d %.1f\n",(NR-1)%1024,$0);if(0==(NR%1024)){printf("\n")};fflush()}' | \
#  ~/bin/gp/gnuplotblock.sh "0:1023;-100:-20" "400-406Mhz Power;l lw 2;red;xy"

