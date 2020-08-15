#!/bin/bash


logs_dir='/opt/shared/Downloads/radiosonde_auto_rx-master/auto_rx/log'



home_lat=${1:-47.85}
home_lon=${2:-12.12}

for i in "$logs_dir"/*.log; do \
  tail -n+2 $i |
  awk -v hlat=$home_lat -vhlon=$home_lon -i ./latlon-spherical.awk -F',' ' \
  BEGIN{mind=1e6;maxd=0}
  {
   time=$1;id=$2;lat=$4;lon=$5;alt=$6;type=$12;freq=$13;
   dist=calc_distance(hlat,hlon,lat,lon);
   if(maxd<dist){maxd=dist;maxdalt=alt;maxdtype=type;maxdid=id;maxdfreq=freq}
   if(mind>dist){mind=dist;mindalt=alt}
  }
  END{printf("%s: freq: %s, max_dist: %6.2f km / %5d m, min_dist: %6.2f km / %5d m, last_point: %6.2f km / %5d m / %5.1f / %f / %f / %s\n", id, maxdfreq, maxd/1000, maxdalt, mind/1000, mindalt, dist/1000, alt, calc_bearing(hlat, hlon, lat, lon), lat, lon, time)}';
done


