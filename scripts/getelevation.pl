#!/usr/bin/env perl

# http://vterrain.org/Elevation/global.html global datasets info page
#
# 3 arc second resolution
# http://viewfinderpanoramas.org/dem3.html
# download tiles manually from http://viewfinderpanoramas.org/Coverage%20map%20viewfinderpanoramas_org3.htm
# or http://viewfinderpanoramas.org/dem3/XYY.zip for a set of tiles
#
# X for the north side varies from A to U and from SA to SO for the north one
# YY is from 1 to 60
#
# this rule is not applied lineary and there're some fuckup regions with different naming convention
# so I just get tiles manually and unpack them locally
#

use strict;
use warnings;
 
my $lat = shift @ARGV;
my $lon = shift @ARGV;

die "Usage: $0 lat lon\n" if not ($lat and $lon);

my $NS="N"; my $EW="E";
my $sign = 1;

if ($lat < 0) {$NS="S";$sign=-1;};
if ($lon < 0) {$EW="W";$sign=-1;};
my $hgtfile = sprintf("./dem3/%s%d%s%03d.hgt", $NS, $sign*int($lat), $EW, $sign*int($lon));

#print STDERR "heightfile: $hgtfile\n";

my $lat_rounded; my $lon_rounded;
my $offset_row; my $offset_col;

if ($lat =~ /(-?\d*)(\.\d*)?/) {
  defined $2 ? ($lat_rounded = sprintf("%.5f", $2)) : ($lat_rounded = 0.0);
  $offset_row = int(1201*$lat_rounded);
}
if ($lon =~ /(-?\d*)(\.\d*)?/) {
  defined $2 ? ($lon_rounded = sprintf("%.5f", $2)) : ($lon_rounded = 0.0);
  $offset_col = int(1201*$lon_rounded);
}

#print STDERR "lat_rounded: $lat_rounded; lon_rounded: $lon_rounded\n";

my $offset = ((1200-$offset_row) * 1201 * 2) + ($offset_col*2);

#print STDERR "Opening $hgtfile with offset: $offset\n";
open my $in, '<:raw', $hgtfile or die;

seek($in, $offset, 0);
my $success = read $in, my $bytes, 2;
die $! if not defined $success;
last if not $success;

my $value = unpack('n', $bytes);
$value = unpack('s', pack('S',$value));
print "$value\n";

#while (1) {
#    my $success = read $in, my $bytes, 2;
#    die $! if not defined $success;
#    last if not $success;
#    my ($high, $low) = unpack 'C C', $bytes;
#    if ($high>127) {print "offset: $offset high $high low $low\n";}
##    print 256*$high+$low . " ";
#    $offset += 2;
#    if (not $offset % (2*1201)) {
##      print "\n";
#    }
#    if (not $offset % (2*1201*1201)) {
#      last;
#    }    
#}

close $in;
