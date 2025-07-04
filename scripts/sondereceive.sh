#!/bin/bash

. ./defaults.conf

DECODERS_PATH="../decoders"

show_usage()
{
cat <<HEREDOC
Usage: $1 [options]

Options:
  -h,             show this help message and exit
  -f FREQUENCY,   Frequency in Hz to tune to
  -s SAMPLE RATE, Sampling rate
  -g GAIN,        Gain to use (default: 0 for auto)
  -q SQUELCH,     Squelch value (not used currently)
  -p PPM,         PPM error (default: 0)
  -d ID,          Dongle ID
  -w,             input is a wav/raw 48kHz, 16bit, 1 channel stream
  -z,             Sonde type if known already. This will skip detection step
HEREDOC
}

show_error_exit()
{
  echo "$1" >&2
  echo "For help: $0 -h"
  exit 2
}


OPTIND=1 #reset index
while getopts "hwf:g:p:d:s:z:" opt; do
  case $opt in
     h)  show_usage $(basename $0); exit 0; ;;
     f)  TUNER_FREQ="$OPTARG" ;;
     g)  TUNER_GAIN="$OPTARG" ;;
     p)  DONGLE_PPM="$OPTARG" ;;
     d)  DONGLE_ID="$OPTARG" ;;
     s)  TUNER_SAMPLE_RATE="$OPTARG" ;;
     z)  SONDE_TYPE="$OPTARG" ;;
     w)  WAV_INPUT=1 ;;
     \?) exit 1 ;;
     :)  echo "Option -$OPTARG requires an argument" >&2;exit 1 ;;
  esac
done
shift $((OPTIND-1)) 

if [ -z "$WAV_INPUT" ]; then
  [ ! "$TUNER_FREQ" -eq 0 ] || show_error_exit "Wrong frequency: $TUNER_FREQ"
  DECIMATE=$((TUNER_SAMPLE_RATE/DEMODULATOR_OUTPUT_FREQ))
  [ "$((DECIMATE*DEMODULATOR_OUTPUT_FREQ))" -ne "$TUNER_SAMPLE_RATE" ] && show_error_exit "Sample rate should be multiple of $DEMODULATOR_OUTPUT_FREQ"
fi

[ -n "$EPHEM_FILE" ] || EPHEM_FILE='ephemeridis.txt'

# after convert
#    ./csdr fastdcblock_cc | \
log_power()
{
  ( \
    ./csdr convert_u8_f | \
    ./csdr fft_cc $SCAN_BINS $((TUNER_SAMPLE_RATE/(SCAN_UPDATE_RATE*SCAN_AVERAGE_TIMES))) |
    ./csdr logaveragepower_cf -70 $SCAN_BINS $SCAN_AVERAGE_TIMES |
    ./csdr fft_exchange_sides_ff $SCAN_BINS  |
    ./csdr dump_f | tr ' ' '\n' |
    awk -v bins=$SCAN_BINS '{printf("%.1f",$0);if(0==(NR%bins)){printf("\n")}else{printf(",")};fflush()}' |
    awk -v f=$TUNER_FREQ -v bins="$SCAN_BINS" -v sr="$TUNER_SAMPLE_RATE" '
      {printf("{\"response_type\":\"log_power\",\"samplerate\":%d,\"tuner_freq\":%d,\"result\":\"%s\"}\n", sr, f, $0);
      fflush()}'
  ) &> /dev/stdout | grep --line-buffered -E '^{' | \
    while read LINE; do 
      (flock 200; echo "$LINE") 200>$MUTEX_LOCK_FILE
    done
}


