#!/bin/bash
#
# Written by Alexnader K
#

. ./defaults.conf

SCAN_BINS=4096
SCAN_OUTPUT_STEP=10000  # in Hz
SCAN_AVERAGE_TIMES=100
SCAN_UPDATE_RATE=1
SCAN_UPDATE_RATE_DIV=5 # 5 seconds
SCAN_POWER_THRESHOLD=-69

SCANNER_OUT_PORT=5676
SCANNER_COM_PORT=5677
DECODER_PORT=5678

MAX_SLOTS=10 # maximum number of rx slots
SLOT_TIMEOUT=10 # i.e 30 seconds *10 = 5 minutes
SLOT_ACTIVATE_TIME=4 # 4 * 5 seconds = 20 seconds min activity

OPTIND=1 #reset index
while getopts "ha:p:f:s:g:p:P:t:" opt; do
  case $opt in
     h)  show_usage $(basename $0); exit 0; ;;
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
 
[ ! "$TUNER_FREQ" -eq 0 ] || show_error_exit "Wrong frequency"
[ ! "$TUNER_SAMPLE_RATE" -eq 0 ] || show_error_exit "Wrong sample rate"

DECIMATE=$((TUNER_SAMPLE_RATE/DEMODULATOR_OUTPUT_FREQ))
[ "$((DECIMATE*DEMODULATOR_OUTPUT_FREQ))" -ne "$TUNER_SAMPLE_RATE" ] && show_error_exit "Sample rate should be multiple of $DEMODULATOR_OUTPUT_FREQ"


cleanup()
{
  local children child
  children="$1 $2 $(get_children_pids $1) $(get_children_pids $2)"
  kill $children &>/dev/null;wait $children &>/dev/null
}

scan_power()
{
  ./csdr convert_u8_f | \
  ./csdr fft_cc $SCAN_BINS $((TUNER_SAMPLE_RATE/(SCAN_UPDATE_RATE*SCAN_AVERAGE_TIMES/SCAN_UPDATE_RATE_DIV))) | \
  ./csdr logaveragepower_cf -70 $SCAN_BINS $SCAN_AVERAGE_TIMES | \
  ./csdr fft_exchange_sides_ff $SCAN_BINS | \
  ./csdr dump_f | tr ' ' '\n' | \
   tee >(
    awk -v bins=$SCAN_BINS '{printf("%.1f ",$0);if(0==(NR%bins)){printf("\n")};fflush()}' |
    awk -v f=$TUNER_FREQ -v bins="$SCAN_BINS" -v sr="$TUNER_SAMPLE_RATE" '
      {printf("{\"response_type\":\"log_power\",\"samplerate\":%d,\"tuner_freq\":%d,\"result\":\"%s\"}\n", sr, f, $0);
      fflush()}' |
    socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_OUT_PORT,broadcast,reuseaddr
   ) |
   awk -v f=$TUNER_FREQ -v sr=$TUNER_SAMPLE_RATE -v bins=$SCAN_BINS '
     BEGIN{fstep=sr/bins;fstart=f-sr/2;print fstep;print fstart}
     {printf("%d %.1f\n",fstart+fstep*((NR-1)%bins),$0);
      if(0==(NR%bins)){printf("\n")};fflush()}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v step=$((TUNER_SAMPLE_RATE/SCAN_BINS)) '
     function abs(x){return (x<0)?-x:x}
     {if(length($1)!=0){if(abs($1-outstep*int($1/outstep)<step)){print $0}}
      else{print};
      fflush();}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v thr=$SCAN_POWER_THRESHOLD '{if (length($2)!=0){if(int($2)>thr){print outstep*int(int($1)/outstep)" "$2;fflush()}}}'
}

