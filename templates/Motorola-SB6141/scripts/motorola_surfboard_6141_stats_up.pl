#!/usr/bin/perl -w

# motorola_surfboard_6141_stats.pl
# 
# Extracts statistics from the Motorola Surfboard SB6141 DOCSIS cable modem for use by Cacti.
# Modified version of the script found here: http://nerhood.wordpress.com/2006/06/28/graphing-motorola-surfboard-sb5101-cable-modem-stats-with-cacti/
#
######################
## Revision History ##
######################
# v0.01 6/12/2014 Brian Rudy (brudyNO@SPAMpraecogito.com)
#       First working version. Only supports white version of the SB6141 with 8 down and 4 up channels in use.
#



use warnings;
use strict;
use LWP::Simple;
#

my %data;

my $host = $ARGV[0];

unless (defined $host) {
  # Missing input params
  print "usage:\n\n./motorola_surfboard_6141_stats.pl HOST\n";
  exit 0;
}



my $content = LWP::Simple::get("http://$host/cmSignalData.htm") or die "Couldn’t get it!";
$content =~ s/\\n//g; # Strip all the linefeeds
#print $content;

## regex in html source order
if ($content =~ /<TR><TD>Channel ID<\/TD>\s*<TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><\/TR>/) {
	$data{Up}{Chan}[0] = $1;
	$data{Up}{Chan}[1] = $2;
	$data{Up}{Chan}[2] = $3;
	$data{Up}{Chan}[3] = $4;
}

if ($content =~ /<TR><TD>Symbol Rate<\/TD>\s*<TD>(.*)\s*Msym\/sec&nbsp\;<\/TD><TD>(.*)\s*Msym\/sec&nbsp\;<\/TD><TD>(.*)\s*Msym\/sec&nbsp\;<\/TD><TD>(.*)\s*Msym\/sec&nbsp\;<\/TD><\/TR>/) {
	$data{Up}{SymbolRate}[0] = $1 * 1000000;
	$data{Up}{SymbolRate}[1] = $2 * 1000000;
	$data{Up}{SymbolRate}[2] = $3 * 1000000;
	$data{Up}{SymbolRate}[3] = $4 * 1000000;
}

if ($content =~ /<TR><TD>Power Level<\/TD>\s*<TD>(\d*)\s*dBmV&nbsp\;<\/TD><TD>(\d*)\s*dBmV&nbsp\;<\/TD><TD>(\d*)\s*dBmV&nbsp\;<\/TD><TD>(\d*)\s*dBmV&nbsp\;<\/TD><\/TR>/) {
	$data{Up}{Power}[0] = $1;
	$data{Up}{Power}[1] = $2;
	$data{Up}{Power}[2] = $3;
	$data{Up}{Power}[3] = $4;
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
print join(' ', @outstrings) . "\n";

