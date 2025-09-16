#!/bin/bash
#
# Written by Alexnader K
#

. ./defaults.conf

SCAN_OUTPUT_STEP=10000  # in Hz
SCAN_POWER_NOISE_LEVEL_INIT=-69 # initial noise level
SCAN_POWER_THRESHOLD=5 # signal is detected if its power is above noise level + this value

SCANNER_OUT_PORT=5676
SCANNER_COM_PORT=5677
DECODER_PORT=5678
DECODER_BROADCAST_IP=127.255.255.255 # broadcasted locally by default
DEBUG_PORT=5675

SLOT_TIMEOUT=10 # i.e 30 seconds *10 = 5 minutes
SLOT_ACTIVATE_TIME=4 # 4 * 5 seconds = 20 seconds min activity
MAX_SLOTS=6 # this value should be MAX_FQ - 1 (MAX_FQ is defined in the iq_base.h)

IQ_SERVER_PATH="../iq_svcl"
DECODERS_PATH="../decoders"
PATH="$PATH:$IQ_SERVER_PATH:$DECODERS_PATH"

SCRIPT_DEPENDENCIES=(rtl_sdr aplay sox jq gawk bash socat iq_server iq_client)
SUPPORTED_DECODERS=(rs41mod rs92mod dfm09mod m10mod c50dft mp3h1mod)
SCRIPT_DEPENDENCIES+=(${SUPPORTED_DECODERS[@]})

show_error_exit()
{
  echo "$1" >&2
  echo "For help: $(basename $0) -h" >&2
  exit 2
}

show_dependencies()
{
  local dep
  for dep in ${SCRIPT_DEPENDENCIES[@]}; do
    printf "%s " $dep
  done
  printf "\n"
}

check_dependencies()
{
  local dep
  for dep in ${SCRIPT_DEPENDENCIES[@]}; do
    [[ -z "$(which $dep)" ]] && {
      show_error_exit "Unmet dependency: missing $dep program"
    }
  done

  # decoders aren't checked. Make sure to compile them first
}

show_usage()
{
cat <<HEREDOC
This script receives and decodes several sondes with only one rtl dongle

Usage: $(basename $0) -f 403405000 -s 2400000 -P 35 -g 40 -t 4
       - I set the tuning frequenty in the middle of $SCAN_OUTPUT_STEP
       - Sample rate is the maximum 2400000 Hz to improve SNR
       - My rtl receiver has 35 PPM
       - I set gain to 40 but I guess the gain could be set to 0 - automatic gain
       - Signal threshold is set to 4 - a signal is considered active if its power
         is 4dB above the noise signal

Script output:
- local UDP port 5676 the power measuremnts in json form each 5 seconds:
  {"response_type":"log_power","samplerate":2400000,"tuner_freq":403405000,"result":"-77.9 ..."} 
  where "result" has SCAN_BINS values.
- local UDP port 5678 decoders output in json form:
  {"type":"RS41","frame":5174,"id":"S3440233", ...}

Options:
  -h prints this help message
  -f tuner tune frequency
  -s tuner sample rate
  -g tuner gain (0 - auto gain)
  -P tuner PPM
  -t power threshold
  -b broadcast decoder JSON output to the local network (port 5678)

Following programs are required to start the script:
$(show_dependencies)
HEREDOC
}

debug()
{
  local now_date
  [[ "-d" = "$1" ]] && {
    shift
    now_date=$(date +%Y%m%d-%H%M%S\ )
  }
  [[ -n "$1" ]] && {
    echo "${now_date}$@" | socat -u - UDP4-DATAGRAM:127.255.255.255:$DEBUG_PORT,broadcast,reuseaddr
  }
}

check_dependencies

OPTIND=1 #reset index
while getopts "bha:p:f:s:g:p:P:t:" opt; do
  case $opt in
     h)  show_usage; exit 0; ;;
     a)  address="$OPTARG" ;;  # not used atm
     p)  port="$OPTARG" ;;     # not used atm
     f)  TUNER_FREQ="$OPTARG" ;;
     s)  TUNER_SAMPLE_RATE="$OPTARG" ;;
     g)  TUNER_GAIN="$OPTARG" ;;
     P)  DONGLE_PPM="$OPTARG" ;;
     t)  SCAN_POWER_THRESHOLD="$OPTARG" ;;
     b)  do_broadcast=1 ;;
     \?) show_error_exit ;;
     :)  show_error_exit "Option -$OPTARG requires an argument" ;;
  esac
done
shift "$((OPTIND-1))"
 
