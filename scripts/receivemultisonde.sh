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

SLOT_TIMEOUT=10 # i.e 30 seconds *10 = 5 minutes
SLOT_ACTIVATE_TIME=10 # 4 * 5 seconds = 20 seconds min activity

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

scan_power()
{
  local SCAN_BINS=16384 # scan bins is atm hardcoded to be 16384

  while true; do ./iq_client --fft /dev/stdout; done | awk -F';' '{print $3}' |
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
  local bpf3=$(calc_bandpass_param 5000 48000)
  local bpf9=$(calc_bandpass_param 9600 48000)

  (
    ./iq_client --freq $(calc_bandpass_param "$(($1-TUNER_FREQ))" "$TUNER_SAMPLE_RATE") |
    tee >(
      ./csdr bandpass_fir_fft_cc -$bpf9 $bpf9 0.02 |
      ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 |
      sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
      ./m10mod --ptu --json > /dev/stderr
    ) |
    ./csdr bandpass_fir_fft_cc -$bpf3 $bpf3 0.02 |
    ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 |
    sox -t raw -esigned-integer -b 16 -r 48000 - -b 8 -c 1 -t wav - highpass 10 gain +5 |
    tee >(./dfm09mod --ptu --ecc --json -vv /dev/stdin > /dev/stderr) \
        >(./dfm09mod --ptu --ecc --json -i /dev/stdin > /dev/stderr) \
        >(./rs41mod --ptu --ecc --crc --json -vv /dev/stdin > /dev/stderr) \
        >(./rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr) | \
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
           [ -z "${slots[$freq]}" ] && {
echo "Activating slot $slot with freq $freq and fifo ${fifos[$slot]}" >> /tmp/debug.out
             decode_sonde "$freq" &
             slots[$freq]=$!
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
(sleep 2; scan_power | socat -u - UDP4-DATAGRAM:127.255.255.255:$SCANNER_COM_PORT,broadcast,reuseaddr) &
pid3=$!

trap "cleanup $pid1 $pid2 $pid3" EXIT INT TERM

rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - |
./iq_server --fft /tmp/fft.out --bo 32 - 2400000 8
