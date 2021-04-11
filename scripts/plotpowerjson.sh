#!/bin/bash


while read LINE; do
  IFS=$'\n' a=( $(echo "$LINE" | jq --unbuffered -r '.samplerate, .tuner_freq, .result') )
  samplerate=${a[0]};tuner_freq=${a[1]};result=${a[2]}
  scan_bins=$(echo "$result" | awk -F',' '{print NF}')
  [[ -n "$result" ]] && [[ -n "$samplerate" ]] && [[ -n "$tuner_freq" ]] && {
    echo "$result" | 
    awk -F',' -v tf="$tuner_freq" -v sr="$samplerate" -v sb="$scan_bins" '
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
( # at first the block length is calculated because gnuplotblock cant dynamically adjust to the
  # length changes, so we wait util 2 adjacent blocks have the same length and only then continue
  # I have no idea why the block length changes, something isn't right with the awk code block above
 bl=$(awk 'BEGIN{ol=0;l=0}{if(length($1)!=0){l++;}else{if(l!=0 && ol==l){print l;exit 0}else{ol=l;l=0;}}}');
 ~/bin/gp/removecolumns.sh '1' |  ~/bin/gp/gnuplotblock.sh "-1:$((bl+1));-1:22;-85:-50" "power map 10k step;image;;map;$bl;20"
)
