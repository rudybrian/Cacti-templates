#!/usr/bin/perl -w
#

# Parse JSON stats from BTC Guild for Cacti
#
# Can be invoked in three seperate modes for each of the stats: User, Miners and Total all pools
#
# Sample invocation:
#
# User
#   query_btcguild_stats.pl HOST API_KEY user 
#
# Miners
#   query_btcguild_stats.pl HOST API_KEY miners index
#
# Total all pools
#   query_btcguild_stats.pl HOST API_KEY total_all_pools
#
######################
## Revision History ##
######################
# v0.08 5/12/2013 (jintuNO@SPAMpraecogito.com)
#	Minor change to impersonate a real browser to keep CloudFlare happy.
#
# v0.07 5/7/2012 (jintuNO@SPAMpraecogito.com)
#	Major rework for comprehensive support of the new PPS API and simplification of the script. Requires nearly all Cacti templates to be reworked as well. 
#	Removed Pool stats as there is no API support by BTCGuild for pool stats anymore.
#
# v0.06 10/24/2011 JinTu (jintuNO@SPAMpraecogito.com)
# 	Re-worked to support change to PPS pool.
#
# v0.05 7/14/2011 JinTu (jintuNO@SPAMpraecogito.com)
#	Added 24 hour totals now that this has been added to the BTC Guild JSON. Minor bugfix to not blow up when we "never" in last_share responses.
# 
# v0.04 7/5/2011 JinTu (jintuNO@SPAMpraecogito.com)
#	Minor bugfixes for worker indexing after the addition of worker totals. Added more specific memcached namespace. Added simple check for when the API JSON gives us null.
#
# v0.03 7/3/2011 JinTu (jintuNO@SPAMpraecogito.com)
#	Added worker totals
#
# v0.02 6/29/2011 JinTu (jintuNO@SPAMpraecogito.com)
#	Added simple JSON caching via memcached resulting in big performance boost:
#        Before -> SYSTEM STATS: Time:114.1648 Method:spine Processes:2 Threads:4 Hosts:12 HostsPerProcess:6 DataSources:159 RRDsProcessed:105
#        After  -> SYSTEM STATS: Time:19.5116 Method:spine Processes:2 Threads:4 Hosts:12 HostsPerProcess:6 DataSources:159 RRDsProcessed:105
#
# v0.01	6/24/2011 JinTu (jintuNO@SPAMpraecogito.com)
#	First working version. Only supports btcguild stats for now. No JSON query caching support (Slow!). 
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
# The API JSON check interval in seconds. Should be slightly less than your polling interval to ensure fresh data each polling cycle, 
# but more than the minimum update interval
my $check_interval = 70;
# The maximum amount of time to wait (in seconds) for the lock loop to wait before baling out and attempting to fix things
my $max_loop_time = 40;
#
###### Do not edit below here unless you know what you are doing
#

my $host = $ARGV[0];
my $api_key = $ARGV[1];
my $mode = $ARGV[2];

unless ((defined $host) && (defined $api_key) && (($ARGV[2] eq "user") || ($ARGV[2] eq "workers") || ($ARGV[2] eq "pool") || ($ARGV[2] eq "total_all_pools"))) {
  # Missing input params
  print "usage:\n\n./query_btcguild_stats.pl HOST API_KEY user\n\n" .
        "./query_btcguild_stats.pl HOST API_KEY workers index\n" . 
        "./query_btcguild_stats.pl HOST API_KEY workers num_indexes\n" . 
        "./query_btcguild_stats.pl HOST API_KEY workers query {worker_name,hash_rate,valid_shares,stale_shares,dupe_shares,unknown_shares,valid_shares_since_reset,stale_shares_since_reset,dupe_shares_since_reset,unknown_shares_since_reset,valid_shares_nmc,stale_shares_nmc,dupe_shares_nmc,unknown_shares_nmc,valid_shares_nmc_since_reset,stale_shares_nmc_since_reset,dupe_shares_nmc_since_reset,unknown_shares_nmc_since_reset,last_share}\n" . 
        "./query_btcguild_stats.pl HOST API_KEY workers get {worker_name,hash_rate,valid_shares,stale_shares,dupe_shares,unknown_shares,valid_shares_since_reset,stale_shares_since_reset,dupe_shares_since_reset,unknown_shares_since_reset,valid_shares_nmc,stale_shares_nmc,dupe_shares_nmc,unknown_shares_nmc,valid_shares_nmc_since_reset,stale_shares_nmc_since_reset,dupe_shares_nmc_since_reset,unknown_shares_nmc_since_reset,last_share} WORKER\n\n" . 
        "./query_btcguild_stats.pl HOST API_KEY total_all_pools\n";
  exit 0;
}

