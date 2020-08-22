#!/usr/bin/env perl
## aprs-output provided by daniestevez
## axudp extensions provided by dl9rdz

# this is a heavy facelifted script from Zilog
# Usage:
#
# nc -luk 5678 | \
# ./aprs/json2aprs.pl MYCALLSIGN MYPASS MYLAT MYLON " My comment srting" | 
# socat -u - UDP4-DATAGRAM:0.0.0.0:30448,broadcast,reuseaddr
#
# It will receive decoded radiosonde json strings broadcasted on the UDP port 5678,
# convert it into APRS format and broadcasts it on the 30448 port locally. If the
# aprsfakeserver.pl is started too it will receive messages on that port and send
# it to the client on the TCP port 14580. I use this to show sondes using YAAC
# 
# Another usage scenario
# socat -d -d exec:./aprs/aprsfakeclient.sh,pty,stderr TCP:radiosondy.info:14590
# where aprsfakeclient.sh is
# ```
# #!/bin/bash
#
# nc -luk 5678 | ./aprs/json2aprs.pl MYCALLSIGN MYPASS MYLAT MYLON " My comment srting"
# ```
# in this case json2aprs.pl will send its output to the radiosondy.info port 14590
#

use strict;
use warnings;
use IO::Socket::INET;
use Getopt::Long;

use JSON;
use Time::Piece;
use Scalar::Util qw(looks_like_number);
use POSIX qw(ceil);
use List::Util qw(min);
use List::Util qw(max);

my $filename = undef;

our $mycallsign = undef;
my $passcode = undef;
my $homelat = 0.0;
my $homelon = 0.0;
our $homeaprslat;
our $homeaprslon;
our $comment = '';
our $first_time_alarm;

my $udp;
GetOptions("u=s" => \$udp) or die "Error in command line arguments\n";

$|=1;

while (@ARGV) {
  $mycallsign = shift @ARGV;
  $passcode = shift @ARGV;
  $homelat = shift @ARGV;
  $homelon = shift @ARGV;
  $comment = shift @ARGV;
  $filename = shift @ARGV;
}

(defined $mycallsign and defined $passcode) or die "Missing script arguments\n";

our $fpi;

if (defined $filename) {
  open($fpi, "<", $filename) or die "Could not open $filename: $!";
}
else {
  $fpi = *STDIN;
}

our $fpo = *STDOUT;


my $line;