detect_sonde_type() {
  [ -n "$SONDE_TYPE" ] && {
    printf "$SONDE_TYPE: 0.99"
    return
  }
  # sonde type detection is done with the maximum signal bandwidth 9600 Hz if not specified
  local bpf=$(calc_bandpass_param 9600 $DEMODULATOR_OUTPUT_FREQ)

  [ -n "$1" ] && bpf="$1"

  ./csdr convert_u8_f | \
  ./csdr fir_decimate_cc $DECIMATE 0.005 HAMMING | \
  ./csdr bandpass_fir_fft_cc -$bpf $bpf 0.02 | \
  ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 | \
  sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 8 -c 1 -t wav - highpass 10 gain +5 | \
  tee >(aplay -r $DEMODULATOR_OUTPUT_FREQ -f S8 -t wav -c 1 -B 500000 &> /dev/null) | \
  $DECODERS_PATH/dft_detect /dev/stdin | awk -F':' '{printf("%s %d", $1,100*$2)}'
}

decode_sonde()
{
  local decoder bw

  local bpf3=$(calc_bandpass_param 3000 $DEMODULATOR_OUTPUT_FREQ)
  local bpf9=$(calc_bandpass_param 9600 $DEMODULATOR_OUTPUT_FREQ)

  local type=$(detect_sonde_type $bpf9)

  case "${type%: *}" in
    RS41) decoder="$DECODERS_PATH/rs41mod --ptu --ecc --crc --json";bw=10 ;;
    RS92) decoder="$DECODERS_PATH/rs92mod --ptu --crc --ecc --json";bw=10 ;;
    DFM9) decoder="$DECODERS_PATH/dfm09mod --ptu --ecc --json";[ -n "${type#* }" -a "${type#* }" -lt 0 ] && decoder="$decoder -i";bw=10 ;;
     M10) decoder="$DECODERS_PATH/m10mod --ptu --json";bw=19.2 ;;
  C34C50) decoder="$DECODERS_PATH/c50dft -d1 --ptu --json";bw=19.2 ;;
     MRZ) decoder="$DECODERS_PATH/mp3h1mod --ptu --ecc --json";bw=12 ;;
       *) ;;
  esac

  [ -n "$decoder" ] || {
    printf "Decoder: $decoder is unknown\n" >/dev/stderr; return
  }
  [ "${type% *}" = "RS92" ] && {
    # check if ephemeridis file exist and not older than EPHEM_MAX_AGE_SEC
    [ -s "$EPHEM_FILE" ] && [ "$(($(date +%s)-$(date -r $EPHEM_FILE +%s)))" -gt "$EPHEM_MAX_AGE_SEC" ] && \rm $EPHEM_FILE
    [ -s "$EPHEM_FILE" ] || ./getephemeris.sh
    [ -s "$EPHEM_FILE" ] || {
      [ -s "$ALMANAC_FILE" ] && [ "$(($(date +%s)-$(date -r $ALMANAC_FILE +%s)))" -gt "$ALMANAC_MAX_AGE_SEC" ] && \rm $ALMANAC_FILE
      [ -s "$ALMANAC_FILE" ] || ./getsemalmanac.sh "$ALMANAC_FILE"
    }
    if [ -s "$EPHEM_FILE" ]; then
      decoder="$decoder -e $EPHEM_FILE"
    else
      if [ -s "$ALMANAC_FILE" ]; then
        decoder="$decoder -a $ALMANAC_FILE"
      else
        decoder="(cat /dev/stdin >/dev/null)"
      fi
    fi
  }

  ( \
    ./csdr convert_u8_f | \
    ./csdr fir_decimate_cc $DECIMATE 0.005 HAMMING | \
    ./csdr bandpass_fir_fft_cc -$bw $bw 0.02 | \
    ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16 | \
    decode_sonde_wav "$decoder" 
  ) &>/dev/stdout | grep --line-buffered -E '^{' | jq --unbuffered -rcM '. + {"response_type":"sonde"}' | \
    while read LINE; do
      (flock 200; echo "$LINE") 200>$MUTEX_LOCK_FILE
    done
}