# the line below should come before the m10mod if needed.
#      tee >(c50dft -d1 --ptu --json /dev/stdin > /dev/stderr) | \
decode_sonde()
{
  local bpf3=$(calc_bandpass_param 5000 $DEMODULATOR_OUTPUT_FREQ)
  local bpf10=$(calc_bandpass_param 10000 $DEMODULATOR_OUTPUT_FREQ)
  (
    ./csdr convert_u8_f | \
    ./csdr shift_addition_switchable_cc --fifo "$1" | \
    ./csdr fir_decimate_cc $DECIMATE 0.005 HAMMING | \
    tee >(
      ./csdr bandpass_fir_fft_cc -$bpf10 $bpf10 0.02 | \
      ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 | \
      sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 8 -c 1 -t wav - highpass 10 gain +5 | \
      ./m10mod --ptu --json > /dev/stderr
    ) | \
    ./csdr bandpass_fir_fft_cc -$bpf3 $bpf3 0.02 | \
    ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 | \
    sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 8 -c 1 -t wav - highpass 10 gain +5 | \
    tee >(./dfm09mod --ptu --ecc --json -vv /dev/stdin > /dev/stderr) \
        >(./dfm09mod --ptu --ecc --json -i /dev/stdin > /dev/stderr) \
        >(./rs41mod --ptu --ecc --crc --json -vv /dev/stdin > /dev/stderr) \
        >(./rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr) | \
    aplay -r 48000 -f S8 -t wav -c 1 -B 500000 &> /dev/null
  ) &>/dev/stdout | while read LINE; do
      tmp_freq="$(echo "$LINE" | awk -F: '/^shift_addition_frequency/{print $2}')"
      [ -n "$tmp_freq" ] && {
        # due to float (un)precision, calculated freq could be +-1, so it is corrected
        freq=$(awk -v f="$tmp_freq" -v sr="$TUNER_SAMPLE_RATE" -v tf="$TUNER_FREQ" 'BEGIN{printf 1000*int((1+tf-int(f*sr))/1000)}')
      }
      echo "$LINE" | grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"freq":"'"$freq"'"}' | \
      (flock 200; socat -u - UDP4-DATAGRAM:127.255.255.255:$DECODER_PORT,broadcast,reuseaddr) 200>$MUTEX_LOCK_FILE
    done
}

declare -A actfreq # active frequencies

# create fifos
FIFO_BASE_NAME='/tmp/sonde_scanner_'
for ((fifo=1;fifo<=MAX_SLOTS;fifo++)); do
  fifo_name="${FIFO_BASE_NAME}${fifo}.pipe"
  [ -e "$fifo_name" ] && \rm "$fifo_name"    
  mkfifo "$fifo_name"
  fifos[$fifo]="$fifo_name"
done
 
(socat -u UDP-RECVFROM:$SCANNER_COM_PORT,fork,reuseaddr - | while read LINE; do
  case "$LINE" in
    TIMER30)
       for freq in "${!actfreq[@]}"; do 
echo "timer: actfreq[$freq] is ${actfreq[$freq]}" >> /tmp/debug.out
         actfreq[$freq]=$((actfreq[$freq]-1))
         [ "${actfreq[$freq]}" -gt "$SLOT_TIMEOUT" ] && actfreq[$freq]=$SLOT_TIMEOUT
         if [ "${actfreq[$freq]}" -eq 0 ]; then
           # deactivate slot
           for slot in "${!slots[@]}"; do
             [ "$freq" = "${slots[$slot]}" ] && {
echo "Deactivating slot $slot with freq $freq" >> /tmp/debug.out
               echo "1.0" > "${fifos[$slot]}"
               unset slots[$slot]
               break
             }
           done
           unset actfreq[$freq]
         elif [ "${actfreq[$freq]}" -ge $SLOT_ACTIVATE_TIME ]; then
           [[ "${slots[@]}" =~ "$freq" ]] || {
             # activate slot
             for ((slot=1;slot<=MAX_SLOTS;slot++)); do
               [ -z "${slots[$slot]}" ] && {
echo "Activating slot $slot with freq $freq and fifo ${fifos[$slot]}" >> /tmp/debug.out
                 slots[$slot]="$freq"
                 calc_bandpass_param "$((TUNER_FREQ-freq))" "$TUNER_SAMPLE_RATE" > "${fifos[$slot]}"
                 break
               }
             done
           }
         fi
       done
echo "----------------------------------------" >> /tmp/debug.out
       ;;
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

trap "cleanup $pid1 $pid2" EXIT INT TERM

# This is a magic line that kick-starts the decode_sonde processes
# I really don't understand why it is needed because the way I
# implemented the shift_addition_switchable_cc should make it work
# without this line but it doesn't. Some kind of weired magic
(sleep 2;eval "$(printf 'echo '1.0' > %q;' "${fifos[@]}")") &
 
rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | \
eval "tee $(printf '>(decode_sonde %q) ' "${fifos[@]}")" | \
scan_power | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr




# receivemultisonde.sh complete with old functions.
# saved here for historical reasons

