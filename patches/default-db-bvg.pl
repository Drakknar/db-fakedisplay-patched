#!/usr/bin/env perl
# Make every search in the web frontend include DB and BVG by default:
#
#  * Typed station names show one list with DB (IRIS) and BVG matches,
#    labelled "(DB)" and "(BVG)". A single match opens its board directly.
#  * The generic HAFAS fallback (upstream: ÖBB) becomes BVG, so "Stationen in
#    der Umgebung" lists DB and BVG stops, and hafas=1 means BVG.
#
# Train numbers, an explicitly chosen backend (?hafas=X / ?efa=X) and direct
# board URLs such as /8011160 behave as upstream.
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

# Turn a code snippet into a pattern that ignores differences in whitespace.
sub loose {
	my ($code) = @_;
	my $re = join( '\s*', map { quotemeta } grep { length } split( /\s+/, $code ) );
	return qr{$re};
}

sub replace {
	my ( $what, $expected, $old, $new ) = @_;
	my $re    = loose($old);
	my $count = () = $src =~ m{$re}g;
	die "patch did not apply ($what: $count matches, expected $expected):"
	  . " upstream code changed\n"
	  if $count != $expected;
	$src =~ s{$re}{$new}g;
}

# 1. Generic HAFAS fallback in handle_no_results, get_results_p and
#    stations_by_coordinates.
replace(
	'generic HAFAS default', 3,
	q{my $service = 'ÖBB';},
	q{my $service = $ENV{DBFAKEDISPLAY_DEFAULT_HAFAS} || 'BVG';},
);

# 2. Frontend search form (redirect_to_station, no backend chosen).
replace( 'frontend search', 1, <<'OLD', <<'NEW' );
	else {
		$params->remove('efa');
		my @candidates
		  = Travel::Status::DE::IRIS::Stations::get_station($input);
		if (
			@candidates == 1
			and (  $input eq $candidates[0][0]
				or lc($input) eq lc( $candidates[0][1] )
				or $input eq $candidates[0][2] )
		  )
		{
			$params->remove('hafas');
		}
		else {
			$params->param( hafas => 1 );
		}
		$params = $params->to_string;
		$self->redirect_to("/${input}?${params}");
	}
OLD
	else {
		# Patched (default-db-bvg.pl): search DB and the default HAFAS
		# service together.
		$params->remove('efa');
		my $service = $ENV{DBFAKEDISPLAY_DEFAULT_HAFAS} || 'BVG';
		my @candidates
		  = Travel::Status::DE::IRIS::Stations::get_station($input);
		if (
			@candidates == 1
			and (  $input eq $candidates[0][0]
				or $input eq $candidates[0][2] )
		  )
		{
			# DS100 or EVA, e.g. a DB entry picked from the list below
			$params->remove('hafas');
			$params = $params->to_string;
			$self->redirect_to("/${input}?${params}");
			return;
		}
		if ( $input =~ m{ ^ [0-9]+ $ }x ) {
			# Stop ID of the default HAFAS service picked from the list below
			$params->param( hafas => $service );
			$params = $params->to_string;
			$self->redirect_to("/${input}?${params}");
			return;
		}
		my @db = map { [ "$_->[1] (DB)", $_->[2] ] } @candidates;
		$self->render_later;
		Travel::Status::DE::HAFAS->new_p(
			locationSearch => $input,
			service        => $service,
			promise        => 'Mojo::Promise',
			user_agent     => $self->ua,
		)->then(
			sub {
				my ($status) = @_;
				return [ map { [ $_->name . " ($service)", $_->eva ] }
					  $status->results ];
			}
		)->catch(
			sub {
				my ($err) = @_;
				$self->app->log->warn(
					"$service locationSearch for '$input' failed: $err");
				return [];
			}
		)->then(
			sub {
				my ($hafas) = @_;
				my @all = ( @db, @{$hafas} );
				for my $candidate (@all) {
					$candidate->[0] =~ s{[&]#x0028;}{(}g;
					$candidate->[0] =~ s{[&]#x0029;}{)}g;
				}
				if ( @all == 1 ) {
					$params->param( input => $all[0][1] );
					$self->redirect_to( '/_redirect?' . $params->to_string );
				}
				elsif (@all) {
					$self->render(
						'landingpage',
						stationlist => \@all,
						hide_opts   => 0,
						status      => 300,
					);
				}
				else {
					$self->render(
						'landingpage',
						error     => "Keine Station '$input' gefunden (DB, $service)",
						hide_opts => 0,
						status    => 404,
					);
				}
			}
		)->wait;
	}
NEW

open( my $out, '>', $file ) or die "write $file: $!\n";
print {$out} $src;
close($out);

print "frontend searches now include DB + BVG\n";