decode_sonde_wav()
{
    local decoder="$1"

    sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 8 -c 1 -t wav - highpass 10 gain +5 | \
    tee >(
      if [ -z "$decoder" ]; then
        # start all decoders if no decoder is specified
        # TODO: define decoders as string constants and use them here and also in decode_sonde
        tee >($DECODERS_PATH/m10mod --ptu --json > /dev/stderr) |
        tee >($DECODERS_PATH/c50dft -d1 --ptu --json > /dev/stderr) |
        tee >($DECODERS_PATH/dfm09mod --ptu --ecc --json /dev/stdin > /dev/stderr) |
        tee >($DECODERS_PATH/dfm09mod --ptu --ecc --json -i > /dev/stderr) |
        tee >($DECODERS_PATH/rs92mod --ptu --crc --ecc --json > /dev/stderr)  |
        $DECODERS_PATH/rs41mod --ptu --ecc --crc --json > /dev/stderr
      else
        eval "$decoder > /dev/stderr"
      fi
    ) | \
    aplay -r $DEMODULATOR_OUTPUT_FREQ -f S8 -t wav -c 1 -B 500000 &> /dev/null
} 

# TODO: add a switch to use rtlclient2.sh instead of the rtl_sdr
if [ -z "$WAV_INPUT" ]; then
  rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - 2>/dev/null | tee >(log_power >/dev/stderr) | decode_sonde
else
  # if wav input is specified then we need to overwrite the default value of the DEMODULATOR_OUTPUT_FREQ
  DEMODULATOR_OUTPUT_FREQ=48000 decode_sonde_wav
fi

#######################################################################################################
# Some old stuff

#./rtlclient2.sh -P $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | tee >(log_power >/dev/stderr) | decode_sonde
#./rtlclient2.sh -P $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | pv | decode_sonde_test >/dev/stderr

#    sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 8 -c 1 -t wav - highpass 10 gain +5 | \

# old 16bit samples
#    aplay -r 48000 -f S16_LE -t raw -c 1 -B 500000 &> /dev/null

# rs92 decoder with ephemeridis file
#    tee >(./rs92mod -e "$EPHEM_FILE" --crc --ecc --json /dev/stdin > /dev/stderr) | \

# rs92 decoder with almanac file
#    tee >(./rs92mod -a "almanac.sem.txt" --crc --ecc --json /dev/stdin > /dev/stderr) | \

# bandpass filter without control fifo filee
#    ./csdr bandpass_fir_fft_cc -$BANDPASS_PARAM $BANDPASS_PARAM 0.02 | \

# old sox conversion is replaced above by potentially more sensetive variant. Should be tested
#    sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 16 -c 1 -t wav - lowpass $SONDE_SIGNAL_BANDWIDTH highpass 10 gain +14 | \
#    sox -t raw -esigned-integer -b 16 -r $DEMODULATOR_OUTPUT_FREQ - -b 16 -c 1 -t wav - lowpass $SONDE_SIGNAL_BANDWIDTH highpass 10 gain +14 | \


#echo "rtl_fm -f $TUNER_FREQ -p $DONGLE_PPM -g $TUNER_GAIN -s $DEMODULATOR_OUTPUT_FREQ -M fm" >/dev/stderr
#rtl_fm -f $TUNER_FREQ -p $DONGLE_PPM -s $DEMODULATOR_OUTPUT_FREQ -M fm | decode_sonde_fm


#(./rtlclient2.sh -P $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | tee >(log_power >/dev/stdout) | decode_sonde) 2> /dev/null
#(./rtlclient2.sh -P $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | tee >(log_power >/dev/stderr) | decode_sonde) #> /dev/null
#(./rtlclient2.sh -P $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | tee >(log_power >/dev/stderr) | decode_sonde) #> /dev/null
#(./rtlclient2.sh -P $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | decode_sonde) #> /dev/null
#rtl_sdr -p $DONGLE_PPM -f $TUNER_FREQ -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - | decode_sonde #> /dev/null

