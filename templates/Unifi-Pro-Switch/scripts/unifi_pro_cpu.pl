#!/usr/bin/perl -w
#

# unifi_pro_cpu.pl

# Simple script to grab the CPU stats from Unifi Pro switches
# This is needed fo rolder versions of cacti that have broken value regex parsing for indexed SNMP queries
#
# Invoke with unifi_pro_cpu.pl <hostname> <snmp_community> <snmp_version> <snmp_port> <snmp_timeout>
# e.g. unifi_pro_cpu.pl 192.168.1.1 public 2 161 30 

# Revision history
# v0.01 5/23/2020 Brian Rudy (brudyNO@SPAMpraecogito.com)
# 	Initial version
# v0.02 2/16/2025 Brian Rudy (brudyNO@SPAMpraecogito.com)
# 	Improvements to regext to handle single digit numbers

# 
use strict;
use SNMP;

my $status;
my $answer = "";
my $snmpkey=0;
my $snmpoid=0;
my $key=0;
my $community = "public";
my $port = 161;
my @snmpoids;
my $hostname;
my $session;
my $error;
my $response;
my %ddwrtstatus;
my $snmp_version = 2;
my $cpu_stats;


my $vars = new SNMP::VarList(['.1.3.6.1.4.1.4413.1.1.1.1.4.9']);

# Just in case of problems, let's not hang poller
$SIG{'ALRM'} = sub {
     die ("ERROR: No snmp response from $hostname (alarm timeout)\n");
};
alarm($ARGV[4]);

$session = new SNMP::Session(
		DestHost    => $ARGV[0],
		Community   => $ARGV[1],
		RemotePort  => $ARGV[3],
		Version     => $ARGV[2],
		Timeout     => $ARGV[4] * 1000
			);

if ($session->{ErrorNum}) {
	$answer=$session->{ErrorStr};
	die ("$answer");
}

my @resp = $session->bulkwalk(0, 35, $vars);


if ($session->{ErrorNum}) {
        $answer=$session->{ErrorStr};
        die ("$answer with snmp version $snmp_version\n");
}

for my $vbarr ( @resp ) {
        for my $v (@$vbarr) {
		$cpu_stats = $v->val;
        }
}

my ($fiveSec,$sixtySec,$threehundredSec) = $cpu_stats  =~ /.*5\sSecs\s\(\s+([0-9]*\.?[0-9]+)\%\)\s+60\sSecs\s\(\s+([0-9]*\.?[0-9]+)\%\)\s+300\sSecs\s\(\s+([0-9]*\.?[0-9]+)\%/g;
#unless ((defined $fiveSec) && (defined $sixtySec) && (defined $threehundredSec)) {
#	print "Failed to parse response: \'$cpu_stats\'\n";
#} else {
#	print "Normal parsed response: \'$cpu_stats\'\n"; 
#}
print "fiveSec:$fiveSec sixtySec:$sixtySec threehundredSec:$threehundredSec";

