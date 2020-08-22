#/bin/bash

# Terminal 1
# socat -d -d TCP-LISTEN:14580 exec:./aprsfakeserver.sh,pty,stderr

# Terminal 2
# ./demodulatenfm.sh -f 144800000 -g 0 -s 2400000 -P 35 -b 6000 | \
#  sox -t wav -esigned-integer -b 16 -r 48000 - -b 16 -t wav -r 22050 -esigned-integer - | \
#  tee >(aplay -r 22050 -f S16_LE -t wav -c 1 -B 500000) | \
#  ~/projects/multimon-ng/multimon-ng -a AFSK1200 -A  - 2>/dev/null | \
#  tee /dev/stderr | socat -u - udp-datagram:0.0.0.0:30448,broadcast

# Terminal 3
# java -jar YAAC.jar

# Note: I haven't yet found a reliable clean way to terminate this script from YAAC,
#       because that darn tail command which just won't die. So use the perl version
#       instead and this bash version is there just for historical reasons


get_children_pids() {
  local cpids cpid
  [ -n "$1" ] || return
  cpids=$(pgrep -P $1|xargs)
  for cpid in $cpids; do
    printf "$cpid "
    get_children_pids $cpid
  done
}

cleanup()
{
  local children child
 
  printf "cleaning up\n" >> /tmp/aprs.out

  children="$2 $3 $4 $(get_children_pids $2) $(get_children_pids $3) $(get_children_pids $4)"
echo "killing $children" >> /tmp/aprs.out
  kill $children &>/dev/null;wait $children &>/dev/null

  [ -n "$1" -a -e "$1" ] && {
echo "removing $1" >> /tmp/aprs.out
    \rm "$1"
  }
}


UDP_LISTEN_PORT=30448
PINGMSG='# aprsfakeserver (c) 0v1'
com_fifo="/tmp/aprsfakeserver.$$.txt"

[ -p "$com_fifo" ] || mkfifo "$com_fifo"

export PINGMSG

socat -u exec:"/bin/sh -c \'while true; do echo "\""\$PINGMSG"\"";sleep 60;done\'",pty,stderr udp-datagram:0.0.0.0:${UDP_LISTEN_PORT},broadcast,reuseaddr &
pid1=$!
socat -u "/proc/$$/fd/0" udp-datagram:0.0.0.0:${UDP_LISTEN_PORT},broadcast,reuseaddr &
pid2=$!
socat -u UDP-RECVFROM:${UDP_LISTEN_PORT},fork,reuseaddr "$com_fifo" &
pid3=$!

echo "started $pid1 $pid2 $pid3" >> /tmp/aprs.out
trap "cleanup $com_fifo $pid1 $pid2 $pid3" INT TERM EXIT


tail --pid=$pid3 -f "$com_fifo" 2>/dev/null | while read LINE; do
echo "i: $LINE" >> /tmp/aprs.out
  case "$LINE" in
    user*)
      user=$(echo $LINE|awk '{print $2}')
      filter=$(echo "$LINE"|awk '/filter/{print gensub(/.*(filter.*)/,"\\1","g")}')
      result="# logresp $user verified, server N0APRS-1 $filter"
      ;;
    APRS:*) result="${LINE#APRS: }" ;;
    "") continue ;;
    QUIT*) break ;;
    *) result="$LINE" ;;
  esac
  printf "$result\n\n"
echo "o: $result" >> /tmp/aprs.out
done

