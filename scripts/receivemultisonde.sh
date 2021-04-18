#!/bin/bash
#
# Written by Alexnader K
#

show_usage()
{
cat <<HEREDOC
This script receives and decodes several sondes with only one rtl dongle

Usage: $(basename $0) -f 403405000 -s 2400000 -P 35 -g 40 -t 5
       - I set the tuning frequenty in the middle of 10 kHz because I
         know that sondes transmit with at least 10 kHz steps. 
       - Sample rate is the maximum 2400000 Hz to improve SNR
       - My rtl receiver has 35 PPM
       - I set gain to 40 but I guess that with recent addition of the automatic
         noise floor detection the gain could be set to 0 - automatic gain
       - Signal threshold is set to 5 - a signal is considered active if its power
         is 5dB above the noise signal

Script output:
- local UDP port 5676 the power measuremnts in json form each 5 seconds:
  {"response_type":"log_power","samplerate":2400000,"tuner_freq":403405000,"result":"-77.9 ..."} 
  where "result" has SCAN_BINS values.
- local UDP port 5678 decoders output in json form:
  {"type":"RS41","frame":5174,"id":"S3440233", ...}
HEREDOC
}

show_error_exit()
{
  echo "$1" >&2
  echo "For help: $(basename $0) -h"
  exit 2
}

debug()
{
  [ -n "$1" ] && {
    echo "$@" | socat -u - UDP4-DATAGRAM:127.255.255.255:$DEBUG_PORT,broadcast,reuseaddr
  }
}

. ./defaults.conf

SCAN_BINS=4096
SCAN_OUTPUT_STEP=10000  # in Hz
SCAN_POWER_NOISE_LEVEL_INIT=-69 # initial noise level
SCAN_POWER_THRESHOLD=5 # signal is detected if its power is above noise level + this value

SCANNER_OUT_PORT=5676
SCANNER_COM_PORT=5677
DECODER_PORT=5678
DEBUG_PORT=5675

SLOT_TIMEOUT=10 # i.e 30 seconds *10 = 5 minutes
SLOT_ACTIVATE_TIME=4 # 4 * 5 seconds = 20 seconds min activity
MAX_SLOTS=5 # this value should be MAX_FQ - 1 (MAX_FQ is defined in the iq_base.h)

IQ_SERVER_PATH="../iq_svcl"
DECODERS_PATH="../decoders"

OPTIND=1 #reset index
while getopts "ha:p:f:s:g:p:P:t:" opt; do
  case $opt in
     h)  show_usage; exit 0; ;;
     a)  address="$OPTARG" ;;  # not used atm
     p)  port="$OPTARG" ;;     # not used atm
     f)  TUNER_FREQ="$OPTARG" ;;
     s)  TUNER_SAMPLE_RATE="$OPTARG" ;;
     g)  TUNER_GAIN="$OPTARG" ;;
     P)  DONGLE_PPM="$OPTARG" ;;
     t)  SCAN_POWER_THRESHOLD="$OPTARG" ;;
     \?) exit 1 ;;
     :)  echo "Option -$OPTARG requires an argument" >&2;exit 1 ;;
  esac
done
shift "$((OPTIND-1))"
 
[ -n "$TUNER_FREQ" ] && [ ! "$TUNER_FREQ" -eq 0 ] || show_error_exit "Wrong frequency"
[ ! "$TUNER_SAMPLE_RATE" -eq 0 ] || show_error_exit "Wrong sample rate"

DECIMATE=$((TUNER_SAMPLE_RATE/DEMODULATOR_OUTPUT_FREQ))
[ "$((DECIMATE*DEMODULATOR_OUTPUT_FREQ))" -ne "$TUNER_SAMPLE_RATE" ] && show_error_exit "Sample rate should be multiple of $DEMODULATOR_OUTPUT_FREQ"


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

