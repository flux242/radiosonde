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
my $tilesFolder = shift @ARGV;
$tilesFolder = "./dem3" if not $tilesFolder;

die "Usage: $0 lat lon\n" if not ($lat and $lon);

my $NS="N"; my $EW="E";
my $signNS = 1;
my $signEW = 1;

if ($lat < 0) {$NS="S";$signNS=-1;};
if ($lon < 0) {$EW="W";$signEW=-1;};
my $hgtfile = sprintf("%s/%s%d%s%03d.hgt", $tilesFolder, $NS, $signNS*int($lat), $EW, $signEW*int($lon));

#print STDERR "heightfile: $hgtfile\n";
die "$hgtfile file is not found\n" if not -e $hgtfile;

my $HGT_3_SEC_ROW_SIZE = 1201;
my $HGT_1_SEC_ROW_SIZE = 3601;

my $rowSize = 0;

my $fileSize = -s $hgtfile;
die "hgt file should be either " . 1201*1201*2 . " or " . 3601*3601*2 . " bytes in size\n" if not ($fileSize==1201*1201*2 or $fileSize==3601*3601*2);

#print $fileSize . "\n";
if ($HGT_3_SEC_ROW_SIZE*$HGT_3_SEC_ROW_SIZE*2 == $fileSize) {
  $rowSize = $HGT_3_SEC_ROW_SIZE;
}
if ($HGT_1_SEC_ROW_SIZE*$HGT_1_SEC_ROW_SIZE*2 == $fileSize) {
  $rowSize = $HGT_1_SEC_ROW_SIZE;
}
die if ($rowSize == 0);


my $lat_rounded; my $lon_rounded;
my $offset_row; my $offset_col;

if ($lat =~ /(-?\d*)(\.\d*)?/) {
  defined $2 ? ($lat_rounded = sprintf("%.5f", $2)) : ($lat_rounded = 0.0);
  $offset_row = int($rowSize*$lat_rounded);
}
if ($lon =~ /(-?\d*)(\.\d*)?/) {
  defined $2 ? ($lon_rounded = sprintf("%.5f", $2)) : ($lon_rounded = 0.0);
  $offset_col = int($rowSize*$lon_rounded);
}

#print STDERR "lat_rounded: $lat_rounded; lon_rounded: $lon_rounded\n";

my $offset = ((($rowSize-1)-$offset_row) * $rowSize * 2) + ($offset_col*2);

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