[[ -n "$TUNER_FREQ" && ! "$TUNER_FREQ" -eq 0 ]] || show_error_exit "Wrong frequency"
[[ ! "$TUNER_SAMPLE_RATE" -eq 0 ]] || show_error_exit "Wrong sample rate"

DECIMATE=$((TUNER_SAMPLE_RATE/DEMODULATOR_OUTPUT_FREQ))
[[ "$((DECIMATE*DEMODULATOR_OUTPUT_FREQ))" -ne "$TUNER_SAMPLE_RATE" ]] && show_error_exit "Sample rate should be multiple of $DEMODULATOR_OUTPUT_FREQ"
SCAN_BINS=$(awk -v tsr="$TUNER_SAMPLE_RATE" 'BEGIN{print lshift(1, int(log(tsr/400)/log(2)))}')

AUDIO_OUTPUT_CMD="tee >(aplay -r $DEMODULATOR_OUTPUT_FREQ -f S16_LE -t wav -c 1 -B 500000 &> /dev/null)"
[[ "yes" = "$AUDIO_OUTPUT" ]] || AUDIO_OUTPUT_CMD="cat -"
SOX_IF_FILTER_CMD="sox -t wav - -t wav - highpass 10 gain +5"
[[ "yes" = "$SOX_IF_FILTER" ]] || SOX_IF_FILTER_CMD="cat -"

[[ "$do_broadcast" = "1" ]] && {
  # try to detect the local network ip/24 and update DECODER_BROADCAST_IP
  # in case of a complex network config edit DECODER_BROADCAST_IP manually
  # and skip -b option
  [[ -n "$(which ip)" ]] && {
    iface_name="$(\ip -j r | jq -rc '.[] | select(.dst == "default").dev')"
    [[ -n "$iface_name" ]] && {
      bcast_addr="$(\ip -j a | jq -rc '.[] | select(.ifname == "'"$iface_name"'").addr_info[]|select(.broadcast).broadcast')"
      [[ -n "$bcast_addr" ]] && {
        DECODER_BROADCAST_IP="$bcast_addr"
echo "BCAST ADDR: $DECODER_BROADCAST_IP"
      }
    }
  }
}

cleanup()
{
  local children child
  children="$1 $2 $3 $(get_children_pids $1) $(get_children_pids $2) $(get_children_pids $3)"
  kill $children &>/dev/null;wait $children &>/dev/null
}

# Power scanning using iq_server.
# NOTE that the following needs to be changes on the iq_server side for it to work:
# 1. Set nuber of bins be 4096 instead of 16384 in the iq_base.c
# -#define HZBIN 100 # hz per bin -> lshift(1, int(log(2400000/100)/log(2))) = 16384
# +#define HZBIN 400 # hz per bin -> lshift(1, int(log(2400000/400)/log(2))) = 4096
# 2. Set averaging time to be 5 seconds instead of 2 in the iq_server.c
# -#define FFT_SEC 2
# +#define FFT_SEC 5
# 3. Continues scanning mode shall be integrated into the iq_server and iq_client.
#    This feature exist currently only in my repository
scan_power_iq()
{
   "$IQ_SERVER_PATH"/iq_client --fftc /dev/stdout | \
   tee >(
    awk -v f=$TUNER_FREQ -v bins="$SCAN_BINS" -v sr="$TUNER_SAMPLE_RATE" '
      {printf("{\"response_type\":\"log_power\",\"samplerate\":%d,\"tuner_freq\":%d,\"result\":\"%s\"}\n", sr, f, $0);
      fflush()}' |
    socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_OUT_PORT,broadcast,reuseaddr
   ) |
   awk -F',' -v f=$TUNER_FREQ -v sr=$TUNER_SAMPLE_RATE -v bins=$SCAN_BINS '
     BEGIN{fstep=sr/bins;fstart=f-sr/2;}
     { for(i=1;i<=NF;++i){printf("%d %.2f\n", fstart+fstep*(i-1), $i)};print;fflush()}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v step=$((TUNER_SAMPLE_RATE/SCAN_BINS)) '
     BEGIN{idx=1}
     {if(length($2)!=0){a[idx++]=$2;if(($1-outstep*int($1/outstep))<step){print $0}}
      else{print;if(idx>1){asort(a);print a[int(idx/2)]} idx=1;};
      fflush();}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v nl=$SCAN_POWER_NOISE_LEVEL_INIT -v thr=$SCAN_POWER_THRESHOLD '
     {if (length($2)!=0){if(int($2)>(nl+thr)){print outstep*int(int($1)/outstep)" "$2;fflush()}}
      else if(length($1)!=0) {nl=$1}}'
# This awk command taxes CPU a bit more but it chooses closest freq to the SCAN_OUTPUT_STEP
# by looking not only above the SCAN_OUTPUT_STEP like it's done above but also below
# awk  -v outstep="$SCAN_OUTPUT_STEP" -v step=$((TUNER_SAMPLE_RATE/SCAN_BINS)) '
#    BEGIN{idx=1}
#    {if(length($2)!=0){a[idx++]=$2;intf=outstep*int($1/outstep);d=$1-intf;if(d<step){if(length(pr)){split(pr,pra," ");if(intf-pra[1]<d){print pr}else{print $0}}else{print $0}}}
#     else{print;if(idx>1){asort(a);print a[int(idx/2)]} idx=1;};
#     fflush();pr=$0}' | \
#     }'
}