my $json_url = "https://$host/api.php?api_key=$api_key";
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
               'namespace' => "Cacti::BTCGuild/$host/$api_key/",
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
    elsif ($content =~ m/<!DOCTYPE HTML>/) {
      print "$host returned HTML response rather than JSON:$content\n";
      exit 0;
    }
    my $json = new JSON;
 
    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($content);
     
    # Cacti needs whole numbers, so this needs to be divided by 100000000 to get the original value and retain full 8 digit precision
    if ($mode eq "user") {
       my $user_string;
       foreach my $user (keys %{$json_text->{user}}) {
	 if ($user eq "user_id") {
           $user_string .= "$user:" . $json_text->{user}->{$user} . " ";
         }
         else {
           # This only works if everything else is in BTC
           $user_string .= "$user:" . ($json_text->{user}->{$user} * 100000000) . " "; 
         }
       }
       # Strip the trailing space
       $user_string =~ s/\s$//g;
       print $user_string;
    }
    elsif($mode eq "workers") {
      # Enumerate the worker names so we don't have indexing issues and get sums for total
      my %workerid;
      my %workertotal;
      foreach my $worker (keys %{$json_text->{workers}}) {
        if (defined $json_text->{workers}->{$worker}->{worker_name}) {
          $workerid{$json_text->{workers}->{$worker}->{worker_name}} = $worker;
          foreach my $wparam (keys %{$json_text->{workers}->{$worker}}) {
            unless ($wparam eq "worker_name") {
              if (defined $workertotal{$wparam}) {
                if (($wparam eq "last_share") && ($json_text->{workers}->{$worker}->{$wparam} eq "never")) {
                  $workertotal{$wparam} += 0;
                }
                else {
                  $workertotal{$wparam} += $json_text->{workers}->{$worker}->{$wparam};
                }
              } 
              else {
                if (($wparam eq "last_share") && ($json_text->{workers}->{$worker}->{$wparam} eq "never")) {
                  $workertotal{$wparam} = 0;
                }
                else {
                  $workertotal{$wparam} = $json_text->{workers}->{$worker}->{$wparam};
                }
              }
              #print "$wparam for " . $json_text->{workers}->{$worker}->{worker_name} . " set to " . $json_text->{workers}->{$worker}->{$wparam} . "\n";
            }
          }
        }
      }     
      if (($ARGV[3] eq "get") && (defined $ARGV[4]) && (defined $ARGV[5])) {
        if ($ARGV[5] eq "total") {
          if ($ARGV[4] eq "hash_rate") {
            # need to make this a whole number for Cacti
            printf ("%d", $workertotal{$ARGV[4]});
          }
          else {
            print $workertotal{$ARGV[4]};
          }
        }
        elsif (defined $json_text->{workers}->{$workerid{$ARGV[5]}}->{$ARGV[4]}) {
          if ($ARGV[4] eq "hash_rate") {
            # need to make this a whole number for Cacti
            printf ("%d", $json_text->{workers}->{$workerid{$ARGV[5]}}->{$ARGV[4]});  
          }
          elsif ($ARGV[4] eq "last_share") {
            if ($json_text->{workers}->{$workerid{$ARGV[5]}}->{$ARGV[4]} eq "never") {
              print "NaN";
            }
            else {
              print $json_text->{workers}->{$workerid{$ARGV[5]}}->{$ARGV[4]};
            }
          }
          else {
            print $json_text->{workers}->{$workerid{$ARGV[5]}}->{$ARGV[4]};
          }
        }
      }
      elsif (($ARGV[3] eq "query") && (defined $ARGV[4])) {
        foreach my $worker_name (keys %workerid) {
          if (($ARGV[4] eq "hash_rate") && (defined $json_text->{workers}->{$workerid{$worker_name}}->{hash_rate})) {
      	    print "$worker_name:" . sprintf("%d",$json_text->{workers}->{$workerid{$worker_name}}->{hash_rate}) ."\n";
          }
          elsif (($ARGV[4] eq "last_share") && (defined $json_text->{workers}->{$workerid{$worker_name}}->{last_share})) {
            if ($json_text->{workers}->{$workerid{$worker_name}}->{last_share} eq "never") {
              print "$worker_name:NaN\n";
            }
            else {
      	      print "$worker_name:$json_text->{workers}->{$workerid{$worker_name}}->{last_share}\n";
            }
          }
          elsif (defined $json_text->{workers}->{$workerid{$worker_name}}->{$ARGV[4]}) {
            # Just assume they know what they are asking for
            print "$worker_name:$json_text->{workers}->{$workerid{$worker_name}}->{$ARGV[4]}\n";
          }
        }
        if ($ARGV[4] eq "worker_name") {
          print "total:total\n";
        }
        elsif ($ARGV[4] eq "hash_rate") {
           print "total:" . sprintf("%d",$workertotal{$ARGV[4]}) . "\n";
        }
        else {
          print "total:" . $workertotal{$ARGV[4]} . "\n";
        }
      }
      elsif ($ARGV[3] eq "index") {
        foreach my $worker_name (keys %workerid) {
          print "$worker_name\n";
        }
        print "total\n";
      }
      elsif ($ARGV[3] eq "num_indexes") {
        print scalar(keys %workerid) + 1;
      }
    }
    elsif ($mode eq "total_all_pools") {
      print "pool_speed:" . sprintf("%d", $json_text->{pool}->{pool_speed}) . " " .
         "pps_rate:" . sprintf("%.0f", $json_text->{pool}->{pps_rate} * 100000000000000000000) . " " .
         "difficulty:$json_text->{pool}->{difficulty}" . " " .
         "pps_rate_nmc:" . sprintf("%.0f", $json_text->{pool}->{pps_rate_nmc} * 100000000000000000000) . " " .
         "difficulty_nmc:$json_text->{pool}->{difficulty_nmc}";
    }
  };
  # catch crashes:
  if($@){
    print "Crash detected: $@\n";
  }

# Convert HH:MM:SS into seconds
sub convert_time {
   my ($time_in) = @_;
   my ($hours,$minutes,$seconds) = $time_in =~ m/(\d*):(\d*):(\d*)/;
   return $seconds + ($minutes * 60) + ($hours * 60 * 60); 
}

# Get the API JSON
sub fetch_json { 
   my ($url) = @_;
   my $request = HTTP::Request->new(GET => $url);
   my $ua = LWP::UserAgent->new;
   # BTCGuild has started blocking our UA string, so we need to impersonate a browser
   $ua->agent('Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.31 (KHTML, like Gecko) Chrome/26.0.1410.64 Safari/537.31');
   my $response = $ua->request($request);
   # Should do some error checking
   return $response->content();
}
