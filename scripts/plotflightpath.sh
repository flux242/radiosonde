#!/bin/bash

[ -e "$1" ] || {
  echo "auto-rx log file $1 does not exist" > /dev/stderr
  exit 1
}

# gnuplot does automatic scaling of axis without taking aspect ratio into account
# so here goes a complex calculation of x and y ranges to have x/y aspect ratio be 1
range=$(cat "$1" | tail -n+2 |awk -i ./latlon-spherical.awk -F',' ' \
function abs(val){if(val<0.0){return -val}else{return val}}
{
  if(1==NR){lat0=$4;lon0=$5;split(lla2enu($4, $5, $6, lat0, lon0, 0.0),pmin," ");pmax[1]=pmin[1];pmax[2]=pmin[2]};
  split(lla2enu($4, $5, $6, lat0, lon0, 0.0),pcur," ");
  if(pcur[1]<pmin[1]){pmin[1]=pcur[1]};if(pcur[2]<pmin[2]){pmin[2]=pcur[2]};
  if(pcur[1]>pmax[1]){pmax[1]=pcur[1]};if(pcur[2]>pmax[2]){pmax[2]=pcur[2]};
}
END{
  xd=abs(pmin[1]-pmax[1]);yd=abs(pmin[2]-pmax[2]);
  if (xd > yd) {
    print pmin[1]":"pmax[1]";"pmin[2]-(xd-yd)/2":"pmax[2]+(xd-yd)/2;
  }
  else {
    print pmin[1]-(yd-xd)/2":"pmin[1]+(yd-xd)/2";"pmin[2]":"pmax[2];
  }
}')

cat "$1" | tail -n+2 |
awk -i ./latlon-spherical.awk -F',' '{if(0==length(flag)){flag=1;lat0=$4;lon0=$5};print lla2enu($4, $5, $6, lat0, lon0, 0.0)}' |
awk '{print}END{print "";fflush();system("sleep 1000000")}' |
~/bin/gp/gnuplotblock.sh "$range" 'Flight Path;impulses lw 1 palette;;xyz'
#~/bin/gp/gnuplotblock.sh '0:20000;-5000:15000' 'Flight Path;impulses lw 1 palette;;xyz'
