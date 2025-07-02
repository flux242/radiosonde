#!/bin/bash

LOG_DIR=~/sondes.log
TIMEOUT=600 # seconds

log_info()
{
  echo "$(date +%Y-%m-%d\ %H:%M:%S) - $1"
}

[ -d "$LOG_DIR" ] || mkdir "$LOG_DIR"

#20201006-050351_R3320158_RS41_402700_sonde.log
#$(date +%Y%m%d-%H%M%S)
# date +%Y-%m-%dT%H:%M:%S.%3N%Z --date="2021-06-12T00:40:29.000Z" 2>/dev/null
#echo '{"type":"RS41","frame":9144,"id":"S3440298","datetime":"2021-02-27T06:52:04.001Z","lat":48.32432,"lon":9.62179,"alt":9996.93769,"vel_h":19.53257,"heading":216.75179,"vel_v":-6.84676,"sats":9,"bt":29126,"batt":2.6,"temp":-50.1,"humidity":7.2,"subtype":"RS41-SGP","freq":"404500000"}'
#  id=$(echo "$LINE" | jq -rc 'select(.lat)|[ .lat, .lon ]|"\(.[0]);\(.[1])"'

declare -A active_logs
declare -A active_sondes

while read LINE; do
  grep -qE '^\{.*\}$' <(echo "$LINE") || continue # skip not a json string
  id=$(echo "$LINE" | jq -rc '.id|select(.!=null)')
  [ -n "$id" ] || continue # id is not found in json string
  # TODO:  add local filter for DXXXXXXXXX ids
  [ "$id" = 'SC50xxxx' ] && continue
  [ "$id" = 'Dxxxxxxxx' ] && continue
  [ -n "${active_logs[$id]}" ] || {
    log_file=$(find "$LOG_DIR" -iname '*'"$id"'*' -printf "%f\n")
    if [ -n "$log_file" ]; then
      active_logs[$id]="$log_file"
      log_info "Using existing log file ${active_logs[$id]}"
    else
      sonde_type=$(echo "$LINE" | jq -rc '.subtype|select(.!=null)')
      [ -n "$sonde_type" ] || sonde_type=$(echo "$LINE" | jq -rc '.type|select(.!=null)')
      sonde_aux=$(echo "$LINE" | jq -rc '.aux|select(.!=null)')
      [ -n "$sonde_aux" ] && sonde_type="$sonde_type-Ozone"
      sonde_freq=$(echo "$LINE" | jq -rc '.freq|select(.!=null)')
      sonde_date=$(echo "$LINE" | jq -rc '.datetime|select(.!=null)')
      file_date=$(date +%Y%m%d-%H%M%S --date="$sonde_date" 2>/dev/null)
      [ -n "$file_date" ] || file_date=$(date +%Y%m%d-%H%M%S)
      active_logs[$id]="${file_date}_${id}_${sonde_type}_${sonde_freq}_sonde.log"
      log_info "Opening new log file ${active_logs[$id]}"
    fi
  }

  echo "$LINE" >> "${LOG_DIR}/${active_logs[$id]}"

  cur_time="$(date +%s)"
  active_sondes[$id]="$cur_time"

  for key in "${!active_sondes[@]}"; do
    (( "$cur_time" > ("${active_sondes[$key]}"+"$TIMEOUT") )) && {
      # sonde is inactive for more that 10 minutes 
      log_info "Closing log for $key"
      unset active_sondes[$key]
      unset active_logs[$key]
    }
  done
done

