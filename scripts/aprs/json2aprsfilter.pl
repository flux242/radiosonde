#!/usr/bin/env perl
#

use strict;
use warnings;

use JSON;
use threads::shared;

$|=1;

my $homelat; my $homelon;

while (@ARGV) {
  $homelat = shift @ARGV;
  $homelon = shift @ARGV;
}

defined $homelat or $homelat = 0.0;
defined $homelon or $homelon = 0.0;

$homelat != 0.0 or die "Home latitude should not be 0.0";
$homelon != 0.0 or die "Home longitude should not be 0.0";

my $max_distance_m    = 1000000; # 1000 km
my $max_altitude_m    = 50000;   # 50 km
my $min_altitude_m    = -50;     # -50 m
my $min_sats          = 4;       # minimum number of sats

# if a sonde is above $decimation_alt altitude then
# don't commit to the server too often to not overload it
my $decimation_period = 15;      # commit to the server each N seconds
my $decimation_alt    = 3000;    # decimation activation altitude in m

our %messages_dict;

$SIG{ALRM} = sub {
    # reschedule the next signal for N seconds from now
    alarm $decimation_period;
    lock (%messages_dict);
    my $id;
    foreach $id (keys %messages_dict) {
      print $messages_dict{$id};
      delete $messages_dict{$id};
    }
};

# schedule decimation filter
alarm $decimation_period;

sub filter_sonde_by_id {
  my ($id) = @_;

  defined $id or return 0;

  # filter DFM wrong ids out
   not $id =~ /Dxxxxxxxx/ or return 0;
   not $id =~ /DFM-xxxxxxxx/ or return 0;

   # filter C50 wrong ids out
   not $id =~ /C50-xxxx/ or return 0;

#  re.match(r'DFM-\d{6}', _serial)

  return 1;
}

my $json;

while (<>) {
  # only for json strings
  if ($_ =~ /^{.*}$/) {
    $json = decode_json($_);
    my $datetime = $json->{"datetime"};

    my $lat = $json->{"lat"};
    my $lon = $json->{"lon"};

    my $responsejson = `./calcdistance.sh $homelat $homelon $json->{"lat"} $json->{"lon"}`;
    my $distancejson = decode_json($responsejson);
    my $distance = $distancejson->{"distance"};
    if ($distance > $max_distance_m) {
      print STDERR "Discarded by the distance filter: $_";
    } 

    my $sats= $json->{"sats"};
    if (defined $sats) {
      if ($sats < $min_sats) {
        print STDERR "Discarded by the sats filter: $_";
      } 
    }

    my $altitude = $json->{"alt"};
    if ($altitude > $max_altitude_m or $altitude < $min_altitude_m) {
      print STDERR "Discarded by the altitude filter: $_";
    } 

    my $id = $json->{"id"};

    filter_sonde_by_id($id) or next;

    if ($altitude < $decimation_alt) {
      # anyting below the $decimation_alt is reported immediately
      print $_;
      next;
    }
    else {
      # otherwise put in into the decimation  dictionary 
      lock (%messages_dict);
      $messages_dict{$id} = $_; 
    }

  } 
}

