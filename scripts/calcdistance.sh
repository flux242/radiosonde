#!/bin//bash


awk -i ./latlon-spherical.awk -v lat1=$1 -v lon1=$2 -v lat2=$3 -v lon2=$4 -v radius=${5:-6371000} \
'BEGIN{print calc_distance(lat1, lon1, lat2, lon2, radius); print calc_bearing(lat1, lon1, lat2, lon2)}'

