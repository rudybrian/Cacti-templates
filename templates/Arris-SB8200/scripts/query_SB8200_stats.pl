#!/usr/bin/perl -w
#

# Parse stats from Arris SB8200 DOCSIS modem for Cacti
#
# Can be invoked in two seperate modes for each of the stats: up and down
#
# Sample invocation:
#
# Up
#   query_sb8200_stats.pl HOST up index 
#
# Down
#   query_sb8200_stats.pl HOST down index
#
######################
## Revision History ##
######################
#
# v0.01	3/9/2018 Brian Rudy (brudyNO@SPAMpraecogito.com)
#	First working version. Must use memcached as the SB8200 responds too slowly to use an indexed query without it.
# 

use strict;
use JSON -support_by_pp;
use HTTP::Request;
use LWP::UserAgent;

my $memcached_server;
# Uncomment the following three lines and set $memcached_server as appropriate if you are using memcached
use Cache::Memcached;
use IO::Socket::INET;
$memcached_server = "localhost:11211";
#
# The API JSON check interval in seconds. Should be slightly less than your polling interval to ensure fresh data each polling cycle
my $check_interval = 120;
# The maximum amount of time to wait (in seconds) for the lock loop to wait before baling out and attempting to fix things
my $max_loop_time = 60;
#
###### Do not edit below here unless you know what you are doing
#

my $host = $ARGV[0];
my $mode = $ARGV[1];

unless ((defined $host) && (($mode eq "Up") || ($mode eq "Down"))) {
  # Missing input params
  show_help();
}

my $json_url = "http://$host/cmconnectionstatus.html";
my $content;

eval{
    # download the json page:
    if (defined $memcached_server) {
       # Memcached is enabled
       #print "Using memcached\n";
       my $msock = IO::Socket::INET->new( PeerAddr => $memcached_server,
                                          Timeout  => 3);
       unless ($msock) {
          print "Unable to connected to memcached server at $memcached_server, aborting!\n";
          exit 0;
       }
       my $memd = new Cache::Memcached {
               'servers' => [ $memcached_server ],
               'debug' => 0,
               'compress_threshold' => 10_000,
               'namespace' => "Cacti::SB8200/$host/",
       };
       # Check the timestamp
       my $timestamp = $memd->get("timestamp");
       my $api_json = $memd->get("api_json");
       if ((defined $timestamp) && (defined $api_json)) {
          # Check if we are beyond the check interval based on the last timestamp
          if (time() >= ($timestamp + $check_interval)) {
             # We have exceeded the check interval and might need to fetch an update if no one else is.
             unless (defined $memd->get("lock")) {
                $memd->set("lock", 1);
                $content = fetch_json($json_url);
                $memd->set("api_json", $content);
                $memd->set("timestamp", time());
                $memd->delete("lock");
             }
             else {
                #print "Locked\n";
                # Loop for a while waiting for the lock to clear
                my $time_elapsed = 0;
                while (defined $memd->get("lock")) {
                   #print "locked, looping. time_elapsed = $time_elapsed\n";
                   # sleep for a random amount of time from 100-600ms
                   my $wait_time = 0.1 + (int(rand(500)) * 0.001);
                   select(undef, undef, undef, $wait_time);
                   $time_elapsed += $wait_time;
                   if ($time_elapsed >= $max_loop_time) {
                      # Loop timer elapsed. Something has gone wrong
                      $content = fetch_json($json_url);
                      $memd->set("api_json", $content);
                      $memd->set("timestamp", time());
                      $memd->delete("lock");
                   }
                }
                # Assume that now that the lock is cleared, the data is current
                #print "Lock loop has exited\n";
                $content = $api_json;
             }
          }
          else {
             #print "Data in cache is current:" . time() . " > " . ($timestamp + $check_interval) . "\n";
             # We don't need to check again, just use the cached value
             $content = $api_json;
          }
       }
       else {
          # timestamp and/or json aren't defined (e.g. first run). We need to fetch the JSON and set the timestamp
          $memd->set("lock", 1);
          $content = fetch_json($json_url);
          $memd->set("api_json", $content);
          $memd->set("timestamp", time());
          $memd->delete("lock");
       }
    }
    else {
       # not using memcached, so fetch every time
       $content = fetch_json($json_url);
    }

    # Simple validation prior to parsing
    if ($content eq "") {
      print "$host API returned null, not valid JSON!\n";
      exit 0;
    }
    my $json = new JSON;
 
    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($content);

    if (($mode eq "Up") || ($mode eq "Down")) {
        if (($ARGV[2] eq "get") && (defined $ARGV[3]) && (defined $ARGV[4])) {
		if (defined $json_text->{$mode}->{$ARGV[3]}->[$ARGV[4]]) {
			print $json_text->{$mode}->{$ARGV[3]}->[$ARGV[4]];
		}
	}
	elsif (($ARGV[2] eq "query") && (defined $ARGV[3])) {
		if (defined $json_text->{$mode}->{$ARGV[3]}) {
			for my $element (0..$#{$json_text->{$mode}->{$ARGV[3]}}) {
				print "$element:$json_text->{$mode}->{$ARGV[3]}->[$element]\n";
			}
		}
	}
	elsif ($ARGV[2] eq "index") {
		for my $element (0..$#{$json_text->{$mode}->{Chan}}) {
			print "$element\n";
		}
	}
	elsif ($ARGV[2] eq "num_indexes") {
		print scalar(@{$json_text->{$mode}->{Chan}}) . "\n";
	}
	else {
		show_help();
	}
  }
};
# catch crashes:
if($@){
	print "Crash detected: $@\n";
}