# axudp: encodecall: encode single call sign ("AB0CDE-12*") up to 6 letters/numbers, ssid 0..15, optional "*"; last: set in last call sign (dst/via)
sub encodecall{
    my $call = shift;
    my $last = shift;
    if(!($call =~ /^([A-Z0-9]{1,6})(-\d+|)(\*|)$/)) {
        die "Callsign $call not properly formatted";
    };
    my $callsign = $1 . ' 'x(6-length($1));
    my $ssid = length($2)>0 ? 0-$2 : 0;
    my $hbit = $3 eq '*' ? 0x80 : 0;
    my $encoded = join('',map chr(ord($_)<<1),split //,$callsign);
    $encoded .= chr($hbit | 0x60 | ($ssid<<1) | ($last?1:0));
    return $encoded;
}

# kissmkhead: input: list of callsigns (dest, src, repeater list); output: raw kiss frame header data
sub kissmkhead {
    my @calllist = @_;
    my $last = pop @calllist;
    my $enc = join('',map encodecall($_),@calllist);
    $enc .= encodecall($last, 1);
    return $enc;
}

#create CRC tab
my @CRCL;
my @CRCH;
my ($c, $crc,$i);
for $c (0..255) {
    $crc = 255-$c;
    for $i (0..7) {  $crc = ($crc&1) ? ($crc>>1)^0x8408 : ($crc>>1); }
    $CRCL[$c] = $crc&0xff;
    $CRCH[$c] = (255-($crc>>8))&0xff;
}
sub appendcrc {
    $_ = shift;
    my @data = split //,$_;
    my ($b, $l, $h)=(0,0,0);
    for(@data) { $b = ord($_) ^ $l; $l = $CRCL[$b] ^ $h; $h = $CRCH[$b]; }
    $_ .= chr($l) . chr($h);
    return $_;
}

# Takes a decimal and returns base91 char string.
# With optional parameter for fix with output
sub base91_from_decimal {
    my ($number,$width) = @_;
    $width //= 1;

    looks_like_number($number) and looks_like_number($width) and ($number >= 0) or die "base91 conversion error";

    my $text = '';
    if ($number > 0) {
      my $max_n = int(ceil(log($number) / log(91)));   

      for (my $n = $max_n; $n >= 0; $n += -1) {
        my $quotient = int($number / (91**$n));
        $number %= 91**$n;
        $text = $text . chr(33 + $quotient);
      }
    }
    $text =~ s/!+//;
   
    # pad the final string with !
    while (length($text) < max(1, $width)) { $text="!$text"; }

    return $text;
}

sub deg2aprsoffset
{
  my $deg = shift @_;
  my $degint = int($deg * 10000);
  return int((($deg * 10000) - $degint)*100);
}

sub lat2aprs {
  my $lat; my $hemchar;
  ($lat, $hemchar) = deg2aprs(shift @_, 'S', 'N');
  $lat = sprintf("%07.2f%s", $lat, $hemchar);
  return $lat;
}

sub lon2aprs {
  my $lon; my $hemchar;
  ($lon, $hemchar) = deg2aprs(shift @_, 'W', 'E');
  $lon = sprintf("%08.2f%s", $lon, $hemchar);
  return $lon;
}

sub deg2aprs {
  my ($deg, $negchar, $poschar) = @_;
  my $sign; my $hemchar;
  my $aprstr = '';

  if ($deg =~ /(-?\d*)(\.\d*)/) {
    if ($1 < 0) { $hemchar="$negchar"; $sign *= -1; }
    else        { $hemchar="$poschar"; $sign = 1; }
    $aprstr = $sign*$1*100+$2*60;
  }
  return ($aprstr, $hemchar);
}
sub put_station_info {
  # use E instead of ` to show an eye instead of a radar
  printf $fpo "%s-2>APNL51,TCPIP*,qAI,%s-2:!%s/%s`%s\n\n", $mycallsign, $mycallsign, $homeaprslat, $homeaprslon, $comment;
}

$SIG{ALRM} = sub {
    # set up the next signal for N  seconds from now
    alarm 300; # 5 minutes timeout
    put_station_info
    $first_time_alarm = 1;
};

my ($sock,$kissheader);
if($udp) {
    my ($udpserver,$udpport)=split ':',$udp;
    $udpserver = "127.0.0.1" unless $udpserver;
    $sock = new IO::Socket::INET(PeerAddr => $udpserver, PeerPort => $udpport, Proto => "udp", Timeout => 1) or die "Error creating socket";
    # $kissheader = kissmkhead("APRS",uc($mycallsign),"TCPIP*");
    $kissheader = kissmkhead("APRS",uc($mycallsign));
}

print $fpo "user $mycallsign pass $passcode vers \"M0ROZ decoder\" 0v1\n\n";
$homeaprslat = lat2aprs($homelat);
$homeaprslon = lon2aprs($homelon);

# alarm canno't be triggered immediately but after minimum 1 second
# so we trigger an alarm and wait util it is executed 
alarm 1;  
while(not $first_time_alarm) {
  select(undef, undef, undef, 0.25);  # sleep for 250 milliseconds
}

while ($line = <$fpi>) {

    print STDERR $line; ## entweder: alle Zeilen ausgeben

    if ($line =~ /^{.*}$/) {
        my $json = decode_json($line);
        my $datetime = $json->{"datetime"};
        
        # Datetime is this: 2020-08-21T11:04:35.001Z
        # I do not know how to define a format for it properly for the strptime
        # so I just strip it
        if ($datetime =~ /(-?[^\.]*).*/) {
          $datetime = $1;
        }

        my $time = Time::Piece->strptime($datetime, "%Y-%m-%dT%H:%M:%S");

        my $hms = $time->hour*10000+$time->min*100+$time->sec;

        my $lat; my $lon;
        my $latoffset; my $lonoffset;

        $lat = lat2aprs($json->{"lat"});
        $latoffset = deg2aprsoffset($json->{"lat"});
#        $latoffset = int(90 * (($lat*100) - int($lat*100)));
        $lon = lon2aprs($json->{"lon"});
        $lonoffset = deg2aprsoffset($json->{"lon"});
#        $lonoffset = int(90 * (($lon*100) - int($lon*100)));

        my $alt = $json->{"alt"}*3.28084; ## m -> feet

        my $date = $time->mday*10000+$time->mon*100+($time->year%100);

        my $speed = $json->{"vel_h"}*3.6/1.852;  ## m/s -> knots
        my $course = $json->{"heading"};

        my $callsign = $json->{"id"};

        my $elevation = `./getelevation.pl $json->{"lat"} $json->{"lon"}`;
        my $otg = length($elevation)!=0 ? " OG:" . int($json->{"alt"}-$elevation) ."m" : "";

        my $frame = $json->{"frame"} // '';
        my $framestr = length($frame)!=0 ? sprintf(" FN=%d", $frame):"";

        my $climb = $json->{"vel_v"};
        my $freq = $json->{"freq"};

        my $temp = $json->{"temp"} // '';
        my $tempstr = length($temp)!=0 ? sprintf(" t=%.1fC", $temp):"";

        my $humid = $json->{"humidity"} // '';
        my $humidstr = length($humid)!=0 ? sprintf(" h=%.1f%%", $humid):"";

        my $batt = $json->{"batt"};
        my $battstr = length($batt)!=0 ? sprintf(" V=%.1fV", $batt):"";

        my $type = $json->{"subtype"};
        if (length($type)==0){$type = $json->{"type"};}
        
        my $sats = $json->{"sats"} // '';
        my $satstr = length($sats)!=0 ? " Sats:". $sats : "";

        my $bkt = $json->{"bt"} // '';
        my $bktstr = length($bkt)!=0 ? $bkt < 65535 ? " BK=" . int($bkt/3600) . "h" . int($bkt/60)%60 . "m" : ' BK=Off' : "";

        my $str = sprintf("$mycallsign-15>APRS,TCPIP*:;%-9s*%06dh%s/%sO%03d/%03d/A=%06d!w%s%s!Clb=%.1fm/s%s%s %.2fMHz Type=%s%s%s%s%s%s %s",
                        $callsign, $hms, $lat, $lon, $course, $speed, $alt, base91_from_decimal($latoffset), base91_from_decimal($lonoffset), $climb, $tempstr, $humidstr, $freq/1e6, $type, $bktstr, $satstr, $battstr, $otg, $framestr, $comment);
        print $fpo "$str\n";

        if($sock) {
            $str = (split(":",$str))[1];
            print $sock appendcrc($kissheader.chr(0x03).chr(0xf0).$str);
        }

    }
    #elsif ($line =~ / # xdata = (.*)/) { ## nicht, wenn (oben) alle Zeilen ausgeben werden
    #    if ($1) {
    #        print STDERR $line;
    #    }
    #}
}

close $fpi;
close $fpo;

