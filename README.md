﻿# Radiosonde receive station

I was never happy about existing radiosonde hunting related projects like radiosonde_auto_rx or dxlAPRS because of unneeded complexity or feature sets.
- auto_rx project is written in Python and therefore slow, resources hungry, has dependencies I don't want and can only handle one sonde at time. Although I [patched](https://github.com/projecthorus/radiosonde_auto_rx/issues/72) it and used some time ago to display sondes in my browser but it was taxing CPU on the server badly, so I ditched it.
- dxlAPRS was designed for APRS related things and then enhanced to do some radiosonde related stuff. This project has a channelizer and can track multiple sondes. Still it contains too many (or even mainly) things I don't need. Can't say anything about its complexity and dependencies because I never even tried to compile it.

As far as the sondes decoder were already written by Zilog80 I only needed a script that would scan over the baseband for sondes to demodulate and decode their signals.

First, I've written a [simple script](http://flux242.blogspot.com/2020/08/how-to-receive-and-decode-multiple.html) that would multiplex the IQ samples received from the *rtl-sdr* dongle and then would shift and filter baseband signal using [csdr](https://github.com/ha7ilm/csdr) framework. It worked to some extent but wasn't very flexible. And then Zilog80 told me about his new channelizer - *iq_server*. After [some iterations](http://flux242.blogspot.com/2020/08/how-to-receive-and-decode-multiple_10.html) and improvements the *receivemultisonde.sh* script was ready.

## receivemultisonde.sh
This script is used to receive multiple sondes at a time using only one rtl-sdr dongle by scanning baseband signal.

Main advantages over aforementioned frameworks:
- Simplicity. It's only about 170 lines of code!
- No heavy dependencies: it only depends on the *rlt-sdr* package, *iq_server* (in this repo), *decoders*(in this repo), *gawk*, *bash*, *socat*, *jq*, *sox*, *aplay*
- Easy to enhance. For example to add Russian MRZ sondes I just added a single line of code!
- Modular.

## How to use
- First the decoders and *iq_server* needs to be compiled. Change to decoders and call 'make'. Do the same in the *iq_svcl* directory.
- Change to the scripts directory in the terminal and start the script:
```
./receivemultisonde.sh -f 403405000 -s 2400000 -P 35 -g 40 -t 4
```
In this example I tune to the 403405000 Hz frequency to receive sondes between 40230000 and 404500000 Hz. In my region almost all sondes are transmitting within this range. To receive over wider range I'd need either a hardware that has wider baseband (6MHz would cover up the whole range allocated for weather radiosondes) or I'd need multiple *rtl-sdr* dongles. In the latter case 2 or 3 dongles would be needed to cover up 6MHz. For each dongle a separate instance of *receivemultisonde.sh* needs to be started with different tune frequencies. As far as this solution would require additional hardware like splitters and signal amplifiers (or multiple antennas), I never tried it. Additionally several computers would be needed because receiving 6 sondes at the same time is the maximum I can achieve on my server equipped with Intel Celeron n5000. Then the script itself needs to be enhanced a bit - there should be a MIN and MAX frequencies defined so that multiple dongles frequency ranges do not overlap.

~~After starting the script it will automatically scan the frequency range on the 10kHz borders. So, if the sampling rate is set as in the example above to 2400000, then it will scan 240 different frequencies. That’s why I tune somewhere in the middle of a 10kHz. This solution is much easier to implement as to go over all peaks in the spectrum.~~

After starting the script it will automatically scan the frequency range with 2 kHz steps (adjustable) to find signal peaks. Minimum 2 kHz is used to avoid ±1kHz jumps around the detected peak. 

If a peak is detected the *iq_server* will allocate a slot for it until that signal vanishes. The script automatically adjusts to the signal noise floor, so the slot is allocated when the peak is bigger than current noise floor level + the threshold defined by the script's '-t' parameter (its 4dB in the example above. Lower value would increadse sensivity which would lead to earlier sonde detection but it also would increase sensivity to the noise). 4-5dB is an adequate value. There's maximum number of slots defined which should correlate to the one defined for the *iq_server*. Currently it is 6 because I cannot receive more than 6 sondes at the same time anyway.

If detected signal isn't recognized as a sonde within 60 seconds then its slot will be deallocated. This can be useful if all slots are allocated but one of signals isn't a sonde. And at the same time there is another sonde signal which is actively sending but can't be received because there's no free slots for it.

If detected peak is a sonde then the script will broadcast JSON formatted strings on the local UPD port 5678. So I can check the output using: 
```
nc -luk 5678
```
Example output:
```
{"type":"RS41","frame":3044,"id":"S3541192","datetime":"2021-04-10T05:16:25.000Z","lat":48.88825,"lon":9.54869,"alt":9515.6267,"vel_h":21.0129,"heading":76.92116,"vel_v":3.66779,"sats":10,"bt":65535,"batt":2.8,"temp":-53.8,"humidity":65.6,"pressure":283.34,"subtype":"RS41-SGP","freq":"404500000"}
```

Additionally, the script outputs power scanning results every 5 seconds as JSON string on the local port 5676. Example:
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

*gnuplot* related script can be found in my [dotfiles](https://github.com/flux242/dotfiles) repository.

### Show me the sondes on a map!
I'm using YACC to show the sondes. YACC is a java app in the jar so I have no problem to start it after installing *openjdk-8-jre*. YACC UI is very badly designed and it is slow at rendering but it'll do. I have written an [article about it](http://flux242.blogspot.com/2020/08/yaac-is-not-yak.html). A good thing about it - is that I can inject additional info if I want to. As an example I'm injecting temperature info from my wireless [temperature sensors](/pics/yacc.png)

Note: Actually I finally found some time and compiled the *aprsmap* from dlxaprs project and am uing it instead of the YACC.
```
sudo apt install libpng-dev # to compile dlxaprs
sudo apt install libx11-dev # to compile dlxaprs
sudo apt install libjpeg-dev # to compile dlxaprs

gcc -Ofast -o aprsmap aprsmap.c osic.c aprsdecode.c aprsstr.c useri.c osi.c maptool.c aprstat.c pngread.c aprspos.c aprstext.c libsrtm.c pngwrite.c tcp.c xosi.c jpgdec.c udp.c Select.c pastewrapper.c beep.c -lm -lpng -ljpeg -lX11
```
The same trick with a fake APRS-IS server is used also with the aprsmap.
To compile the aprsmap I also had to do the following additionally:
- replace everywhere '#include <osic.h>' with '#include "osic.h"'
- apply the following patch:
```diff
diff --git a/src/osic.c b/src/osic.c
index c615b92..58a2b37 100644
--- a/src/osic.c
+++ b/src/osic.c
@@ -596,6 +596,7 @@ void *osic_chkptr(void *p)
 
 int32_t osic_setsystime(uint32_t * time0)
 {
-       return stime(time0);
+//     return stime(time0);
+  return clock_settime(CLOCK_REALTIME,time0);
 }
```

### Logging
I log sondes using *logsonde.sh* script
```
cd ~/projects/radiosonde/scripts/; nc -luk 5678 |./aprs/json2aprsfilter.pl 55.66 11.12 | ./logsonde.sh
```
where 55.66 and 11.12 are my QTH lat and lon (those are fake coordinates in this example)

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

so, receiving 5-6 sondes at the same time is the maximum.

## Debugging
Some debug information is broadcasted on the local UDP port DEBUG_PORT (currently 5675)
```
20210516-100345 ----------------------------------------
timer: actfreq[402692000] is 7
timer: actfreq[402694000] is -100
Deactivating slot  with freq 402694000
Type detected:  on frequency 402692000
active slots: 402692000
kill signal received with freq: 402692000
20210516-100415 ----------------------------------------
timer: actfreq[402692000] is -100
Deactivating slot  with freq 402692000
active slots:
...
```
If a slot gets constantly allocated/deallocated because of some parasitic signal on a specific frequency then that frequency can be disabled in the *defaults.conf* by adjusting FREQ_BLACK_LIST list.


## Possible improvements
- add MIN and MAX frequencies parameters to exclude aliasing on the left side and also make it ready for multi-dongle usage scenario
- configurable address to broadcast sondes JSON output. Currently it is broadcasted locally on the UDP port 5676. 
- usage scenario when two script instances are started on the same computer. Currently it won't work because they would use the same UDP ports for interprocess communication

## Can you help with testing?
Actually it would be interesting to know how well does this script perform with different hardware on different locations with different noise sources. Additionally peak detection algorythm needs to be tested for different sonde types. Currently I only tested the script for sondes that use GFSK modulation (like RS41). Sondes like SRC50 that use AFSK aren't tested yet and its 'M' like spectrum could lead to detection of two peaks. I'd need to check your debug output. Just redirect it to a file and send it to me with the description of the problem
```
nc -luk 5675 | tee some_file_name.log
```
Tell me if you can test the script in multi-dongle environment and can help with adjusting it.