# Convert HH:MM:SS into seconds
sub convert_time {
   my ($time_in) = @_;
   return (time() - $time_in); 
}

# Print the help text
sub show_help {
  print "usage:\n\n./query_sb8200_stats.pl HOST Up index\n" .
	"./query_sb8200_stats.pl HOST Up num_indexes\n" .
	"./query_sb8200_stats.pl HOST Up query (Chan,ChanId,Stat,Type,Freq,Width,Power)\n" .
	"./query_sb8200_stats.pl HOST Up get (Chan,ChanId,Stat,Type,Freq,Width,Power) INDEX\n\n" .
	"./query_sb8200_stats.pl HOST Down index\n" .
	"./query_sb8200_stats.pl HOST Down num_indexes\n" .
	"./query_sb8200_stats.pl HOST Down query (Chan,Stat,Type,Freq,Power,SNR,CorrCw,UncorrCW)\n" .
	"./query_sb8200_stats.pl HOST Down get (Chan,Stat,Type,Freq,Power,SNR,CorrCw,UncorrCW) INDEX\n\n";
  exit;
}

# Get the API JSON
sub fetch_json { 
	my ($url) = @_;
	my $request = HTTP::Request->new(GET => $url);
	my $ua = LWP::UserAgent->new;
	my $response = $ua->request($request);
	# Should do some error checking
	my $content = $response->content();
	my %data;
	$content =~ tr/\r\n//d; # Strip all the linefeeds
	# New format as of SB8200.0200.174F.311915.NSH.RT.NA
	#<tr align='left'>      <td>31</td>      <td>Locked</td>      <td>QAM256</td>      <td>723000000 Hz</td>      <td>2.1 dBmV</td>      <td>37.7 dB</td>      <td>2</td>      <td>0</td>   </tr>
	# parse the down stats
	#while ($content =~ /<tr>\s*<td>(\d*)<\/td>\s*<td>(\w+)<\/td>\s*<td>(QAM\d+|Other)<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>([-]?[0-9]*\.?[0-9]+)\s*dBmV<\/td>\s*<td>([0-9]*\.?[0-9]+)\s*dB<\/td>\s*<td>(\d*)<\/td>\s*<td>(\d*)<\/td>\s*<\/tr>/g) {
	while ($content =~ /<tr\salign=\'left\'>\s*<td>(\d*)<\/td>\s*<td>(\w+)<\/td>\s*<td>(QAM\d+|Other)<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>([-]?[0-9]*\.?[0-9]+)\s*dBmV<\/td>\s*<td>([0-9]*\.?[0-9]+)\s*dB<\/td>\s*<td>(\d*)<\/td>\s*<td>(\d*)<\/td>\s*<\/tr>/g) {
		#print "channel:$1\n";
		push @{$data{Down}{Chan}}, $1;
		#print "status:$2\n";
		push @{$data{Down}{Stat}}, $2;
		#print "type:$3\n";
		push @{$data{Down}{Type}}, $3;
		#print "frequency:$4\n";
		push @{$data{Down}{Freq}}, $4;
		#print "power:$5\n";
		push @{$data{Down}{Power}}, $5 * 10;
		#print "SNR:$6\n";
		push @{$data{Down}{SNR}}, $6 * 10;
		#print "corrected:$7\n";
		push @{$data{Down}{CorrCw}}, $7;
		#print "uncorrectable:$8\n\n";
		push @{$data{Down}{UncorrCw}}, $8;
	}

	# New format as of SB8200.0200.174F.311915.NSH.RT.NA
	#<tr align='left'>      <td>1</td>      <td>4</td>      <td>Locked</td>      <td>SC-QAM Upstream</td>      <td>36700000 Hz</td>      <td>6400000 Hz</td>      <td>55.0 dBmV</td>   </tr> 
	# Parse the up stats
	#while ($content =~ /<tr>\s*<td>(\d*)<\/td>\s*<td>(\d*)<\/td>\s*<td>(\w*)<\/td>\s*<td>([a-zA-Z0-9-]+)<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>([0-9]*\.?[0-9]+)\s*dBmV<\/td>\s*/g) {
	while ($content =~ /<tr\salign=\'left\'>\s*<td>(\d*)<\/td>\s*<td>(\d*)<\/td>\s*<td>(\w*)<\/td>\s*<td>([a-zA-Z0-9-\s]+)<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>([0-9]*\.?[0-9]+)\s*dBmV<\/td>\s*/g) {
		#print "channel:$1\n";
		push @{$data{Up}{Chan}}, $1;
		#print "channel id:$2\n";
		push @{$data{Up}{ChanId}}, $2;
		#print "status:$3\n";
		push @{$data{Up}{Stat}}, $3;
		#print "type:$4\n";
		push @{$data{Up}{Type}}, $4;
		#print "frequency:$5\n";
		push @{$data{Up}{Freq}}, $5;
		#print "width:$6\n";
		push @{$data{Up}{Width}}, $6;
		#print "power:$7\n\n";
		push @{$data{Up}{Power}}, $7 * 10;
	}

	# Convert $data to JSON text
	to_json(\%data);
}
