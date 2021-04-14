# Radiosonde receive station

I was never happy about existing radiosonde hunting related projects like radiosonde_auto_rx or dxlAPRS because of unneeded complexity or feature sets.
- auto_rx project is written in Python and therefore slow, resources hungry, has dependencies I don't want and can only handle one sonde at time. Although I [patched](https://github.com/projecthorus/radiosonde_auto_rx/issues/72) it and used some time ago to display sondes in my browser but it was taxing CPU on the server badly, so I ditched it.
- dxlAPRS was designed for APRS related things and then enhanced to do some radiosonde related stuff. This project has a slicer and can track multiple sondes. Still it contains too many (or even mainly) things I don't need. Can't say anything about its complexity and dependencies because I never even tried to compile it.

As far as the sondes decoder were already written by Zilog80 I only needed a script that would scan over the baseband for sondes to demodulate and decode their signals.

First, I've written a simple script that would multiplex the IQ samples received from the rtl-sdr dongle and then would shift and filter baseband signal using csdr framework. It worked to some extent but wasn't very flexible. And then Zilog80 told me about his new slicer - *iq_server*. After some iterations and improvements the *receivemultisonde.sh* script was ready.

## receivemultisonde.sh
This script is used to receive multiple sondes at a time by scanning baseband signal. Only one 

Main advantages over aforementioned frameworks:
- Simplicity. It's only about 170 lines of code!
- No heavy dependencies: it only depends on the rlt-sdr package, *iq_server* (in my repo), decoders(in my repo), gawk, bash
- Easy to enhance. For example to add Russian MRZ sondes I just added a single line of code!
- Modular.

## How to use
- First the decoders and *iq_server* needs to be compiled. Change to decoders and call 'make'. Do the same in the *iq_svcl* directory.
- Change to the scripts directory in the terminal and start the script:
```
./receivemultisonde.sh -f 403405000 -s 2400000 -P 35 -g 40 -t 5
```
In this example I tune the 403405000 Hz frequency to receive sondes between 40230000 and 404500000 Hz. In my region almost all sondes are transmiting within this range. To receive over wider range I'd need either a hardware that has wider baseband (6MHz would cover up the whole range available for weather radiosondes) or I'd need multiple rtl-sdr sondes. In the latter case 2 or 3 dongles would be needed to cover up 6MHz. For each dongle a separate instance of receivemultisonde.sh needs to be started with different tune frequencies. As far as this solution would require additional hardware like splitters and signal amplifiers (or multiple antennas), I never tried it. Additionally several computers would be needed because receiving 5 sondes at the same time is the maximum I can achieve on my server equipped with Intel Celeron n5000. Then the script itself needs to be enhanced a bit - there should be a MIN and MAX frequencies defined so that multiple dongles do not overlap.

After starting the script it will automatically scan the frequency range on the 10kHz borders. So, if the sampling rate is set as in the example above to 2400000, then it will scan 240 different frequencies. That’s why I tune somewhere in the middle of a 10kHz. This solution is much easier to implement as to go over all peaks in the spectrum.

If a peak is detected on a 10kHz border a slot on the *iq_server* will be allocated until a signal vanishes. The script automatically adjusts to the signal noise floor, so the slot is allocated when the peak is bigger than current noise floor level + the threshold defined by the script's '-t' parameter (its 5dB in the example above). There's maximum number of slots defined which should correlate to the one defined for the *iq_server*. Currently it is 5 because I cannot receive more than 5 sondes at the same time anyway.

If detected peak is a sonde then the script will broadcast JSON formatted strings on the local UPD port 5678. So I can check the output using: 
```
nc -luk 5678
```
Example output:
```
{"type":"RS41","frame":3044,"id":"S3541192","datetime":"2021-04-10T05:16:25.000Z","lat":48.88825,"lon":9.54869,"alt":9515.6267,"vel_h":21.0129,"heading":76.92116,"vel_v":3.66779,"sats":10,"bt":65535,"batt":2.8,"temp":-53.8,"humidity":65.6,"pressure":283.34,"subtype":"RS41-SGP","freq":"404500000"}
```

Additionally, the script outputs power scanning results every 5 seconds as json string on the local port 5676. Example:
```
{"response_type":"log_power","samplerate":2400000,"tuner_freq":403405000,"result":"-83.45,...,-83.28"}
```
"result" contains 4096 comma separated values.

## OK, I have the strings, now what?
And here it is up to the user what to do with that but I can show what I do.

### Show me power scanning results!
To show the scanning results I use *gnuplot* and some scripts I've written some time ago to get live graphs with the *gnuplot*:
```
cd ~/projects/radiosonde/scripts/; nc -luk 5676 | ./plotpowerjson.sh
```
![Power scanning](/pics/powerscanning.png)
In this picture 3 sondes are visible.

*gnuplot* related script can be found in my dotfiles repository.

### Show me the sondes on a map!
I'm using YACC to show the sondes. YACC is a java app in a jar so I have no problem to start it after installing openjdk-8-jre. YACC UI is very badly designed and it is slow at rendering but it'll do. I have written an [article about it](http://flux242.blogspot.com/2020/08/yaac-is-not-yak.html). A good thing about it - is that I can inject additional info if I want to. As an example I'm injecting temperature info from my wireless [temperature sensors](/pics/yacc.png) 

### Logging
I log sondes using *logsonde.sh* script
```
cd ~/projects/radiosonde/scripts/; nc -luk 5678 |./aprs/json2aprsfilter.pl 55.66 11.12 | ./logsonde.sh
```
where 55.66 and 11.12 are my QTH lat and lon (those are fake coords in this example)

### Submit decoded sondes to an APRS server
As an example I'll commit to the radiosondy.info
```
cd ~/projects/radiosonde/scripts/;
socat -d -d exec:./aprs/aprsfakeclient.sh,pty,stderr TCP:radiosondy.info:14590
```
where *aprsfakeclient.sh* is
```
#!/bin/bash

nc -luk 5678 | ./aprs/json2aprsfilter.pl 55.66 11.12 | \
./aprs/json2aprs.pl N0BODY 55.66 11.12 "receivemultisonde.sh"
```

decoded JSON strings needs to be filtered first before sending to the sever!

## CPU usage
Picture below shows receiving 3 and then 4 sondes at the same time with my Celeron n5000 server
![CPU usage](/pics/cpuusage.png)

so, receiving 5 sondes at the same time is the maximum.
