#/bin/bash

# The following wget call seems to work making this script obsolete:
#
# wget --referer="https://www.navcen.uscg.gov" \
#      --user-agent="Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" \
#      -O- "https://www.navcen.uscg.gov/?pageName=currentAlmanac&format=sem-txt" 
#
# Don't know how their file naming scheme works but there's a pattern in there: 
# Digits 61440,147456,233472,319488,405504,503808,589824 have 4096
# as their common divider. 61440/4096= 15 + 21*0, and 147456/4096= 15 + 21*1 and so on.
# It's true until 503808 where 503808/4096= 3 + 15 + 21*5
#
# 2019-04-07 is the day when gps seconds counter rolled over to zero

output_file=$1
[ -n "$output_file" ] || output_file='/dev/stdout'

SECONDS_PER_DAY=$((3600*24))
SECONDS_PER_WEEK=$((SECONDS_PER_DAY*7))

# always try the next day first because the next almanach can already be available
SECONDS_OFFSET=$SECONDS_PER_DAY

while true; do
  gps_seconds_diff=$(( $(date +%s) - $(date --date='2019-04-06' +%s) ))

  gps_day=$(( ((SECONDS_OFFSET+gps_seconds_diff)/SECONDS_PER_DAY) % 7 ))
  gps_week=$(( (SECONDS_OFFSET+gps_seconds_diff)/SECONDS_PER_WEEK ))
  echo "gps week: $gps_week, gps day: $gps_day" > /dev/stderr
  sec_str=$(printf '%06d' $(( 4096 * ( 3*(gps_day>4) + 15 + gps_day*21) )))
  week_str=$(printf '%04d' $gps_week)

  sem_file_name="https://celestrak.com/GPS/almanac/SEM/$(date +%Y)/almanac.sem.week${week_str}.${sec_str}.txt"
  echo "Getting $sem_file_name into $output_file" > /dev/stderr
  wget --max-redirect 0 -O "$output_file" $sem_file_name
  if [ $? -ne 0 ]; then
    # error getting the file, trying to get an earlier version
    SECONDS_OFFSET=$((SECONDS_OFFSET-SECONDS_PER_DAY))
  else
    break
  fi
done

