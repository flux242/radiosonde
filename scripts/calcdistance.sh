#!/bin//bash


awk -i $(dirname -- "${BASH_SOURCE[0]}")/latlon-spherical.awk -v lat1=$1 -v lon1=$2 -v lat2=$3 -v lon2=$4 -v radius=${5:-6371000} \
'BEGIN{print "{\"distance\":" calc_distance(lat1, lon1, lat2, lon2, radius) ",\"bearing\":" calc_bearing(lat1, lon1, lat2, lon2) "}";
}'

