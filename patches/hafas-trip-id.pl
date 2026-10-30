#!/usr/bin/env perl
# Add tripId to HAFAS departures in the JSON board (?mode=json), so clients
# can open a trip's details: GET /z/<tripId>.json?hafas=<service>. Upstream
# already uses this id in its HTML board's trip links, but leaves it out of
# the JSON. The Home Assistant spdbf_nearby integration uses it for its trip
# view; DB (IRIS) trips are found by train name and number instead.
#
# Usage: perl hafas-trip-id.pl path/to/Stationboard.pm
#
# Exits non-zero when the code it expects is gone, so the image build fails
# loudly instead of shipping an unpatched image.

use strict;
use warnings;

my $file = shift or die "usage: $0 Stationboard.pm\n";

open( my $in, '<', $file ) or die "open $file: $!\n";
my $src = do { local $/; <$in> };
close($in);

# Only a tripId next to the HAFAS trainNumber counts: one elsewhere (say, in
# the IRIS branch) would skip this patch while HAFAS departures lack it.
if ( $src =~ m{trainNumber \s* => \s* \$result->number, \s* tripId \s* =>}x )
{
    print "HAFAS trip ids already present, nothing to do\n";
    exit 0;
}

# The HAFAS branch of the JSON departure list; IRIS departures have
# trainNumber => $result->train_no instead.
my $count = $src =~ s{
	(\n (\s*) trainNumber \s* => \s* \$result->number, \n)
}{$1$2tripId            => \$result->id,\n}x;

die "patch did not apply ("
    . ( $count || 0 )
    . " matches): upstream code changed\n"
    if $count != 1;

open( my $out, '>', $file ) or die "write $file: $!\n";
print {$out} $src;
close($out);

print "added tripId to HAFAS JSON departures\n";