# Alternative signal scanning method. It finds peaks in the power scan log.
# Basically it removes DC component from the power coefficients and then
# checks for coefficients that are SCAN_POWER_THRESHOLD above zero.
# A peak should also be at least SCAN_SIGNAL_MIN_WIDTH wide which corresponds to
# SCAN_SIGNAL_MIN_WIDTH * TUNER_SAMPLE_RATE/SCAN_BINS Hz. Minimal width for RS41
# I've seen was 10, so I set it to 8 by default.
scan_power_peaks()
{
    local SCAN_DC_REMOVAL_AVERAGING=100 # average over so many spectrum coefficients
    local SCAN_SIGNAL_MIN_WIDTH=8 # a signal should be at least this wide (8*samplerate/bins Hz)
    local SCAN_OUTPUT_STEP=2000   # minimum scan distance between signals. I'd say 2000 Hz should be the minimum

    "$IQ_SERVER_PATH"/iq_client --fftc /dev/stdout | \
    tee >(
     awk -v f=$TUNER_FREQ -v bins="$SCAN_BINS" -v sr="$TUNER_SAMPLE_RATE" '
       {printf("{\"response_type\":\"log_power\",\"samplerate\":%d,\"tuner_freq\":%d,\"result\":\"%s\"}\n", sr, f, $0);
       fflush()}' |
     socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_OUT_PORT,broadcast,reuseaddr
    ) |
    awk -F',' -v tf=$TUNER_FREQ -v sr=$TUNER_SAMPLE_RATE -v sb=$SCAN_BINS -v thr=$SCAN_POWER_THRESHOLD \
            -v msw=$SCAN_SIGNAL_MIN_WIDTH -v al=$SCAN_DC_REMOVAL_AVERAGING -v ost=$SCAN_OUTPUT_STEP '
    BEGIN{count=0}
    {
      sum=$1;
      for(i=2;i<=NF;++i) {
        sum += ($i-sum)/al;
        if(($i-sum)>thr) {
          if(count==0){idx=i-1;}
          ++count;
        }
        else {
          if ( (count<msw) && ($(i+count/2)-sum)>thr ) {
            ++count;
            continue;
          }
          if(count>=msw) {
            idx+=(count/2);
            peak_freq=(tf-sr/2)+int(sr/sb*idx);
            peak_freq=ost*int((peak_freq+500)/ost);
            printf("%d %.2f\n", peak_freq, $idx);
            fflush();
          }
          count=0;
        }
      }
    }'
}

start_decoder()
{
  local decoder bw

  case "$1" in
    RS41) decoder="$DECODERS_PATH/rs41mod --json --ptu --ecc3";bw=10 ;;
    RS92) decoder="$DECODERS_PATH/rs92mod --json --ptu";bw=10 ;;
    DFM9) decoder="$DECODERS_PATH/dfm09mod --json --ptu --ecc2";[ -n "$2" -a "$2" -lt 0 ] && decoder="$decoder -i";bw=10 ;;
     M10) decoder="$DECODERS_PATH/m10mod --json --ptu";bw=19.2 ;;
  C34C50) decoder="$DECODERS_PATH/c50dft --json --ptu -d1";bw=19.2 ;;
     MRZ) decoder="$DECODERS_PATH/mp3h1mod --json --ptu --ecc";bw=12 ;;
       *) decoder="(cat /dev/stdin >/dev/null)"; debug "ERROR: Unsupported sonde type: $1" ;;
  esac

  [ "$1" = "RS92" ] && {
    # check if ephemeridis file exist and not older than EPHEM_MAX_AGE_SEC
    [[ -s "$EPHEM_FILE" && "$(($(date +%s)-$(date -r $EPHEM_FILE +%s)))" -gt "$EPHEM_MAX_AGE_SEC" ]] && \rm $EPHEM_FILE
    [[ -s "$EPHEM_FILE" ]] || ./getephemeris.sh
    [[ -s "$EPHEM_FILE" ]] || {
      [[ -s "$ALMANAC_FILE" && "$(($(date +%s)-$(date -r $ALMANAC_FILE +%s)))" -gt "$ALMANAC_MAX_AGE_SEC" ]] && \rm $ALMANAC_FILE
      [[ -s "$ALMANAC_FILE" ]] || ./getsemalmanac.sh "$ALMANAC_FILE"
    }
    if [[ -s "$EPHEM_FILE" ]]; then
      decoder="$decoder -e $EPHEM_FILE"
    else
      if [[ -s "$ALMANAC_FILE" ]]; then
        decoder="$decoder -a $ALMANAC_FILE"
      else
        decoder="(cat /dev/stdin >/dev/null)"
      fi
    fi
  }

  "$IQ_SERVER_PATH"/iq_fm --lpbw $bw - $DEMODULATOR_OUTPUT_FREQ 32 --bo 16 --wav |
  eval "$SOX_IF_FILTER_CMD" |
  eval "$AUDIO_OUTPUT_CMD" |
  eval "$decoder >/dev/stderr"
}

