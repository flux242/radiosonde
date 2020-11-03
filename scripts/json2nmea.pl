#!/usr/bin/env perl

# Reworked Zilog's pos2nmea script that parses json instead
#
# Depends: libjson-perl
#
# Usage:
#   later
#
# Legacy:
#  The following code could be used to convers json decoder output to a string
#  that Zilog's pos2nmea.pl script understands:
#
#  grep --line-buffered datetime|sed -nur 's/(.*datetime":)([^\.]+)....(.*)/\1\2\3/p' - |
#  jq --unbuffered -rc 'select(.lat)|[.datetime, .lat, .lon, .alt, .vel_h, .heading, .id, .frame, .temp]|"[\(.[7])] (\(.[6])) (2.7V) \(.[0]|strptime("%Y-%m-%dT%H:%M:%SZ")|strftime("%Y-%m-%d %H:%M:%S.000"))  lat: \(.[1])  lon: \(.[2])  alt: \(.[3])  vH: \(.[4])  D: \(.[5]) \(if isempty(.[8]//empty) then "" else " T=\(.[8])C" end)"'
#
#  sed strips all symbols behind seconds in the data-time field
#


use strict;
use warnings;
#use Getopt::Long;

use JSON;
use Time::Piece;

my $filename = undef;


$|=1;

while (@ARGV) {
  $filename = shift @ARGV;
}

our $fpi;

if (defined $filename) {
  open($fpi, "<", $filename) or die "Could not open $filename: $!";
}
else {
  $fpi = *STDIN;
}

my $geoid = 0.0;

our $fpo = *STDOUT;
my $line;

while ($line = <$fpi>) {

    print STDERR $line; ## entweder: alle Zeilen ausgeben

    if ($line =~ /^{.*}$/) {
        my $json = decode_json($line);
        my $datetime = $json->{"datetime"};
        
        # Datetime is this: 2020-08-21T11:04:35.001Z
        # I do not know how to define a format for it properly for the strptime to work
        # so I just strip all symbols behind seconds
        if ($datetime =~ /(-?[^\.]*).*/) {
          $datetime = $1;
        }

        # sometimes DFM decoder returns an invalid unparsable date-time
        # which makes the script stop. Here is an exception handling
        my $time;
        eval {
          $time = Time::Piece->strptime($datetime, "%Y-%m-%dT%H:%M:%S");
          1;
        }
        or do {
          my $error = $@ || 'Unknown error by date parsing';
          print STDERR $error;
          next; # can't continue as the time object wasn't created
        };

        my $hms = $time->hour*10000+$time->min*100+$time->sec;
        my $date = $time->mday*10000+$time->mon*100+($time->year%100);

        my $lat = $json->{"lat"};
        my $lon = $json->{"lon"};

        my $sign; my $NS; my $EW;

        if ($lat < 0) { $NS="S"; $sign = -1; }
        else          { $NS="N"; $sign = 1}
        $lat = $sign*int($lat)*100+($lat-int($lat))*60;

        if ($lon < 0) { $EW="W"; $sign = -1; }
        else          { $EW="E"; $sign = 1; }
        $lon = $sign*int($lon)*100+($lon-int($lon))*60;

        my $alt = $json->{"alt"}; ## m

        my $speed = $json->{"vel_h"}*3.6/1.852;  ## m/s -> knots
        my $course = $json->{"heading"};

        my $str = sprintf("GPRMC,%010.3f,A,%08.3f,$NS,%09.3f,$EW,%.2f,%.2f,%06d,,", $hms, $lat, $lon, $speed, $course, $date);
        my $cs = 0;
        $cs ^= $_ for unpack 'C*', $str;
        printf $fpo "\$$str*%02X\n", $cs;

        $str = sprintf("GPGGA,%010.3f,%08.3f,$NS,%09.3f,$EW,1,04,0.0,%.3f,M,%.1f,M,,", $hms, $lat, $lon, $alt-$geoid, $geoid);
        $cs = 0;
        $cs ^= $_ for unpack 'C*', $str;
        printf $fpo "\$$str*%02X\n", $cs;
    }
}

close $fpi;
close $fpo;

