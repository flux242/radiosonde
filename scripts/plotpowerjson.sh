#!/bin/bash


while read LINE; do
  result=$(echo "$LINE" | jq --unbuffered -r 'select(.result!=null)|.result')
  samplerate=$(echo "$LINE" | jq --unbuffered -r 'select(.samplerate!=null)|.samplerate')
  tuner_freq=$(echo "$LINE" | jq --unbuffered -r 'select(.tuner_freq!=null)|.tuner_freq')
  scan_bins=$(echo "$result" | awk '{print NF}')
  [[ -n "$result" ]] && [[ -n "$samplerate" ]] && [[ -n "$tuner_freq" ]] && {
    echo "$result" | 
    awk -v tf="$tuner_freq" -v sr="$samplerate" -v sb="$scan_bins" '
      {
        fstart=tf-(sr/2); fstep=sr/sb; i=1;
        while (i<=NF) {print int(fstart+int((i-1)*fstep))" "$i;++i}
        printf("\n");fflush();
      }'
  }
done |
 tee >(~/bin/gp/gnuplotblock.sh ":;-100:-20" "Signal Power;l lw 2;red;xy") |
 awk 'function abs(x){return (x<0)?-x:x}
      {
        if(length($1)!=0) {
          if (length(step)!=0) {
            if(abs($1-10000*int($1/10000)<step)){print $0}
          }else{
            if(length(firstval)!=0){
              step=$1-firstval;
              step--;
            }
            else {firstval=$1;}
          }
        }else{print};fflush()
      }' |
 ~/bin/gp/removecolumns.sh '1' | ~/bin/gp/gnuplotblock.sh "-1:241;-1:22;-80:-45" "power map 10k step;image;;map;240;20"
# ~/bin/gp/removecolumns.sh '1' | ~/bin/gp/gnuplotblock.sh "-1:241;-1:17;-95:-65" "power map 10k step;image;;map;240;15"

