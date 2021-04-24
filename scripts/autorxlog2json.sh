#!/bin/bash

# Converts auto_rx log files into original json form
# As I ditched auto_rx I wanted to keep collected sondes log files
# Usage: autorxlog2json.sh logfilename|/dev/stdin

#timestamp,serial,frame,lat,lon,alt,vel_v,vel_h,heading,temp,humidity,type,freq_mhz,snr,f_error_hz,sats,batt_v,burst_timer,aux_data
#2021-02-27T11:29:37.000Z,S1241035,2130,48.20788,11.49001,5338.5,7.4,16.3,198.4,-273.0,-1.0,RS41-SGP,402.300,-99.0,0,12,2.9,-1,-1

#{"type":"RS41","frame":3811,"id":"R3340919","datetime":"2021-02-27T11:22:48.001Z","lat":49.12767,"lon":11.51964,"alt":11251.76885,"vel_h":15.15269,"heading":196.90084,"vel_v":3.03807,"sats":11,"bt":17114,"batt":2.7,"temp":-55.7,"humidity":8.3,"pressure":220.01,"subtype":"RS41-SGP","freq":"402700000"}

awk -F',' '{printf("{\"type\":\"%s\",\"frame\":%d,\"id\":\"%s\",\"datetime\":\"%s\",\"lat\":%f,\"lon\":%f,\"alt\":%f,\"vel_h\":%f,\"heading\":%f,\"vel_v\":%f,\"sats\":%d,\"bt\":%d,\"batt\":%.1f,\"temp\":%.1f,\"humidity\":%.1f,\"subtype\":\"%s\",\"freq\":\"%s\"}\n", $12, $3, $2, $1, $4, $5, $6, $8, $9, $7, $16, $18, $17, $10, $11, $12, $13);}' $1
