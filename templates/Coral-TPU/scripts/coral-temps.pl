#!/usr/bin/perl -w
#
# Read the temps for all attached PCIe Coral TPUs
#
my @files = glob( '/sys/class/apex/apex_*' );

foreach $apex (@files) {
   open my $file, '<', $apex . "/temp";
   my $firstLine = <$file>;
   close $file;
   print $firstLine;
}

