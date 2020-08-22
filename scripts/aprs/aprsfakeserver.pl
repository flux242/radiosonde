#!/usr/bin/perl

#
# Fake APRS-IS. Use it the following way:
# 1. Start socat -d -d TCP-LISTEN:14580,reuseaddr,fork exec:./aprsfakeserver.pl,pty,stderr
# 2. Create an APRS-IS Port in YAAC (localhost, port 14580) and activate it 
# 3. Broadcast APRS messages on the UDP port 30448 on the local machine or the local network
#

use strict;
use warnings;
use sigtrap 'handler' => \&sig_handler, qw(INT TERM KILL QUIT);
use Socket;

my ($soc_listen,$soc_broadcast);
my $paddr;
my @pids;

sub sig_handler {
  print "Signal handler is called, exiting...\n";
  kill HUP => $pids[0];
  kill HUP => $pids[1];
  exit(0);
}

# flush after every write
$| = 1;

my $port = '30448'; # TODO make the port number configurable
my $remote = '0.0.0.0';
my $server_ping="# aprsfakeserver (c) 0v2\n";

# create sockets to listen and broadcast
socket($soc_listen, AF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "Can't open socket $!\n";
socket($soc_broadcast, AF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "Can't open socket $!\n";
 
setsockopt($soc_listen, SOL_SOCKET, SO_REUSEADDR, 1) or die "Can't set socket option to SO_REUSEADDR $!\n";
setsockopt($soc_broadcast, SOL_SOCKET, SO_BROADCAST, 1) or die "Can't set socket option to  SO_BROADCAST $!\n";
 
my $iaddr = inet_aton($remote) or die "Unable to resolve hostname : $remote";
$paddr = sockaddr_in($port, $iaddr); #socket address structure

my $child = 0;

for ( my $i = 0; $i<2; $i++)
{
  my $pid = fork();
  die "Error in fork: $!" unless defined $pid;
  $pids[$i] = $pid;

  if (not $pid) {
    if (not $child) {
      # Code executed by the child process 0
      bind($soc_listen, $paddr) or die "Connect failed : $!";
      print "# Connected to $remote on port $port\n";
      local $SIG{HUP} = sub { close($soc_listen);exit(0); };
#my $dfd;
      while(1) {
#open($dfd, ">>/tmp/aprs.out");
        my $result = '';
        my $datastring = '';
        my $hispaddr;
        $hispaddr = recv($soc_listen, $datastring, 400, 0); # blocking recv MSG_WAITALL
        if (!defined($hispaddr)) {
          print ("# recv failed: $!\n");
#print $dfd ("# recv failed: $!\n");
          last;
        }
        $datastring =~ s/[\r\n]+$//;
#print $dfd "i: $datastring\n";
        if ($datastring =~ /^$/) {
          next;
        }
        if ($datastring =~ /^#.*$/) {
          $result = $datastring; # just print comment (ping) messages
        }
        elsif ($datastring =~ /^user ([^ ]*).*$/) {
          my $user_name = $1;
          # now check if filter string is also there
          $datastring =~ /^user ([^ ]*).*(filter.*?)$/;
          $result = "# logresp $user_name verified, server N0APRS-1 " . ($2 // "");
        }
        elsif ($datastring =~ /^APRS: (.*)$/) {
          $result = "$1\n";
        }
        else {
##          $result = "# $datastring"; # all other strings are commented out
          $result = $datastring;
        }
        print "$result\n";
#print $dfd "o: ${result}\n";
#close($dfd);
      }
      close($soc_listen);
      exit(0);
    }
    else {
      # Code executed by the child process 1
      my $pingcounter = 0;
      my $doexit = 0;
      local $SIG{HUP} = sub { $doexit = 1 };
      # Code executed by the second child process
      while(not $doexit) {
        $pingcounter = $pingcounter + 1;
        select(undef, undef, undef, 0.25); # sleep 250 ms
        if (not $pingcounter % (60*4)) {
          send($soc_broadcast, $server_ping, 0, $paddr);
        }
      }
      exit(0);
    }
  }
  $child = $child + 1;
}

select(undef, undef, undef, 0.25); # sleep 250 ms
send($soc_broadcast, $server_ping, 0, $paddr);

while(<STDIN>) {
  send($soc_broadcast, $_, 0, $paddr);
}

