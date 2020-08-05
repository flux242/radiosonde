#!/bin/bash

echo "Creating Virtual Com Port: 0 and 1"

vcpath='/tmp'
socat -d -d pty,link=${vcpath}/virtualcom0,raw,echo=0 pty,link=${vcpath}/virtualcom1,raw,b4800,echo=0 &
socatpid=$!
echo "socat pid=$socatpid"
sleep 2

trap "kill $socatpid &>/dev/null; exit 0" INT TERM EXIT

echo "Starting gpsd..."
#systemctl stop gpsd.socket
#systemctl stop gpsd.service
killall -q gpsd
gpsd -D2 -b -n -N ${vcpath}/virtualcom1
