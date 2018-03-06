#!/usr/bin/perl -w

# arris_sb8200_stats_up.pl
# 
# Extracts statistics from the Arris Surfboard SB8200 DOCSIS cable modem for use by Cacti.
#
######################
## Revision History ##
######################
# v0.01 3/5/2018 Brian Rudy (brudyNO@SPAMpraecogito.com)
#       First working version. Supports firmware version D31CM-PEREGRINE-1.0.1.0-GA-04-NOSH
#



use warnings;
use strict;
use LWP::Simple;
#

my %data;

my $host = $ARGV[0];

unless (defined $host) {
  # Missing input params
  print "usage:\n\n./arris_sb8200_stats_up.pl HOST\n";
  exit 0;
}



my $content = LWP::Simple::get("http://$host/cmconnectionstatus.html") or die "Couldn’t get it!";
$content =~ tr/\r\n//d; # Strip all the linefeeds
#print $content;


while ($content =~ /<tr>\s*<td>(\d*)<\/td>\s*<td>(\d*)<\/td>\s*<td>(\w*)<\/td>\s*<td>([a-zA-Z0-9-]+)<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>([0-9]*\.?[0-9]+)\s*dBmV<\/td>\s*/g) {
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


# Collect all the settings
my @outstrings;
foreach my $key (keys %data) {
	foreach my $key2 (keys %{$data{$key}}) {
		for my $element (0..$#{$data{$key}{$key2}}) {
			push(@outstrings, ($key . "_" . $key2 . "_" . ($element + 1) . ":" . $data{$key}{$key2}[$element]));
		}
	}
}

# Print it all at once to keep spine happy
print join(' ', @outstrings);

