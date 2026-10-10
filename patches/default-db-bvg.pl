#!/usr/bin/env perl
# Make the web frontend look at DB and BVG by default:
#
#  * The generic HAFAS fallback (upstream: ÖBB) becomes BVG, so "Stationen in
#    der Umgebung" lists DB (IRIS) and BVG stops, and hafas=1 means BVG.
#  * A station name that is not a DB (IRIS) station is searched in BVG instead
#    of ending in "not found", so bus/tram/U-Bahn stops work from the
#    front page too.
#
# Set DBFAKEDISPLAY_DEFAULT_HAFAS in the container to use another HAFAS
# service instead of BVG.
#
# Usage: perl default-db-bvg.pl path/to/Stationboard.pm
#
# Exits non-zero when the code it expects is gone, so the image build fails
# loudly instead of shipping a half-patched image.

use strict;
use warnings;

my $file = shift or die "usage: $0 Stationboard.pm\n";

open( my $in, '<', $file ) or die "open $file: $!\n";
my $src = do { local $/; <$in> };
close($in);

if ( $src =~ m{DBFAKEDISPLAY_DEFAULT_HAFAS} ) {
	print "DB+BVG defaults already present, nothing to do\n";
	exit 0;
}

my $default = q{$ENV{DBFAKEDISPLAY_DEFAULT_HAFAS} || 'BVG'};

# 1. Generic HAFAS fallback: handle_no_results, get_results_p,
#    stations_by_coordinates.
my $count = $src =~ s{my \$service = 'ÖBB';}{my \$service = $default;}g;
die "patch did not apply ($count generic HAFAS defaults, expected 3): upstream code changed\n"
  if $count != 3;

# 2. IRIS station not found: search the default HAFAS service instead.
$count = $src =~ s{
	(\n \t if \s \( \$data->\{station_ds100\} \s and \s \$data->\{station_ds100\} \s =~ \s m\{ \s \^ \s \[OPQXYZ\] \s \}x \s \) \n
	 \t \{ \n .*? \n \t\t return; \n \t \} \n)
}{$1\tif ( not \@candidates ) {
		my \$params = \$self->req->params->clone;
		\$params->param( hafas => $default );
		\$self->redirect_to( "/\${station}?" . \$params->to_string );
		return;
	}
}xs;
die "patch did not apply ($count IRIS fallbacks, expected 1): upstream code changed\n"
  if $count != 1;

open( my $out, '>', $file ) or die "write $file: $!\n";
print {$out} $src;
close($out);

print "frontend now defaults to DB + BVG\n";