#!/bin/bash
#
# Written by Alexnader K
#
# This script receives and decodes several sondes with only one rtl dongle
#
# Usage: ./receivemultisonde.sh -f 403405000 -s 2400000 -P 35 -g 40 -t 5
#        So I set the tuning frequenty in the middle of 10 kHz because I
#        know that sondes transmit with at least 10 kHz steps. 
#        Sample rate is the maximum 2400000 Hz to improve SNR
#        My rtl receiver has 35 PPM
#        I set gain to 40 but I guess that with recent addition of the automatic
#        noise floor detection the gain could be set to 0 - automatic gain
#        Signal threshold is set to 5 - a signal is considered active if its power
#        is 5dB above the noise signal
#
# Script output:
# - local UDP port 5676 the power measuremnts in json form each 5 seconds:
#   {"response_type":"log_power","samplerate":2400000,"tuner_freq":403405000,"result":"-77.9 ..."} 
#   where "result" has SCAN_BINS values.
# - local UDP port 5678 decoders output in jsong form:
#   {"type":"RS41","frame":5174,"id":"S3440233", ...}


. ./defaults.conf

SCAN_BINS=4096
SCAN_OUTPUT_STEP=10000  # in Hz
SCAN_AVERAGE_TIMES=100
SCAN_UPDATE_RATE=1
SCAN_UPDATE_RATE_DIV=5 # 5 seconds
SCAN_POWER_NOISE_LEVEL_INIT=-69 # initial noise level
SCAN_POWER_THRESHOLD=5 # signal is detected if its power more than (noise level + this value) 

SCANNER_OUT_PORT=5676
SCANNER_COM_PORT=5677
DECODER_PORT=5678

SLOT_TIMEOUT=10 # i.e 30 seconds *10 = 5 minutes
SLOT_ACTIVATE_TIME=4 # 4 * 5 seconds = 20 seconds min activity
MAX_SLOTS=5 # this value should be MAX_FQ - 1 (MAX_FQ is defined in the iq_base.h)

IQ_SERVER_PATH="../iq_svcl"
DECODERS_PATH="../decoders"

OPTIND=1 #reset index
while getopts "ha:p:f:s:g:p:P:t:" opt; do
  case $opt in
     h)  show_usage $(basename $0); exit 0; ;;
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
 
[ ! "$TUNER_FREQ" -eq 0 ] || show_error_exit "Wrong frequency"
[ ! "$TUNER_SAMPLE_RATE" -eq 0 ] || show_error_exit "Wrong sample rate"

DECIMATE=$((TUNER_SAMPLE_RATE/DEMODULATOR_OUTPUT_FREQ))
[ "$((DECIMATE*DEMODULATOR_OUTPUT_FREQ))" -ne "$TUNER_SAMPLE_RATE" ] && show_error_exit "Sample rate should be multiple of $DEMODULATOR_OUTPUT_FREQ"


cleanup()
{
  local children child
  children="$1 $2 $3 $(get_children_pids $1) $(get_children_pids $2) $(get_children_pids $3)"
  kill $children &>/dev/null;wait $children &>/dev/null
}

