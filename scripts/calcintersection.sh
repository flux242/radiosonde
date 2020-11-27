#/bin/bash

# See https://www.movable-type.co.uk/scripts/latlong-nomodule.html
# Usage: calculateintersection lat1 long1 angle1 lat2 long2 angle2
# Example:
#        ./calcintersection.sh 51.8853 0.2545 108.547 49.0034 2.5735 32.435 | \
#         jq -rc 'select(.lat)|[ .lat, .lon ]|"\(.[0]);\(.[1])"' => 50.9078;4.50841

awk -i ./latlon-spherical.awk -v lat1=$1 -v lon1=$2 -v brng1=$3 -v lat2=$4 -v lon2=$5 -v brng2=$6 \
 'BEGIN{latlon=calc_intersection(lat1, lon1, brng1, lat2, lon2, brng2); n=split(latlon,p,";"); print "{\"lat\":"p[1]", \"lon\":"p[2]"}";
}'

