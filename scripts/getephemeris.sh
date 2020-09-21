#!/bin/bash

. ./defaults.conf

# this script requires ncompress package be installed
day=$(date +%j)
year=$(date +%y)

filename="brdc${day}0.${year}n.Z"
outfile="${1:-$EPHEM_FILE}"
[ "$outfile" = "-" ] && outfile='/dev/stdout'

wget --timeout=3 -O/tmp/$filename "ftp://cddis.gsfc.nasa.gov/gnss/data/daily/$(date +%Y)/brdc/$filename"
[ $? == 0 ] && compress -d -c /tmp/$filename > $outfile
  
