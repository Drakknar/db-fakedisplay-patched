#!/usr/bin/env perl
# Add lat/lon to HAFAS results of POST /_geolocation, so clients such as the
# Home Assistant spdbf_nearby integration can put HAFAS stops (BVG etc.) on a
# map. IRIS (DB) results already include them.
#
# Usage: perl hafas-geolocation-coordinates.pl path/to/Stationboard.pm
#
# Exits non-zero when the code it expects is gone, so the image build fails
# loudly instead of shipping an unpatched image.

use strict;
use warnings;

my $file = shift or die "usage: $0 Stationboard.pm\n";

open( my $in, '<', $file ) or die "open $file: $!\n";
my $src = do { local $/; <$in> };
close($in);

# Only lat in the HAFAS candidates of the coordinate search counts: any other
# "$_->lat" (station-name-search.pl adds one, upstream might elsewhere) would
# skip this patch while the coordinate search still lacks them.
if ($src =~ m{distance \s* => \s* \$_->distance_m \s* / \s* 1000, \s*
	hafas \s* => \s* \$service, \s* lat \s* => \s* \$_->lat\b}x
    )
{
    print "HAFAS coordinates already present, nothing to do\n";
    exit 0;
}

my $count = $src =~ s{
	(distance \s* => \s* \$_->distance_m \s* / \s* 1000, \n
	 (\s*) hafas \s* => \s* \$service, \n)
}{$1$2lat      => \$_->lat,\n$2lon      => \$_->lon,\n}x;

die "patch did not apply ("
    . ( $count || 0 )
    . " matches): upstream code changed\n"
    if $count != 1;

open( my $out, '>', $file ) or die "write $file: $!\n";
print {$out} $src;
close($out);

print "added lat/lon to HAFAS geolocation results\n";