# Power scanning using csdr. This is my older, stable and well tested solution
# to perform power scanning 
scan_power()
{
  ./csdr convert_u8_f | \
  ./csdr fft_cc $SCAN_BINS $((TUNER_SAMPLE_RATE/(SCAN_UPDATE_RATE*SCAN_AVERAGE_TIMES/SCAN_UPDATE_RATE_DIV))) | \
  ./csdr logaveragepower_cf -70 $SCAN_BINS $SCAN_AVERAGE_TIMES | \
  ./csdr fft_exchange_sides_ff $SCAN_BINS | \
  ./csdr dump_f | tr ' ' '\n' | \
   tee >(
    awk -v bins=$SCAN_BINS '{printf("%.1f ",$0);if(0==(NR%bins)){printf("\n")};fflush()}' |
    awk -v f=$TUNER_FREQ -v bins="$SCAN_BINS" -v sr="$TUNER_SAMPLE_RATE" '
      {printf("{\"response_type\":\"log_power\",\"samplerate\":%d,\"tuner_freq\":%d,\"result\":\"%s\"}\n", sr, f, $0);
      fflush()}' |
    socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_OUT_PORT,broadcast,reuseaddr
   ) |
   awk -v f=$TUNER_FREQ -v sr=$TUNER_SAMPLE_RATE -v bins=$SCAN_BINS '
     BEGIN{fstep=sr/bins;fstart=f-sr/2;print fstep;print fstart}
     {printf("%d %.1f\n",fstart+fstep*((NR-1)%bins),$0);
      if(0==(NR%bins)){printf("\n")};fflush()}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v step=$((TUNER_SAMPLE_RATE/SCAN_BINS)) '
     function abs(x){return (x<0)?-x:x}
     BEGIN{idx=1}
     {if(length($2)!=0){a[idx++]=$2;if(abs($1-outstep*int($1/outstep)<step)){print $0}}
      else{print; asort(a); if(idx>1){print a[int(idx/2)]} idx=1;};
      fflush();}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v nl=$SCAN_POWER_NOISE_LEVEL_INIT -v thr=$SCAN_POWER_THRESHOLD '
     {if (length($2)!=0){if(int($2)>(nl+thr)){print outstep*int(int($1)/outstep)" "$2;fflush()}}
      else if(length($1)!=0) {nl=$1}}'
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
   "$IQ_SERVER_PATH"/iq_client --fftc | \
   tee >(
    awk -v bins=$SCAN_BINS '/^$/{printf("\n")};/^[^#].*/{printf("%.1f ",$2);fflush()}' |
    awk -v f=$TUNER_FREQ -v bins="$SCAN_BINS" -v sr="$TUNER_SAMPLE_RATE" '
      {printf("{\"response_type\":\"log_power\",\"samplerate\":%d,\"tuner_freq\":%d,\"result\":\"%s\"}\n", sr, f, $0);
      fflush()}' |
    socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_OUT_PORT,broadcast,reuseaddr
   ) |
   awk -v f=$TUNER_FREQ -v sr=$TUNER_SAMPLE_RATE '/^$/{print;fflush();next};/^[^#].*/{printf("%d %.1f\n", int(f+($1*sr)), $2);fflush()}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v step=$((TUNER_SAMPLE_RATE/SCAN_BINS)) '
     function abs(x){return (x<0)?-x:x}
     BEGIN{idx=1}
     {if(length($2)!=0){a[idx++]=$2;if(abs($1-outstep*int($1/outstep)<step)){print $0}}
      else{print; asort(a); if(idx>1){print a[int(idx/2)]} idx=1;};
      fflush();}' | \
   awk -v outstep="$SCAN_OUTPUT_STEP" -v nl=$SCAN_POWER_NOISE_LEVEL_INIT -v thr=$SCAN_POWER_THRESHOLD '
     {if (length($2)!=0){if(int($2)>(nl+thr)){print outstep*int(int($1)/outstep)" "$2;fflush()}}
      else if(length($1)!=0) {nl=$1}}'
}

# this funciton is not used and kept only for historical reasons
# the line below should come before the m10mod if needed.
#      tee >(c50dft -d1 --ptu --json /dev/stdin > /dev/stderr) | \
decode_sonde()
{
  local bpf3=$(calc_bandpass_param 5000 48000)
  local bpf9=$(calc_bandpass_param 9600 48000)

  (
    "$IQ_SERVER_PATH"/iq_client --freq $(calc_bandpass_param "$(($1-TUNER_FREQ))" "$TUNER_SAMPLE_RATE") |
    tee >(
      ./csdr bandpass_fir_fft_cc -$bpf9 $bpf9 0.02 |
      ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 |
      sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
      "$DECODERS_PATH"/m10mod --ptu --json > /dev/stderr
    ) |
    ./csdr bandpass_fir_fft_cc -$bpf3 $bpf3 0.02 |
    ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 |
    sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
    tee >("$DECODERS_PATH"/dfm09mod --ptu --ecc --json -vv /dev/stdin > /dev/stderr) \
        >("$DECODERS_PATH"/dfm09mod --ptu --ecc --json -i /dev/stdin > /dev/stderr) \
        >("$DECODERS_PATH"/rs41mod --ptu --ecc --crc --json -vv /dev/stdin > /dev/stderr) \
        >("$DECODERS_PATH"/rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr) | \
    aplay -r 48000 -f S8 -t wav -c 1 -B 500000 &> /dev/null
  ) &>/dev/stdout | while read LINE; do
      echo "$LINE" | grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"freq":"'"$1"'"}' | \
      (flock 200; socat -u - UDP4-DATAGRAM:127.255.255.255:$DECODER_PORT,broadcast,reuseaddr) 200>$MUTEX_LOCK_FILE
    done
}

