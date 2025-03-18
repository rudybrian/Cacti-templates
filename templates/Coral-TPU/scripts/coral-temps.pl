#!/usr/bin/perl -w
#
# Read the temps for all attached PCIe Coral TPUs
#
# possible arguments:
# temp
# trip_point0_temp
# trip_point1_temp
# trip_point2_temp
# temp_poll_interval
#

unless (defined $ARGV[0]) {
   print "Must supply parameter e.g. ./coral-temps.pl temp\n";
   exit;
}
my @files = glob( '/sys/class/apex/apex_*' );

foreach $apex (@files) {
   open my $file, '<', $apex . "/" . $ARGV[0];
   my $firstLine = <$file>;
   close $file;
   print $firstLine;
}

