#!/usr/bin/env perl

# http://vterrain.org/Elevation/global.html global elevations datasets info page
#
# For 3 arc second resolution
# http://viewfinderpanoramas.org/dem3.html
# download tiles manually from http://viewfinderpanoramas.org/Coverage%20map%20viewfinderpanoramas_org3.htm
# or http://viewfinderpanoramas.org/dem3/XYY.zip for a set of tiles
#
# X for the north side varies from A to U and from SA to SO for the north one
# YY is from 1 to 60
#
# This rule is not applied lineary and there're some regions with different naming convention
# so I just get tiles manually and unpack them locally
#
# Some values inside of hgt files are missing or wrong they are presented by '0x80 0x00' or -32768
# This script is supposed to fix such issues. I do the following:
# 
# ```
# for i in dem3/*.hgt; do echo -ne "---------------------- ";echo "$i";./fixheightfile.pl "$i"; done
# ```

use strict;
use warnings;
 
my $hgtfile  = shift @ARGV;

die "Usage: $0 height file\n" if not $hgtfile;
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

#print STDERR "heightfile: $hgtfile\n";

my $offset;

open my $in, '+<:raw', $hgtfile or die;

my $minheight = -500;
my $maxheight = 10000;

while (1) {
    my $success = read $in, my $bytes, 2;
    die $! if not defined $success;
    last if not $success;
    my $value = unpack('n', $bytes);
    $value = unpack('s', pack('S',$value));

    # anything higher than 10km and lower than 500m should be corrected
    if ($value>$maxheight or $value < $minheight) {
      my %point;
      $point{"offset"} = tell($in) - 2;
      $point{"value"} = $value;
      $point{"left"} = -32768;
      $point{"right"} = -32768;
      $point{"up"} = -32768;
      $point{"down"} = -32768;
      # read word to the right
      if ( ($point{"offset"} % ($rowSize*2)) < (($rowSize-1)*2) ) {
        $success = read $in, $bytes, 2;
        if ($success) {
          $value = unpack('n', $bytes);
          $value = unpack('s', pack('S',$value));
          $point{"right"} = $value;
        }
      }
      # read word to the left
      if ( ($point{"offset"} % ($rowSize*2)) > 0 ) {
        seek($in, $point{"offset"} - 2, 0);
        $success = read $in, $bytes, 2;
        if ($success) {
          $value = unpack('n', $bytes);
          $value = unpack('s', pack('S',$value));
          $point{"left"} = $value;
        }
      }
      # read word above
      if ( $point{"offset"} > (($rowSize-1)*2) ) {
        seek($in, $point{"offset"} - $rowSize*2, 0);
        $success = read $in, $bytes, 2;
        if ($success) {
          $value = unpack('n', $bytes);
          $value = unpack('s', pack('S',$value));
          $point{"up"} = $value;
        }
      }
      # read word below
      if ( $point{"offset"} < ($rowSize*($rowSize-1)*2) ) {
        seek($in, $point{"offset"} + $rowSize*2, 0);
        $success = read $in, $bytes, 2;
        if ($success) {
          $value = unpack('n', $bytes);
          $value = unpack('s', pack('S',$value));
          $point{"down"} = $value;
        }
      }

      print "offset: " . $point{"offset"} . "\n";

      print "    " . $point{"up"} . "\n";
      print $point{"left"} . " " . $point{"value"} . " " . $point{"right"} . "\n";
      print "    " . $point{"down"} . "\n\n";

      my $newValue = -32768;

      if ($point{"left"}<$maxheight and $point{"right"}<$maxheight and 
          $point{"down"}<$maxheight and $point{"up"}<$maxheight and
          $point{"left"}>$minheight and $point{"right"}>$minheight and 
          $point{"down"}>$minheight and $point{"up"}>$minheight)
      {
        # calculate average over 4 points
        $newValue = int(($point{"left"} + $point{"right"} + $point{"down"} + $point{"up"})/4);
      }
      elsif ($point{"down"}<$maxheight and $point{"up"}<$maxheight and
             $point{"down"}>$minheight and $point{"up"}>$minheight) {
        $newValue = int(($point{"down"} + $point{"up"})/2);
      }
      elsif ($point{"left"}<$maxheight and $point{"right"}<$maxheight and
             $point{"left"}>$minheight and $point{"right"}>$minheight) {
        $newValue = int(($point{"left"} + $point{"right"})/2);
      }
      elsif ($point{"left"}<$maxheight and $point{"down"}<$maxheight and
             $point{"left"}>$minheight and $point{"down"}>$minheight) {
        $newValue = int(($point{"left"} + $point{"down"})/2);
      }
      elsif ($point{"left"}<$maxheight and $point{"up"}<$maxheight and
             $point{"left"}>$minheight and $point{"up"}>$minheight) {
        $newValue = int(($point{"left"} + $point{"up"})/2);
      }
      elsif ($point{"left"}<$maxheight and $point{"down"}<$maxheight and
             $point{"left"}>$minheight and $point{"down"}>$minheight) {
        $newValue = int(($point{"left"} + $point{"down"})/2);
      }
      elsif ($point{"right"}<$maxheight and $point{"up"}<$maxheight and
             $point{"right"}>$minheight and $point{"up"}>$minheight) {
        $newValue = int(($point{"right"} + $point{"up"})/2);
      }
      elsif ($point{"right"}<$maxheight and $point{"down"}<$maxheight and
             $point{"right"}>$minheight and $point{"down"}>$minheight) {
        $newValue = int(($point{"right"} + $point{"down"})/2);
      }

      if ($newValue > $minheight) {
        print "\nNew point:\n";
        print "    " . $point{"up"} . "\n";
        print $point{"left"} . " " . $newValue . " " . $point{"right"} . "\n";
        print "    " . $point{"down"} . "\n\n";

        # replacing the old value
        seek($in, $point{"offset"}, 0);
        $newValue = unpack('S', pack('s' , $newValue));
        $bytes = pack('C*', int($newValue / 256), $newValue % 256);
        print $in $bytes;
      }


      # put the file pointer back
      seek($in, $point{"offset"} + 2, 0);
    }

    $offset += 2;
    if (not $offset % (2*$rowSize*$rowSize)) {
      last;
    }    
}

close $in;
