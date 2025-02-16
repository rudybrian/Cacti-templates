#!/usr/bin/perl -w
#

# Parse stats from Arris S33 or S34 DOCSIS modem for Cacti
#
# Can be invoked in two seperate modes for each of the stats: up and down
#
# Sample invocation:
#
# Up
#   query_s33_stats.pl HOST password Up index 
#
# Down
#   query_s33_stats.pl HOST password Down index
#
######################
## Revision History ##
######################
#
# v0.02 12/26/2024 Brian Rudy (brudyNO@SPAMpraecogito.com)
# 	Added support for S34 modems that use HMAC SHA256 instead of HMAC MD5. S34 also has floating point values for the power and SNR which required updating the regex to support both cases.
#
# v0.01	4/3/2022 Brian Rudy (brudyNO@SPAMpraecogito.com)
#	First working version (based on my earlier SB8200 version). Must use memcached as the S33 responds too slowly to use an indexed query without it.
#

use strict;
use JSON -support_by_pp;
use HTTP::Request;
use HTTP::Cookies;
use LWP::UserAgent;
use IO::Socket::SSL;
use Digest::HMAC_MD5;
use Digest::SHA qw(hmac_sha256_hex);
use Encode;
use Time::HiRes;
#use Data::Dumper qw( Dumper );

my $memcached_server;
# Uncomment the following three lines and set $memcached_server as appropriate if you are using memcached
use Cache::Memcached;
use IO::Socket::INET;
$memcached_server = "localhost:11211";

# Change $device_type to S33 if that is what you have. S33 uses HMAC_MD5 and S34 uses HMAC SHA256 HNAP authentication 
my $device_type = "S34";
# The API JSON check interval in seconds. Should be slightly less than your polling interval to ensure fresh data each polling cycle
my $check_interval = 120;
# The maximum amount of time to wait (in seconds) for the lock loop to wait before baling out and attempting to fix things
my $max_loop_time = 60;
#
###### Do not edit below here unless you know what you are doing
#
# We need to disable certificate hostname validation because the device uses a self-signed cert
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

my $host = $ARGV[0];
my $passwd = $ARGV[1];
my $mode = $ARGV[2];

unless ((defined $host && defined $passwd) && (($mode eq "Up") || ($mode eq "Down"))) {
  # Missing input params
  show_help();
}

