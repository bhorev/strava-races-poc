#!/usr/bin/env perl
use Data::Dumper;
use JSON;

my $year = "2019";
my $country = "United Kingdom";
my $SAVE_PATH = "<PUT_PATH>";
my $access_token = "<PUT_TOKEN>";

sub stravaGet {
	my $url = shift;
	my $cmd = "curl -X GET $url -H \"accept: application/json\" -H \"authorization: Bearer $access_token\"";
	my $res = `$cmd`;
	while ($res =~ m/Rate Limit Exceeded/) {
		sleep(5);
		print "Rate limit exceeded, retrying\n";
		$res = `$cmd`;
	}
	return $res;
}

# Get all races per year
sub getYearlyRaces {
	my $races = readYearlyRaces();
	if (defined $races) {
		return $races;
	}
	my $response = stravaGet("https://www.strava.com/api/v3/running_races?year=$year");
	saveYearlyRaces($response);
	return $response;
}

# Get all country races
sub getCountryRacesPerYear {
	my $countryRacesPerYear = readCountryRaces();
	if (defined $countryRacesPerYear) {
		return $countryRacesPerYear;
	}
	my $races = decode_json(getYearlyRaces());
	my @countryRaces = ();
	foreach $race ( @{$races}) {
		if ($race->{'country'} eq $country) {
			push (@countryRaces, $race);
		}
	}
	print "Found: " . scalar @countryRaces . " $country races in $year\n";
	$countryRacesPerYear = encode_json(\@countryRaces);
	saveCountryRaces($countryRacesPerYear);
	return $countryRacesPerYear;
}

# For each race, obtain race details
sub getRaceDetails {
	my $detailedRacesJson = readDetailedRaces();
	if (defined $detailedRacesJson) {
		return $detailedRacesJson;
	}
	my $countryRaces = decode_json(getCountryRacesPerYear());
	my @detailedRaces = ();
	foreach $race (@{$countryRaces}) {
		my $id = $race->{'id'};
		$response = stravaGet("https://www.strava.com/api/v3/running_races/$id");
		$race_details = decode_json($response);
		push(@detailedRaces, $race_details);
		#print (Dumper($race_details)."\n");
	}
	print "Processed: " . scalar @detailedRaces . " races\n";
	$detailedRacesJson = encode_json(\@detailedRaces);
	saveDetailedRaces($detailedRacesJson);
	return $detailedRacesJson;
}

# Find route_ids
sub getRoutesDetails {
	my $detailedRoutesJson = readDetailedRoutes();
	if (defined $detailedRoutesJson) {
		return $detailedRoutesJson;
	}	
	my $detailedRaces = decode_json(getRaceDetails());
	my @routes = ();
	foreach $race (@{$detailedRaces}) {
		# TODO: currently taking only one route per race, London Marathon has 6
		my $route = @{$race->{'route_ids'}}[0];
		my $response = stravaGet("https://www.strava.com/api/v3/routes/$route");
		my $route_details = decode_json($response);
		push(@routes, $route_details);
	}
	print "Processed: " . scalar @routes . " routes\n";
	$detailedRoutesJson = encode_json(\@routes);
	saveDetailedRoutes($detailedRoutesJson);
	return $detailedRoutesJson;
}

sub main() {
	my $data;

	my $routes = decode_json(getRoutesDetails());
	my $races = decode_json(getRaceDetails());
	
	foreach $race (@{$races}) {
		my $race_route = @{$race->{'route_ids'}}[0];
		foreach $route (@{$routes}) {
			if ($route->{'id'} eq $race_route) {
				$race->{'elevation_gain'} = $route->{'elevation_gain'};
			}
		}
		my ($date, $time) = ($race->{'start_date_local'} =~ m/(.+)T(.+)Z/);
		my $date = 
		$data .= $race->{'id'}.",".$race->{'elevation_gain'}.",".$race->{'city'}.",".$race->{'name'}.",".$date.",".$time."\n";
	}
	saveDataFile($data);
}

main();

sub saveYearlyRaces {
	saveToFile("strava_all_races.txt", shift);
}

sub readYearlyRaces {
	return readSavedFile("strava_all_races.txt");
}

sub saveCountryRaces {
	saveToFile("strava_country_races.txt", shift);
}

sub readCountryRaces {
	return readSavedFile("strava_country_races.txt");
}

sub saveDetailedRaces {
	saveToFile("strava_detailed_races.txt", shift);
}

sub readDetailedRaces {
	return readSavedFile("strava_detailed_races.txt");
}

sub saveDetailedRoutes {
	saveToFile("strava_detailed_routes.txt", shift);
}

sub readDetailedRoutes {
	return readSavedFile("strava_detailed_routes.txt");
}

sub saveDataFile {
	saveToFile("races_data.csv", shift);
}

sub saveToFile {
	my $filename = shift;
	my $str = shift;
	my $outputFile = $SAVE_PATH.$filename;
	
	open(FH, '>', $outputFile) or die $!;
	print FH $str;
	close(FH);
}

sub readSavedFile {
	my $filename = shift;
	my $inputFile = $SAVE_PATH.$filename;
	
	open my $fh, '<', $inputFile or return undef;
	return do { local $/; <$fh> };
}
