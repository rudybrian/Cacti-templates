#!/usr/bin/perl -w

# arris_sb8200_stats_down.pl
# 
# Extracts statistics from the Arris Surfboard SB8200 DOCSIS cable modem for use by Cacti.
#
######################
## Revision History ##
######################
# v0.01 3/5/2018 Brian Rudy (brudyNO@SPAMpraecogito.com)
#       First working version. Supports up to 32 down and 8 up channels
#



use warnings;
use strict;
use LWP::Simple;
#

my %data;

my $host = $ARGV[0];

unless (defined $host) {
  # Missing input params
  print "usage:\n\n./arris_sb8200_stats_down.pl HOST\n";
  exit 0;
}



my $content = LWP::Simple::get("http://$host/cmconnectionstatus.html") or die "Couldn’t get it!";
$content =~ tr/\r\n//d; # Strip all the linefeeds
#print $content;


while ($content =~ /<tr>\s*<td>(\d*)<\/td>\s*<td>(\w+)<\/td>\s*<td>(QAM\d+|Other)<\/td>\s*<td>(\d*)\s*Hz<\/td>\s*<td>([-]?[0-9]*\.?[0-9]+)\s*dBmV<\/td>\s*<td>([0-9]*\.?[0-9]+)\s*dB<\/td>\s*<td>(\d*)<\/td>\s*<td>(\d*)<\/td>\s*<\/tr>/g) {
	#print "channel:$1\n";
	push @{$data{Dwn}{Chan}}, $1;
	#print "status:$2\n";
	push @{$data{Dwn}{Stat}}, $2;
	#print "type:$3\n";
	push @{$data{Dwn}{Type}}, $3;
	#print "frequency:$4\n";
	push @{$data{Dwn}{Freq}}, $4;
	#print "power:$5\n";
	push @{$data{Dwn}{Power}}, $5 * 10;
	#print "SNR:$6\n";
	push @{$data{Dwn}{SNR}}, $6 * 10;
	#print "corrected:$7\n";
	push @{$data{Dwn}{CorrCw}}, $7;
	#print "uncorrectable:$8\n\n";
	push @{$data{Dwn}{UncorrCw}}, $8;
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

