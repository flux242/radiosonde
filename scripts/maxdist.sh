#!/bin/bash

show_usage_exit()
{
  echo "Calculates max and min distance to a sonde" >/dev/stderr
  echo "Usage: $0 sonde_log_file_name home_lat home_lon" >/dev/stderr
  echo "Example: for i in ~/sondes.log/*.log;do $0 \$i 55.66 11.12;done|sort -n -k5" >/dev/stderr
  exit 1
}

[ -s "$1" ] || show_usage_exit
[ -n "$2" ] || show_usage_exit
[ -n "$3" ] || show_usage_exit

jq -r --unbuffered 'select(.lat)|[ .id, .lat, .lon, .alt, .type, .freq ]|"\(.[0]),\(.[1]),\(.[2]),\(.[3]),\(.[4]),\(.[5])"' $1|
awk -i ./latlon-spherical.awk -F',' -v hlat=$2 -v hlon=$3 'BEGIN{mind=1e6;maxd=0}{id=$1;lat=$2;lon=$3;alt=$4;type=$5;freq=$6;dist=calc_distance(hlat,hlon,lat,lon);if(maxd<dist){maxd=dist;maxdalt=alt;maxdtype=type;maxdid=id;maxdfreq=freq}if(mind>dist){mind=dist;mindalt=alt}}END{printf("%s: freq: %s, max_dist: %6.2f km / %5d m, min_dist: %6.2f km / %5d m, last_point: %6.2f km / %5d m / %5.1f / %f / %f\n", id, maxdfreq, maxd/1000, maxdalt, mind/1000, mindalt, dist/1000, alt, calc_bearing(hlat, hlon, lat, lon), lat, lon)}'