start_decoder()
{
  local decoder bw

  case "$1" in
    RS41) decoder="$DECODERS_PATH/rs41mod --ptu --ecc --crc --json /dev/stdin > /dev/stderr";bw=10 ;;
    RS92) decoder="$DECODERS_PATH/rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr";bw=10 ;;
    DFM9) decoder="tee >($DECODERS_PATH/dfm09mod --ptu --ecc --json /dev/stdin > /dev/stderr) | ./dfm09mod --ptu --ecc --json -i /dev/stdin > /dev/stderr";bw=10 ;;
     M10) decoder="$DECODERS_PATH/m10mod --ptu --json > /dev/stderr";bw=19.2 ;;
  C34C50) decoder="tee >($DECODERS_PATH/c34dft -d1 --ptu --json /dev/stdin > /dev/stderr) | ./c50dft -d1 --ptu --json /dev/stdin > /dev/stderr";bw=19.2 ;;
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
    (type=$("$DECODERS_PATH"/dft_detect --iq - 48000 32 | awk -F':' '{print $1}'); start_decoder "$type") &>/dev/stdout |
    while read LINE; do
      echo "$LINE" | grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"freq":"'"$1"'"}' | \
      (flock 200; socat -u - UDP4-DATAGRAM:127.255.255.255:$DECODER_PORT,broadcast,reuseaddr) 200>$MUTEX_LOCK_FILE
    done
}


# this funciton is not used and kept only for historical reasons
decode_sonde_iqfm()
{
  (
    "$IQ_SERVER_PATH"/iq_client --freq $(calc_bandpass_param "$(($1-TUNER_FREQ))" "$TUNER_SAMPLE_RATE") |
    tee >(
      "$IQ_SERVER_PATH"/iq_fm --lpbw 19.2 - 48000 32 --bo 16 |
      sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
      "$DECODERS_PATH"/m10mod --ptu --json > /dev/stderr
    ) |
    "$IQ_SERVER_PATH"/iq_fm --lpbw 10.0 - 48000 32 --bo 16 |
    sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
    tee >("$DECODERS_PATH"/dfm09mod --ptu --ecc --json -vv /dev/stdin > /dev/stderr) \
        >("$DECODERS_PATH"/dfm09mod --ptu --ecc --json -i /dev/stdin > /dev/stderr) \
        >("$DECODERS_PATH"/rs41mod --ptu --ecc --crc --json -vv /dev/stdin > /dev/stderr) \
        >("$DECODERS_PATH"/rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr) | \
    aplay -r 48000 -f S8 -t wav -c 1 -B 500000 &> /dev/null
  ) &>/dev/stdout | while read LINE; do
      echo "$LINE" | grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"freq":"'"$1"'"}' | \
      (flock 200; socat -u - UDP4-DATAGRAM:127.255.255.255:$DECODER_PORT,broadcast,reuseaddr) 200>$MUTEX_LOCK_FILE
    done
}

declare -A actfreq # active frequencies
declare -A slots   # active slots

(socat -u UDP-RECVFROM:$SCANNER_COM_PORT,fork,reuseaddr - | while read LINE; do
  case "$LINE" in
    TIMER30)
       for freq in "${!actfreq[@]}"; do 
echo "timer: actfreq[$freq] is ${actfreq[$freq]}" >> /tmp/debug.out
         actfreq[$freq]=$((actfreq[$freq]-1))
         [ "${actfreq[$freq]}" -gt "$SLOT_TIMEOUT" ] && actfreq[$freq]=$SLOT_TIMEOUT
         if [ "${actfreq[$freq]}" -eq 0 ]; then
           # deactivate slot
           [ -z "${slots[$freq]}" ] || {
echo "Deactivating slot $slot with freq $freq" >> /tmp/debug.out
             cleanup "${slots[$freq]}"
             unset slots[$freq]
           }
           unset actfreq[$freq]
         elif [ "${actfreq[$freq]}" -ge $SLOT_ACTIVATE_TIME ]; then
           # activate slot
           [ -z "${slots[$freq]}" ] && [ "${#slots[@]}" -lt $MAX_SLOTS ] && {
echo "Activating slot $slot with freq $freq" >> /tmp/debug.out
             decode_sonde_with_type_detect "$freq" &
             slots[$freq]=$!
           }
         fi
       done
echo "active slots: ${!slots[@]}" >> /tmp/debug.out
echo "----------------------------------------" >> /tmp/debug.out
       ;;
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

# Due to stability issues power measurements using iq_client is deactivated
(scan_power_iq | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr) &
pid3=$!

trap "cleanup $pid1 $pid2 $pid3" EXIT INT TERM

rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - |
"$IQ_SERVER_PATH"/iq_server --fft /tmp/fft.out --bo 32 - 2400000 8

# The code below uses csdr to get power measurements
# To use this code comment 5 lines above and uncomment lines below
#trap "cleanup $pid1 $pid2" EXIT INT TERM

#rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - |
#tee >(scan_power | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr) |
#"$IQ_SERVER_PATH"/iq_server --fft /tmp/fft.out --bo 32 - 2400000 8
