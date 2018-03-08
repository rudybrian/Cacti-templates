#!/usr/bin/perl -w
#

# Parse JSON stats from Slush for Cacti
#
# Can be invoked in two seperate modes for each of the stats: User and Miners
#
# Sample invocation:
#
# User
#   query_slush_stats.pl HOST API_KEY user 
#
# Miners
#   query_slush_stats.pl HOST API_KEY miners index
#
######################
## Revision History ##
######################
#
# v0.01	7/5/2011 JinTu (jintuNO@SPAMpraecogito.com)
#	First working version. Supports worker totals and memcached.
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
my $check_interval = 150;
# The maximum amount of time to wait (in seconds) for the lock loop to wait before baling out and attempting to fix things
my $max_loop_time = 60;
#
###### Do not edit below here unless you know what you are doing
#

my $host = $ARGV[0];
my $api_key = $ARGV[1];
my $mode = $ARGV[2];

unless ((defined $host) && (defined $api_key) && (($mode eq "user") || ($mode eq "workers"))) {
  # Missing input params
  print "usage:\n\n./query_slush_stats.pl HOST API_KEY user\n\n" .
        "./query_slush_stats.pl HOST API_KEY workers index\n" . 
        "./query_slush_stats.pl HOST API_KEY workers num_indexes\n" . 
        "./query_slush_stats.pl HOST API_KEY workers query {worker_name,hashrate,shares,last_share,score}\n" . 
        "./query_slush_stats.pl HOST API_KEY workers get {worker_name,hashrate,shares,last_share,score} WORKER\n\n"; 
  exit;
}

my $json_url = "https://$host/accounts/profile/json/$api_key";
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
               'namespace' => "Cacti::Slush/$host/$api_key/",
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
     
    # Cacti needs whole numbers, so this needs to be divided by 100000000 to get the original value and retain full 8 digit precision
    if ($mode eq "user") {
       print "confirmed_rewards:" . $json_text->{confirmed_reward} * 100000000 . " " .
        "unconfirmed_rewards:" . $json_text->{unconfirmed_reward} * 100000000 . " " .
        "estimated_rewards:" . $json_text->{estimated_reward} * 100000000 . " " .
        "send_threshold:" . $json_text->{send_threshold} * 100000000;
    }
    elsif($mode eq "workers") {
      # Enumerate the worker names so we don't have indexing issues and get sums for total
      my %workerid;
      my %workertotal;
      foreach my $worker(keys %{$json_text->{workers}}) {
        #if (defined $json_text->{workers}->{$worker}->{worker_name}) {
          #$workerid{$json_text->{workers}->{$worker}->{worker_name}} = $worker;
          foreach my $wparam (keys %{$json_text->{workers}->{$worker}}) {
            unless ($wparam eq "worker_name") {
              if (defined $workertotal{$wparam}) {
                if ($wparam eq "last_share") {
                  $workertotal{$wparam} += convert_time($json_text->{workers}->{$worker}->{$wparam});
                }
                else {
                  $workertotal{$wparam} += $json_text->{workers}->{$worker}->{$wparam};
                }
              } 
              else {
                if ($wparam eq "last_share") {
                  $workertotal{$wparam} = convert_time($json_text->{workers}->{$worker}->{$wparam});
                }
                else {
                  $workertotal{$wparam} = $json_text->{workers}->{$worker}->{$wparam};
                }
              }
              #print "$wparam for " . $json_text->{workers}->{$worker}->{worker_name} . " set to " . $json_text->{workers}->{$worker}->{$wparam} . "\n";
            }
          }
        #}
      }     
      if (($ARGV[3] eq "get") && (defined $ARGV[4]) && (defined $ARGV[5])) {
        if ($ARGV[5] eq "total") {
            print $workertotal{$ARGV[4]};
        }
        elsif ($ARGV[4] eq "worker_name") {
          print $ARGV[5];
        }
        elsif (defined $json_text->{workers}->{$ARGV[5]}->{$ARGV[4]}) {
          if ($ARGV[4] eq "score") {
            # need to make this a whole number for Cacti
            printf ("%d", $json_text->{workers}->{$ARGV[5]}->{$ARGV[4]});  
          }
          elsif ($ARGV[4] eq "last_share") {
            print convert_time($json_text->{workers}->{$ARGV[5]}->{$ARGV[4]});
          }
          else {
            print $json_text->{workers}->{$ARGV[5]}->{$ARGV[4]};
          }
        }
      }
      elsif (($ARGV[3] eq "query") && (defined $ARGV[4])) {
        foreach my $worker_name (keys %{$json_text->{workers}}) {
          if ($ARGV[4] eq "worker_name") {
      	    print "$worker_name:$worker_name\n";
          }
          elsif (($ARGV[4] eq "hashrate") && (defined $json_text->{workers}->{$worker_name}->{hashrate})) {
      	    print "$worker_name:$json_text->{workers}->{$worker_name}->{hashrate}\n";
          }
          elsif (($ARGV[4] eq "shares") && (defined $json_text->{workers}->{$worker_name}->{shares})) {
      	    print "$worker_name:$json_text->{workers}->{$worker_name}->{shares}\n";
          }
          elsif (($ARGV[4] eq "last_share") && (defined $json_text->{workers}->{$worker_name}->{last_share})) {
      	    print "$worker_name:" . convert_time($json_text->{workers}->{$worker_name}->{last_share}) ."\n";
          }
          elsif (($ARGV[4] eq "score") && (defined $json_text->{workers}->{$worker_name}->{score})) {
      	    print "$worker_name:" . sprintf("%d",$json_text->{workers}->{$worker_name}->{score}) . "\n";
          }
        }
        if ($ARGV[4] eq "worker_name") {
          print "total:total\n";
        }
        elsif ($ARGV[4] eq "score") {
           print "total:" . sprintf("%d",$workertotal{$ARGV[4]}) . "\n";
        }
        else {
          print "total:" . $workertotal{$ARGV[4]} . "\n";
        }
      }
      elsif ($ARGV[3] eq "index") {
        foreach my $worker_name (keys %{$json_text->{workers}}) {
          print "$worker_name\n";
        }
        print "total\n";
      }
      elsif ($ARGV[3] eq "num_indexes") {
        print scalar(keys %{$json_text->{workers}}) + 1;
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

# Get the API JSON
sub fetch_json { 
   my ($url) = @_;
   my $request = HTTP::Request->new(GET => $url);
   my $ua = LWP::UserAgent->new;
   my $response = $ua->request($request);
   # Should do some error checking
   return $response->content();
}
