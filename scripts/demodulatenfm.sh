#!/bin/bash
#
# Written by Alexnader K
#

. ./defaults.conf

OPTIND=1 #reset index
while getopts "ha:p:f:s:g:p:P:b:" opt; do
  case $opt in
     h)  show_usage $(basename $0); exit 0; ;;
     a)  address="$OPTARG" ;;  # not used atm
     p)  port="$OPTARG" ;;     # not used atm
     f)  TUNER_FREQ="$OPTARG" ;;
     s)  TUNER_SAMPLE_RATE="$OPTARG" ;;
     g)  TUNER_GAIN="$OPTARG" ;;
     P)  DONGLE_PPM="$OPTARG" ;;
     b)  FILTER_BANDWIDTH="$OPTARG" ;;
     \?) exit 1 ;;
     :)  echo "Option -$OPTARG requires an argument" >&2;exit 1 ;;
  esac
done
shift "$((OPTIND-1))"
 
[ ! "$TUNER_FREQ" -eq 0 ] || show_error_exit "Wrong frequency"
[ ! "$TUNER_SAMPLE_RATE" -eq 0 ] || show_error_exit "Wrong sample rate"

DECIMATE=$((TUNER_SAMPLE_RATE/DEMODULATOR_OUTPUT_FREQ))
[ "$((DECIMATE*DEMODULATOR_OUTPUT_FREQ))" -ne "$TUNER_SAMPLE_RATE" ] && show_error_exit "Sample rate should be multiple of $DEMODULATOR_OUTPUT_FREQ"


demodulate_nfm()
{
    ./csdr convert_u8_f |
    ./csdr shift_addition_cc "$1" |
    ./csdr fir_decimate_cc $DECIMATE 0.005 HAMMING |
    ./csdr bandpass_fir_fft_cc -$2 $2 0.02 |
    ./csdr fmdemod_quadri_cf | ./csdr limit_ff | ./csdr convert_f_s16
}

TUNER_FREQ_SHIFT=200000 # 200 kHz frequnecy shift from desired frequency

fbw=$(calc_bandpass_param $FILTER_BANDWIDTH $DEMODULATOR_OUTPUT_FREQ)
tsf=$(calc_bandpass_param $TUNER_FREQ_SHIFT $TUNER_SAMPLE_RATE)

rtl_sdr -p $DONGLE_PPM -f $((TUNER_FREQ+TUNER_FREQ_SHIFT)) -g $TUNER_GAIN -s $TUNER_SAMPLE_RATE - |
demodulate_nfm "$tsf" "$fbw" |
sox -t raw -esigned-integer -b 16 -r 48000 - -b 16 -c 1 -t wav - highpass 10 gain +5

