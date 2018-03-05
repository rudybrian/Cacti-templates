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
if ($content =~ /<TR><TD>Channel ID<\/TD>\s*<TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><TD>(\d*)&nbsp\;\s*<\/TD><\/TR>/) {
	$data{Dwn}{Chan}[0] = $1; 
	$data{Dwn}{Chan}[1] = $2;
	$data{Dwn}{Chan}[2] = $3;
	$data{Dwn}{Chan}[3] = $4;
	$data{Dwn}{Chan}[4] = $5;
	$data{Dwn}{Chan}[5] = $6;
	$data{Dwn}{Chan}[6] = $7;
	$data{Dwn}{Chan}[7] = $8;
}
if ($content =~ /<TR><TD>Frequency<\/TD>\s*<TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><TD>(\d*)\s*Hz&nbsp\;<\/TD><\/TR>/) { 
	$data{Dwn}{Freq}[0] = $1;
	$data{Dwn}{Freq}[1] = $2;
	$data{Dwn}{Freq}[2] = $3;
	$data{Dwn}{Freq}[3] = $4;
	$data{Dwn}{Freq}[4] = $5;
	$data{Dwn}{Freq}[5] = $6;
	$data{Dwn}{Freq}[6] = $7;
	$data{Dwn}{Freq}[7] = $8;
}

if ($content =~ /<TR><TD>Signal to Noise Ratio<\/TD>\s*<TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><TD>(\d*)\s*dB&nbsp\;<\/TD><\/TR>/) {
	$data{Dwn}{SNR}[0] = $1; 
	$data{Dwn}{SNR}[1] = $2; 
	$data{Dwn}{SNR}[2] = $3; 
	$data{Dwn}{SNR}[3] = $4; 
	$data{Dwn}{SNR}[4] = $5; 
	$data{Dwn}{SNR}[5] = $6; 
	$data{Dwn}{SNR}[6] = $7; 
	$data{Dwn}{SNR}[7] = $8; 
}

if ($content =~ /<TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><TD>(\d*)\s*dBmV\s*&nbsp\;<\/TD><\/TR>\s*<\/TBODY><\/TABLE><\/CENTER>/) { 
	$data{Dwn}{Power}[0] = $1;
	$data{Dwn}{Power}[1] = $2;
	$data{Dwn}{Power}[2] = $3;
	$data{Dwn}{Power}[3] = $4;
	$data{Dwn}{Power}[4] = $5;
	$data{Dwn}{Power}[5] = $6;
	$data{Dwn}{Power}[6] = $7;
	$data{Dwn}{Power}[7] = $8;
}

if ($content =~ /<TR><TD>Total Unerrored Codewords<\/TD>\s*<TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><\/TR>/) {
	$data{Dwn}{UnerrCw}[0] = $1;
	$data{Dwn}{UnerrCw}[1] = $2;
	$data{Dwn}{UnerrCw}[2] = $3;
	$data{Dwn}{UnerrCw}[3] = $4;
	$data{Dwn}{UnerrCw}[4] = $5;
	$data{Dwn}{UnerrCw}[5] = $6;
	$data{Dwn}{UnerrCw}[6] = $7;
	$data{Dwn}{UnerrCw}[7] = $8;
}

if ($content =~ /<TR><TD>Total Correctable Codewords<\/TD>\s*<TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><\/TR>/) {
	$data{Dwn}{CorrCw}[0] = $1;
	$data{Dwn}{CorrCw}[1] = $2;
	$data{Dwn}{CorrCw}[2] = $3;
	$data{Dwn}{CorrCw}[3] = $4;
	$data{Dwn}{CorrCw}[4] = $5;
	$data{Dwn}{CorrCw}[5] = $6;
	$data{Dwn}{CorrCw}[6] = $7;
	$data{Dwn}{CorrCw}[7] = $8;
}

if ($content =~ /<TR><TD>Total Uncorrectable Codewords<\/TD>\s*<TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><TD>(\d*)&nbsp\;<\/TD><\/TR>/) {
	$data{Dwn}{UncorrCw}[0] = $1;
	$data{Dwn}{UncorrCw}[1] = $2;
	$data{Dwn}{UncorrCw}[2] = $3;
	$data{Dwn}{UncorrCw}[3] = $4;
	$data{Dwn}{UncorrCw}[4] = $5;
	$data{Dwn}{UncorrCw}[5] = $6;
	$data{Dwn}{UncorrCw}[6] = $7;
	$data{Dwn}{UncorrCw}[7] = $8;
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

