#!/usr/bin/env perl
#

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

    "pressure sensor" eq $model or "inFactory sensor" eq $model or next;
    242 == $id or 129 == $id or next; 

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
    printf("%s-13>APNL51,TCPIP*,qAI,%s-13:!%s/%s_000/000t%03db%dh%02d\n",
           ${mycallsign}, ${mycallsign}, lat2aprs($homelat), lon2aprs($homelon),${temp}, ${pressure}, ${humid});
    printf("%s-13>APNL51,TCPIP*,qAI,%s-13:!%s/%sW\n", ${mycallsign}, ${mycallsign}, lat2aprs($homelat), lon2aprs($homelon));
  }
}