my $base_url = "https://$host/HNAP1/";
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
               'namespace' => "Cacti::S33/$host/",
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
                $content = fetch_json($base_url);
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
                      $content = fetch_json($base_url);
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
          $content = fetch_json($base_url);
          $memd->set("api_json", $content);
          $memd->set("timestamp", time());
          $memd->delete("lock");
       }
    }
    else {
       # not using memcached, so fetch every time
       $content = fetch_json($base_url);
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
        if (($ARGV[3] eq "get") && (defined $ARGV[4]) && (defined $ARGV[5])) {
		if (defined $json_text->{$mode}->{$ARGV[4]}->[$ARGV[5]]) {
			print $json_text->{$mode}->{$ARGV[4]}->[$ARGV[5]];
		}
	}
	elsif (($ARGV[3] eq "query") && (defined $ARGV[4])) {
		if (defined $json_text->{$mode}->{$ARGV[4]}) {
			for my $element (0..$#{$json_text->{$mode}->{$ARGV[4]}}) {
				print "$element:$json_text->{$mode}->{$ARGV[4]}->[$element]\n";
			}
		}
	}
	elsif ($ARGV[3] eq "index") {
		for my $element (0..$#{$json_text->{$mode}->{Chan}}) {
			print "$element\n";
		}
	}
	elsif ($ARGV[3] eq "num_indexes") {
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
  print "usage:\n\n./query_s33_stats.pl HOST password Up index\n" .
	"./query_s33_stats.pl HOST password Up num_indexes\n" .
	"./query_s33_stats.pl HOST password Up query (Chan,ChanId,Stat,Type,Freq,Width,Power)\n" .
	"./query_s33_stats.pl HOST password Up get (Chan,ChanId,Stat,Type,Freq,Width,Power) INDEX\n\n" .
	"./query_s33_stats.pl HOST password Down index\n" .
	"./query_s33_stats.pl HOST password Down num_indexes\n" .
	"./query_s33_stats.pl HOST password Down query (Chan,ChanId,Stat,Type,Freq,Power,SNR,CorrCw,UncorrCW)\n" .
	"./query_s33_stats.pl HOST password Down get (Chan,ChanId,Stat,Type,Freq,Power,SNR,CorrCw,UncorrCW) INDEX\n\n";
  exit;
}

# Generate the hmac keys
sub generate_keys {
	my ($challenge, $pubkey, $password) = @_;
	# compute the private key
	my $data = encode_utf8($challenge);
	my $key = encode_utf8($pubkey . $password);
	my $ucprivatekey;
	my $ucpasskey;
	if ($device_type eq "S33"){
		my $hmac = Digest::HMAC_MD5->new($key);
		$hmac->add($data);
		$ucprivatekey = uc($hmac->hexdigest);
		# compute the passkey
		my $passhmac = Digest::HMAC_MD5->new(encode_utf8($ucprivatekey));
		$passhmac->add($data);
		$ucpasskey = uc($passhmac->hexdigest);
	} else {
		$ucprivatekey = uc(hmac_sha256_hex($data, $key));
		$ucpasskey = uc(hmac_sha256_hex($data,$ucprivatekey));
	}

	return $ucprivatekey, $ucpasskey;
}

# Generate the HNAP auth value
sub generate_hnap_auth {
	my ($privatekey, $operation) = @_;
	my $curtime = int(Time::HiRes::time * 1000);
	my $auth_key = $curtime . '"' . "http://purenetworks.com/HNAP1/$operation" . '"';
        my $enprivkey = encode_utf8($privatekey);
	if ($device_type eq "S33"){
		my $hmac = Digest::HMAC_MD5->new($enprivkey);
		$hmac->add(encode_utf8($auth_key));
		return uc($hmac->hexdigest) . ' ' . $curtime;
	} else {
		return uc(hmac_sha256_hex(encode_utf8($auth_key),$enprivkey) . ' ' . $curtime);
	}
}

# Authenticate again
sub auth_stage1 {
	my ($url) = @_;
	# For some reason this seems to fail, so we need to attempt a few times
	my $header = ['SOAPAction' => '"http://purenetworks.com/HNAP1/Login"'];
	my $encoded_data = '{"Login":{"Action":"request","Username":"admin","LoginPassword":"","Captcha":"","PrivateLogin":"LoginPassword"}}'; 
	my $request = HTTP::Request->new('POST', $url, $header, $encoded_data);
	#print(Dumper($request));
	my $ua = LWP::UserAgent->new(ssl_opts => { SSL_verify_mode => SSL_VERIFY_NONE });
	my $response = $ua->request($request);
	# Should do some error checking
	if ($response->code == 200) {
		my $content = $response->content();
		#print "stage1: I received the following content: $content\n";
		# Simple validation prior to parsing
		if ($content eq "") {
			print "$host API returned null, not valid JSON!\n";
			exit 0;
		}
		my $stage1_json = new JSON;
		# these are some nice json options to relax restrictions a bit:
		my $stage1_json_text = $stage1_json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($content);
		if ($stage1_json_text->{"LoginResponse"}->{"LoginResult"} eq "OK") { 
			my $stage1_reply = {
				'Challenge' => $stage1_json_text->{"LoginResponse"}->{"Challenge"},
				'Cookie' => $stage1_json_text->{"LoginResponse"}->{"Cookie"},
				'PublicKey' => $stage1_json_text->{"LoginResponse"}->{"PublicKey"}
			};
			return $stage1_reply;
		} else {
			die("Abnormal response during authentication (stage1 LoginResult not OK)!");
		}
	} else {
		# If we reach this point we have failed to log in for times and need to abort
		#print "stage1: I received the following content: " . $response->content() . "\n";
		die("Abnormal response during authentication (stage1)!");
        }
}

# Second authentication stage
sub auth_stage2 {
	my ($url, $privkey, $passkey, $cookie) = @_;
	my $auth = generate_hnap_auth($privkey, 'Login');
	my $header = [
		'HNAP_AUTH' => $auth,
		'SOAPAction' => '"http://purenetworks.com/HNAP1/Login"'
	];
        my $encoded_data = '{"Login":{"Action":"login","Username":"admin","LoginPassword":"' . $passkey . '","Captcha":"","PrivateLogin":"LoginPassword"}}';
	my $cookie_jar = HTTP::Cookies->new();
        my $request = HTTP::Request->new('POST', $url, $header, $encoded_data);
	my $ua = LWP::UserAgent->new(ssl_opts => { SSL_verify_mode => SSL_VERIFY_NONE });
	$ua->cookie_jar($cookie_jar);
	$ua->cookie_jar->set_cookie(0, "uid", $cookie, "/", $host, 443 , 0, 1, 365 * 86400, 0);
	$ua->cookie_jar->set_cookie(0, "PrivateKey", $privkey, "/", $host, 443 , 0, 1, 365 * 86400, 0);
	#print "stage2: sending: $encoded_data\n";
	my $response = $ua->request($request);
	if ($response->code == 200) {
		my $content = $response->content();
		#print "stage2: I received the following content: $content\n";
		# Simple validation prior to parsing
		if ($content eq "") {
			print "$host API returned null, not valid JSON!\n";
			exit 0;
		}
		my $stage2_json = new JSON;
		# these are some nice json options to relax restrictions a bit:
		my $stage2_json_text = $stage2_json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($content);
		if ($stage2_json_text->{"LoginResponse"}->{"LoginResult"} eq "OK") { 
			return;
		} else {
			die("Abnormal response during authentication (stage2 LoginResult not OK)!");
		}
	} else {
		# If we reach this point we have failed to log in for times and need to abort
		die("Abnormal response during authentication (stage2)!");
        }
}


# Get the API JSON
sub fetch_json { 
	my ($url) = @_;
        my $stage1_reply = auth_stage1($url);
	my ($privkey, $passkey) = generate_keys(encode_utf8($stage1_reply->{"Challenge"}), encode_utf8($stage1_reply->{"PublicKey"}), encode_utf8($passwd));
	auth_stage2($url, $privkey, $passkey, $stage1_reply->{"Cookie"});
	my $auth = generate_hnap_auth($privkey, 'GetMultipleHNAPs');
	my $header = [
		'HNAP_AUTH' => $auth,
		'SOAPAction' => '"http://purenetworks.com/HNAP1/GetMultipleHNAPs"'
	];
	my $encoded_data = '{"GetMultipleHNAPs":{"GetCustomerStatusDownstreamChannelInfo":"","GetCustomerStatusUpstreamChannelInfo":""}}';
	my $cookie_jar = HTTP::Cookies->new();
	#print "POSTing request: $encoded_data using auth: $auth, cookie: uid:" . $stage1_reply->{"Cookie"} . ", PrivateKey: $privkey\n";
        my $request = HTTP::Request->new('POST', $url, $header, $encoded_data);
	my $ua = LWP::UserAgent->new(ssl_opts => { SSL_verify_mode => SSL_VERIFY_NONE });
	$ua->cookie_jar($cookie_jar);
	$ua->cookie_jar->set_cookie(0, "uid", $stage1_reply->{"Cookie"}, "/", $host, 443 , 0, 1, 365 * 86400, 0);
	$ua->cookie_jar->set_cookie(0, "PrivateKey", $privkey, "/", $host, 443 , 0, 1, 365 * 86400, 0);
	my $response = $ua->request($request);
	if ($response->code == 200) {
		my $content = $response->content();
		#print "I received the following content: $content\n";
		# Simple validation prior to parsing
		if ($content eq "") {
			print "$host API returned null, not valid JSON!\n";
			#print "response: " . Dumper($response) . "\n";
			exit 0;
		}
		my $data_json = new JSON;
		# these are some nice json options to relax restrictions a bit:
		my $data_json_text = $data_json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($content);
		if ($data_json_text->{"GetMultipleHNAPsResponse"}->{"GetMultipleHNAPsResult"} eq "OK") { 
			# Rasponse is good, now parse out the data
			my %data;
			my $downstream_rawtext = $data_json_text->{"GetMultipleHNAPsResponse"}->{"GetCustomerStatusDownstreamChannelInfoResponse"}->{"CustomerConnDownstreamChannel"};
			# Raw downstream (S33):
			# 1^Locked^QAM256^32^579000000^1^39^1919^397^|+|2^Locked^QAM256^17^483000000^2^39^19927^1627^|+|3^Locked^QAM256^18^489000000^2^39^18083^1810^|+|4^Locked^QAM256^19^495000000^2^39^36022^2464^|+|5^Locked^QAM256^20^507000000^2^39^10258^1415^|+|6^Locked^QAM256^21^513000000^2^39^11269^1268^|+|7^Locked^QAM256^22^519000000^2^39^21845^4348^|+|8^Locked^QAM256^23^525000000^2^39^28241^7566^|+|9^Locked^QAM256^24^531000000^2^39^21749^3438^|+|10^Locked^QAM256^25^537000000^2^39^9444^964^|+|11^Locked^QAM256^26^543000000^1^39^4744^759^|+|12^Locked^QAM256^27^549000000^2^39^2837^571^|+|13^Locked^QAM256^28^555000000^2^39^2310^573^|+|14^Locked^QAM256^29^561000000^2^39^1923^538^|+|15^Locked^QAM256^30^567000000^2^39^1782^429^|+|16^Locked^QAM256^31^573000000^1^39^1731^479^|+|17^Locked^QAM256^33^585000000^1^39^1301^315^|+|18^Locked^QAM256^34^591000000^1^39^1492^358^|+|19^Locked^QAM256^35^597000000^1^39^2662^295^|+|20^Locked^QAM256^36^603000000^1^39^6598^385^|+|21^Locked^QAM256^37^609000000^1^39^7749^527^|+|22^Locked^QAM256^38^615000000^1^39^4560^307^|+|23^Locked^QAM256^39^621000000^1^39^1613^217^|+|24^Locked^QAM256^40^627000000^1^39^1312^216^|+|25^Locked^QAM256^41^633000000^1^39^1287^204^|+|26^Locked^QAM256^42^639000000^1^39^1293^178^|+|27^Locked^QAM256^43^645000000^0^39^1549^169^|+|28^Locked^QAM256^44^651000000^0^39^1461^256^|+|29^Locked^QAM256^45^681000000^0^38^6730^434^|+|30^Locked^QAM256^46^687000000^0^38^10390^825^|+|31^Locked^QAM256^47^693000000^0^38^8745^654^|+|32^Locked^OFDM PLC^48^850000000^-4^37^1252372638^10793^
			# Raw downstream (S34):
			# 1^Locked^256QAM^20^495000000^ 4.2^43.4^1522^111^|+|2^Locked^256QAM^28^543000000^ 2.9^40.9^288^11^|+|3^Locked^256QAM^36^591000000^ 1.7^40.4^120^0^|+|4^Locked^256QAM^44^639000000^ 1.4^40.4^147^0^|+|5^Locked^256QAM^13^453000000^ 4.8^43.4^2141^232^|+|6^Locked^256QAM^14^459000000^ 4.8^40.9^2041^260^|+|7^Locked^256QAM^15^465000000^ 4.8^43.4^2238^193^|+|8^Locked^256QAM^16^471000000^ 4.8^40.9^1921^197^|+|9^Locked^256QAM^17^477000000^ 4.7^40.9^1708^147^|+|10^Locked^256QAM^18^483000000^ 4.6^40.9^1565^146^|+|11^Locked^256QAM^19^489000000^ 4.4^43.4^1107^100^|+|12^Locked^256QAM^21^501000000^ 4.0^40.4^1192^109^|+|13^Locked^256QAM^22^507000000^ 3.7^40.4^939^72^|+|14^Locked^256QAM^23^513000000^ 3.7^40.4^710^47^|+|15^Locked^256QAM^24^519000000^ 3.5^40.4^575^60^|+|16^Locked^256QAM^25^525000000^ 3.5^40.9^487^24^|+|17^Locked^256QAM^26^531000000^ 3.4^40.9^416^19^|+|18^Locked^256QAM^27^537000000^ 3.2^40.4^393^9^|+|19^Locked^256QAM^29^549000000^ 2.9^40.9^298^1^|+|20^Locked^256QAM^30^555000000^ 2.8^40.9^212^1^|+|21^Locked^256QAM^31^561000000^ 2.8^40.4^161^0^|+|22^Locked^256QAM^32^567000000^ 2.6^40.9^185^0^|+|23^Locked^256QAM^33^573000000^ 2.4^40.9^140^0^|+|24^Locked^256QAM^34^579000000^ 2.5^40.9^148^0^|+|25^Locked^256QAM^35^585000000^ 2.2^40.9^163^0^|+|26^Locked^256QAM^37^597000000^ 2.0^40.4^105^0^|+|27^Locked^256QAM^38^603000000^ 2.7^40.9^139^0^|+|28^Locked^256QAM^39^609000000^ 2.4^40.4^145^0^|+|29^Locked^256QAM^40^615000000^ 2.0^40.4^108^0^|+|30^Locked^256QAM^41^621000000^ 2.0^40.4^233^873^|+|31^Locked^256QAM^42^627000000^ 1.8^40.4^178^0^|+|32^Locked^256QAM^43^633000000^ 1.6^40.4^150^0^|+|33^Locked^OFDM PLC^193^722000000^-0.7^41.0^766131341^544^|+|34^Locked^OFDM PLC^194^957000000^-2.1^39.0^626951446^11^
			my @sdownstream = split(/\|\+\|/, $downstream_rawtext);
			foreach my $dsline (@sdownstream) {
				#print "Downstream line=$dsline\n";
				$dsline =~ /(\d*)\^(\w+)\^(\w+\s+\w+|\w+)\^(\d*)\^(\d*)\^ ?([-]?[0-9]*\.?[0-9]+)\^([0-9]*\.?[0-9]+)\^(\d*)\^(\d*)\^/g;
				#print("Index=$1, Stat=$2, Type=$3, Chan=$4, Freq=$5, Power=$6, SNR=$7, CorrCw=$8, UncorrCw=$9\n");
				push @{$data{Down}{ChanId}}, $1;
				push @{$data{Down}{Stat}}, $2;
				push @{$data{Down}{Type}}, $3;
				push @{$data{Down}{Chan}}, $4;
				push @{$data{Down}{Freq}}, $5;
				push @{$data{Down}{Power}}, $6;
				push @{$data{Down}{SNR}}, $7;
				push @{$data{Down}{CorrCw}}, $8;
				push @{$data{Down}{UncorrCw}}, $9;
			}

			my $upstream_rawtext = $data_json_text->{"GetMultipleHNAPsResponse"}->{"GetCustomerStatusUpstreamChannelInfoResponse"}->{"CustomerConnUpstreamChannel"};
			# Raw upstream:
			# 1^Locked^SC-QAM^1^3200000^10400000^51.5^|+|2^Locked^SC-QAM^2^6400000^16400000^52.3^|+|3^Locked^SC-QAM^3^6400000^22800000^52.5^|+|4^Locked^SC-QAM^4^6400000^29200000^52.3^|+|5^Locked^SC-QAM^5^6400000^35600000^52.0^|+|6^Locked^SC-QAM^6^3200000^40400000^52.0^
			my @supstream = split(/\|\+\|/, $upstream_rawtext);
			foreach my $usline (@supstream) {
				$usline =~ /(\d*)\^(\w+)\^([a-zA-Z0-9-\s]+)\^(\d*)\^(\d*)\^(\d*)\^([0-9]*\.?[0-9]+)\^/g;
				#print("ChanId=$1, Stat=$2, Type=$3, Chan=$4, Width=$5, Freq=$6, Power=$7\n");
				push @{$data{Up}{ChanId}}, $1;
				push @{$data{Up}{Stat}}, $2;
				push @{$data{Up}{Type}}, $3;
				push @{$data{Up}{Chan}}, $4;
				push @{$data{Up}{Width}}, $5;
				push @{$data{Up}{Freq}}, $6;
				push @{$data{Up}{Power}}, $7 * 10;
			}
			to_json(\%data);
		} else {
			die("Abnormal response when fetching data (GetMultipleHNAPsResult not OK)!");
		}
	} else {
		# If we reach this point we have failed to log in for times and need to abort
		die("Abnormal response when fetching data!");
        }
}