start_decoder()
{
  local decoder bw

  case "$1" in
    RS41) decoder="$DECODERS_PATH/rs41mod --ptu --ecc --crc --json /dev/stdin > /dev/stderr";bw=10 ;;
    RS92) decoder="$DECODERS_PATH/rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr";bw=10 ;;
    DFM9) decoder="tee >($DECODERS_PATH/dfm09mod --ptu --ecc --json /dev/stdin > /dev/stderr) | "$DECODERS_PATH"/dfm09mod --ptu --ecc --json -i /dev/stdin > /dev/stderr";bw=10 ;;
     M10) decoder="$DECODERS_PATH/m10mod --ptu --json > /dev/stderr";bw=19.2 ;;
  C34C50) decoder="tee >($DECODERS_PATH/c34dft -d1 --ptu --json /dev/stdin > /dev/stderr) | "$DECODERS_PATH"/c50dft -d1 --ptu --json /dev/stdin > /dev/stderr";bw=19.2 ;;
     MRZ) decoder="$DECODERS_PATH/mp3h1mod --ptu --ecc --json  dev/stdin > /dev/stderr";bw=12 ;;
       *) ;;
  esac

  [ "$1" = "RS92" ] && {
    # check if ephemeridis file exist and not older than EPHEM_MAX_AGE_SEC
    [ -s "$EPHEM_FILE" ] && [ "$(($(date +%s)-$(date -r $EPHEM_FILE +%s)))" -gt "$EPHEM_MAX_AGE_SEC" ] && \rm $EPHEM_FILE
    [ -s "$EPHEM_FILE" ] || ./getephemeris.sh
    [ -s "$EPHEM_FILE" ] || {
      [ -s "$ALMANAC_FILE" ] && [ "$(($(date +%s)-$(date -r $ALMANAC_FILE +%s)))" -gt "$ALMANAC_MAX_AGE_SEC" ] && \rm $ALMANAC_FILE
      [ -s "$ALMANAC_FILE" ] || ./getsemalmanac.sh "$ALMANAC_FILE"
    }
    [ -s "$EPHEM_FILE" ] || {
      if [ -s "$ALMANAC_FILE" ]; then
        decoder="$DECODERS_PATH/rs92mod -a "$ALMANAC_FILE" --crc --ecc --json /dev/stdin > /dev/stderr"
      else
        decoder="cat /dev/stdin >/dev/null"
      fi
    }
  }

  "$IQ_SERVER_PATH"/iq_fm --lpbw $bw - 48000 32 --bo 16 |
  sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
  tee >(aplay -r 48000 -f S8 -t wav -c 1 -B 500000 &> /dev/null) |
  eval "$decoder"
}

decode_sonde_with_type_detect()
{
    "$IQ_SERVER_PATH"/iq_client --freq $(calc_bandpass_param "$(($1-TUNER_FREQ))" "$TUNER_SAMPLE_RATE") |
    (type=$(timeout 60 "$DECODERS_PATH"/dft_detect --iq - 48000 32 | awk -F':' '{print $1}');
             if [ -z "$type" ]; then
               echo "KILL $1"|socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr;cat - >/dev/null;
             else start_decoder "$type";
             fi) &>/dev/stdout |
    grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"freq":"'"$1"'"}' |
    socat -u - UDP4-DATAGRAM:127.255.255.255:$DECODER_PORT,broadcast,reuseaddr
}


declare -A actfreq # active frequencies
declare -A slots   # active slots

(socat -u UDP-RECVFROM:$SCANNER_COM_PORT,fork,reuseaddr - | while read LINE; do
  case "$LINE" in
    TIMER30)
       for freq in "${!actfreq[@]}"; do 
         debug "timer: actfreq[$freq] is ${actfreq[$freq]}"
         actfreq[$freq]=$((actfreq[$freq]-1))
         [ "${actfreq[$freq]}" -gt "$SLOT_TIMEOUT" ] && actfreq[$freq]=$SLOT_TIMEOUT
         if [ "${actfreq[$freq]}" -le 0 ]; then
           # deactivate slot
           [ -z "${slots[$freq]}" ] || {
             debug "Deactivating slot $slot with freq $freq"
             cleanup "${slots[$freq]}"
             unset slots[$freq]
           }
           unset actfreq[$freq]
         elif [ "${actfreq[$freq]}" -ge $SLOT_ACTIVATE_TIME ]; then
           # activate slot
           [ -z "${slots[$freq]}" ] && [ "${#slots[@]}" -lt $MAX_SLOTS ] && {
             debug "Activating slot $slot with freq $freq"
             decode_sonde_with_type_detect "$freq" &
             slots[$freq]=$!
           }
         fi
       done
       debug "active slots: ${!slots[@]}"
       debug "----------------------------------------"
       ;;
    KILL*) actfreq[${LINE#KILL }]=-100;debug "kill signal received with freq: ${LINE#KILL }" ;;
    *) freq="${LINE% *}"
       [ -z "${_FREQ_BLACK_LIST[$freq]}" ] && {
         [ -n "$freq" ] && actfreq[$freq]=$((actfreq[$freq]+1))           
       }
       ;;
  esac
done) &
pid1=$!

(while sleep 30; do echo "TIMER30" | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr; done) &
pid2=$!

(sleep 5;scan_power_iq | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr) &
pid3=$!

trap "cleanup $pid1 $pid2 $pid3" EXIT INT TERM

rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - |
"$IQ_SERVER_PATH"/iq_server --fft /tmp/fft.out --bo 32 - 2400000 8

