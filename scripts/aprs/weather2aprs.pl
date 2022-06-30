#!/usr/bin/env perl
#

# I use this script to inject wireless temperature sensors readings into my fake
# APRS server (aprsfakeserver.pl)
# Wireless sensor reading are broadcasted on my local network in a JSON form like:
# {"time" : "2021-05-02 07:16:24", "model" : "inFactory sensor", "id" : 118, "temperature_C" : 5.778, "humidity" : 81}
# {"time" : "2021-05-02 07:16:33", "model" : "pressure sensor", "id" : 242, "pressure" : "1013.95"}
#
# Usage: weather2aprs.pl CALLSIGN QTH_LAT QTH_LON | tee /dev/stderr | socat -u - UDP4-DATAGRAM:0.0.0.0:30448,broadcast,reuseaddr

use strict;
use warnings;

use JSON;
use threads::shared;

$|=1;


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


my $json;
my $pressure;
my $temp;
my $humid;
my $homelat;
my $homelon;
my $mycallsign;


while (@ARGV) {
  $mycallsign = shift @ARGV;
  $homelat = shift @ARGV;
  $homelon = shift @ARGV;
}

while (<>) {
  # only for json strings
  if ($_ =~ /^{.*}$/) {
    $json = decode_json($_);

    my $model = $json->{"model"};
    defined $model or next;

    my $id = $json->{"id"};
    defined $id or next;

    "pressure sensor" eq $model or "inFactory-TH" eq $model or next;
    242 == $id or 158 == $id or next;

    if (242 == $id) {
      # pressure sensor
      $pressure = sprintf("%.1f", $json->{"pressure"});
      $pressure = int($pressure * 10);
    }
    else {
      $temp = int(32 + ($json->{"temperature_C"} * 9/5));
      $humid = int($json->{"humidity"});

    }
  }
  if (defined $pressure and defined $temp and defined $humid) {
    printf("%s-13>APRS,TCPIP*,%s-13:!%s/%s_000/000t%03db%dh%02d\n",
           ${mycallsign}, ${mycallsign}, lat2aprs($homelat), lon2aprs($homelon),${temp}, ${pressure}, ${humid});
    printf("%s-13>APRS,TCPIP*,%s-13:!%s/%sW\n", ${mycallsign}, ${mycallsign}, lat2aprs($homelat), lon2aprs($homelon));
  }
}

