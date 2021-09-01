#!/bin/bash

# This is just a wrapper to start the receivemultisonde.sh script.
# Basically it is needed to restart the receivemultisonde.sh if it
# gets stuck. Sometimes really rarely the main processing block of
# that script stops working. I can't find a reason for the problem
# so I simply start listening on the debug port and if no output
# is given after defined timeout period then I restart the script.

. ./defaults.conf

TIMEOUT=120  # restart after that amount of seconds
DEBUG_PORT=5675

echo "Starting the ./receivemultisonde.sh"
(./receivemultisonde.sh $@) &
pid1=$!

trap "kill $pid1" EXIT INT TERM

socat -u UDP-RECVFROM:$DEBUG_PORT,fork,reuseaddr - | 
while true; do
   read -t $TIMEOUT LINE
  if [ "$?" -gt 128 ]; then
    echo "Timeout detected, restarting the $pid1"
    kill $(get_children_pids $pid1)
    (./receivemultisonde.sh $@) &
    pid1=$!
  fi
done

