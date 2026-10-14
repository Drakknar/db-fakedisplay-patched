#!/usr/bin/env perl
# Let POST /_geolocation search stops by name: with q=<name> instead of
# lat/lon it returns the DB (IRIS) stations and the HAFAS stops (BVG by
# default, or ?hafas=X) matching that name, in the same JSON format as the
# coordinate search, including lat/lon. The Home Assistant spdbf_nearby
# integration uses it for its stop search. Upstream only offers name matches
# as an HTML list, with DS100 codes instead of EVA numbers for DB.
#
# It reuses the /_geolocation route so the patch stays within
# Stationboard.pm, like the other patches.
#
# Usage: perl station-name-search.pl path/to/Stationboard.pm
#
# Exits non-zero when the code it expects is gone, so the image build fails
# loudly instead of shipping a half-patched image.

use strict;
use warnings;

my $file = shift or die "usage: $0 Stationboard.pm\n";

open( my $in, '<', $file ) or die "open $file: $!\n";
my $src = do { local $/; <$in> };
close($in);

# Only this patch's own marker counts as "already applied". Upstream code
# that merely looks similar must stop the build instead: a second
# stations_by_name would only be a "redefined" warning, and a q parameter of
# upstream's own could mean something else.
if ( $src =~ m{Patched \(station-name-search\.pl\)} ) {
	print "name search already present, nothing to do\n";
	exit 0;
}
die "upstream now defines stations_by_name: check whether it does the same"
  . " as this patch, then drop or rename the patch\n"
  if $src =~ m{sub \s+ stations_by_name \b}x;
die "upstream now reads a q parameter: check whether it is a name search"
  . " like this patch, then drop or adapt the patch\n"
  if $src =~ m{param\( \s* ['"]q['"] \s* \)}x;

# Turn a code snippet into a pattern that ignores differences in whitespace.
sub loose {
	my ($code) = @_;
	my $re = join( '\s*', map { quotemeta } grep { length } split( /\s+/, $code ) );
	return qr{$re};
}

sub replace {
	my ( $what, $old, $new ) = @_;
	my $re    = loose($old);
	my $count = () = $src =~ m{$re}g;
	die "patch did not apply ($what: $count matches, expected 1):"
	  . " upstream code changed\n"
	  if $count != 1;
	$src =~ s{$re}{$new};
}

# 1. stations_by_coordinates hands q=<name> to stations_by_name, before it
#    insists on lat/lon.
replace( 'q parameter', <<'OLD', <<'NEW' );
	my $hafas       = $self->param('hafas');

	if ( not $lon or not $lat ) {
OLD
	my $hafas       = $self->param('hafas');

	# Patched (station-name-search.pl): search by name instead.
	if ( defined $self->param('q') ) {
		$self->stations_by_name( $self->param('q'), $hafas );
		return;
	}

	if ( not $lon or not $lat ) {
NEW

# 2. The name search itself.
replace( 'name search', <<'OLD', <<'NEW' );
sub stations_by_coordinates {
OLD
# Patched (station-name-search.pl): stops matching a name, in the format of
# stations_by_coordinates (without distance): DB (IRIS) stations first, then
# the matches of one HAFAS service.
sub stations_by_name {
	my ( $self, $query, $hafas ) = @_;

	$query =~ s{ ^ \s+ | \s+ $ }{}gx;
	if ( length($query) < 2 ) {
		$self->render( json => { candidates => [] } );
		return;
	}

	my $service = $ENV{DBFAKEDISPLAY_DEFAULT_HAFAS} || 'BVG';
	if (    $hafas
		and $hafas ne '1'
		and Travel::Status::DE::HAFAS::get_service($hafas) )
	{
		$service = $hafas;
	}

	my @iris = map {
		{
			ds100 => $_->[0],
			name  => $_->[1],
			eva   => $_->[2],
			lon   => $_->[3],
			lat   => $_->[4],
			hafas => 0,
		}
	} Travel::Status::DE::IRIS::Stations::get_station($query);
	splice( @iris, 10 ) if @iris > 10;

	$self->render_later;
	my $warning;
	Travel::Status::DE::HAFAS->new_p(
		locationSearch => $query,
		service        => $service,
		promise        => 'Mojo::Promise',
		user_agent     => $service eq 'PKP' ? Mojo::UserAgent->new : $self->ua,
	)->then(
		sub {
			my ($status) = @_;
			return [
				map {
					{
						name => $_->name =~ s{[&]#x0028;}{(}gr
						  =~ s{[&]#x0029;}{)}gr,
						eva   => $_->eva,
						lat   => $_->lat,
						lon   => $_->lon,
						hafas => $service,
					}
				} $status->results
			];
		}
	)->catch(
		sub {
			my ($err) = @_;
			# HAFAS reports "no match" as a LOCATION error.
			$warning = "$err" if "$err" !~ m{LOCATION};
			return [];
		}
	)->then(
		sub {
			my ($found) = @_;
			$self->render(
				json => {
					candidates => [ @iris, @{$found} ],
					( $warning ? ( warning => $warning ) : () ),
				}
			);
		}
	)->wait;
}

sub stations_by_coordinates {
NEW

open( my $out, '>', $file ) or die "write $file: $!\n";
print {$out} $src;
close($out);

print "added name search to /_geolocation (q=<name>)\n";