decode_sonde_with_type_detect()
{
    "$IQ_SERVER_PATH"/iq_client --freq $(calc_bandpass_param "$(($1-TUNER_FREQ))" "$TUNER_SAMPLE_RATE") |
    (type=$(timeout 60 "$DECODERS_PATH"/dft_detect --iq - $DEMODULATOR_OUTPUT_FREQ 32 | awk -F':' '{printf("%s %d", $1,100*$2)}');
             debug "Type detected: $type on frequency $1"
             if [[ -z "$type" ]]; then
               (flock 200; echo "KILL $1") 200>$MUTEX_LOCK_FILE | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr;cat - >/dev/null;
             else start_decoder $type;
             fi) &>/dev/stdout |
    grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"version":"2.42","freq":"'"$1"'"}' |
    socat -u - UDP4-DATAGRAM:$DECODER_BROADCAST_IP:$DECODER_PORT,broadcast,reuseaddr
}


declare -A actfreq # active frequencies
declare -A slots   # active slots

(socat -u UDP-RECVFROM:$SCANNER_COM_PORT,fork,reuseaddr - | while read LINE; do
  case "$LINE" in
    TIMER30)
       debug -d "----------------------------------------"
       for freq in "${!actfreq[@]}"; do 
         debug "timer: actfreq[$freq] is ${actfreq[$freq]}"
         actfreq[$freq]=$((actfreq[$freq]-1))
         [[ "${actfreq[$freq]}" -gt "$SLOT_TIMEOUT" ]] && actfreq[$freq]=$SLOT_TIMEOUT
         if [[ "${actfreq[$freq]}" -le 0 ]]; then
           # deactivate slot
           [[ -z "${slots[$freq]}" ]] || {
             debug "Deactivating slot for freq $freq"
             cleanup "${slots[$freq]}"
             unset slots[$freq]
           }
           unset actfreq[$freq]
         elif [[ "${actfreq[$freq]}" -ge $SLOT_ACTIVATE_TIME ]]; then
           # activate slot
           [[ -z "${slots[$freq]}" && "${#slots[@]}" -lt $MAX_SLOTS ]] && {
             debug "Activating new slot for freq $freq"
             decode_sonde_with_type_detect "$freq" &
             slots[$freq]=$!
           }
         fi
       done
       debug "active slots: ${!slots[@]}"
       ;;
    KILL*) actfreq[${LINE#KILL }]=-100;debug "kill signal received with freq: ${LINE#KILL }" ;;
    *) freq="${LINE% *}"
       [[ -z "${_FREQ_BLACK_LIST[$freq]}" && -n "$freq" ]] && actfreq[$freq]=$((actfreq[$freq]+1))
       ;;
  esac
done) &
pid1=$!

(while sleep 30; do (flock 200;echo "TIMER30") 200>$MUTEX_LOCK_FILE | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr; done) &
pid2=$!

(sleep 5;scan_power_peaks | while read LINE;do (flock 200;echo "$LINE") 200>$MUTEX_LOCK_FILE;done | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr) &
pid3=$!

trap "cleanup $pid1 $pid2 $pid3" EXIT INT TERM

rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - |
"$IQ_SERVER_PATH"/iq_server --fft /tmp/fft.out --bo 32 --if $DEMODULATOR_OUTPUT_FREQ - $TUNER_SAMPLE_RATE 8

