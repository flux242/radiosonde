#!/bin/bash

. ./defaults.conf

# this script requires ncompress package be installed
day=$(date +%j)
year=$(date +%y)

#filename="brdc${day}0.${year}n.Z"
filename="auto${day}0.${year}n.Z"
outfile="${1:-$EPHEM_FILE}"
[ "$outfile" = "-" ] && outfile='/dev/stdout'
wget --timeout=5 -O/tmp/$filename "ftp://lox.ucsd.edu/rinex/$(date +%Y)/$(date +%j)/$filename"
# nasa.gov won't allow anonymous access to the RINEX broadcast ephemeris files since 31 Oct 2020
# wget --timeout=5 -O/tmp/$filename "ftp://cddis.gsfc.nasa.gov/gnss/data/daily/$(date +%Y)/brdc/$filename"
[ $? == 0 ] && compress -d -c /tmp/$filename > $outfile || cp /tmp/$filename $outfile
  
