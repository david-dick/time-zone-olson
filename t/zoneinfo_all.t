#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Time::Local();
use Time::Zone::Olson();
use POSIX();
use Config;
use English qw( -no_match_vars );

$ENV{PATH} = '/bin:/usr/bin:/usr/sbin:/sbin';
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};
if ($^O eq 'cygwin') {
	delete $ENV{PATH};
}

if ($ENV{TZ}) {
	diag("TZ environment variable is $ENV{TZ}");
}

my $timezone = Time::Zone::Olson->new();
ok($timezone, "Time::Zone::Olson->new() generates an object");
if ($timezone->win32_registry()) {
	diag("Olson tz directory is using the Win32 Registry for Olson tz calculations for $^O");
} else {
	my $directory = $timezone->directory();
	diag("Olson tz directory is $directory for $^O");
}

if (!$timezone->timezone()) {
	$timezone->timezone('UTC');
	diag("$^O does not have a default timezone, setting to " . $timezone->timezone());
}
diag("Local timezone has been determined to be " . $timezone->timezone() );
ok($timezone->timezone(), "Local timezone has been determined to be " . $timezone->timezone() );
if (defined $timezone->determining_path()) {
	my $determining_path = $timezone->determining_path();
	diag("Local timezone was determined using " . $determining_path );
	diag(`ls -la $determining_path`);
}

my $perl_date = 0;
my $bsd_date = 0;
my $busybox_date = 0;
if ($^O eq 'MSWin32') {
	diag "$^O means we should use the pre-compiled Win32 date.exe binary in this distribution as the definitive source of truth for timezone calculations";
} elsif ($^O eq 'solaris') {
	diag "$^O does not have a useful date binary.";
	$perl_date = 1;
} else {
	my $test_gnu_date = `TZ="Australia/Melbourne" date -d "2015/02/28 11:00:00" +"%Y/%m/%d %H:%M:%S" 2>&1`;
	chomp $test_gnu_date;
	if (($test_gnu_date) && ($test_gnu_date eq '2015/02/28 11:00:00')) {
	} else {
		my $test_bsd_date = `TZ="Australia/Melbourne" date -r 1425081600 +"%Y/%m/%d %H:%M:%S" 2>&1`;
		chomp $test_bsd_date;
		if (($test_bsd_date) && ($test_bsd_date eq '2015/02/28 11:00:00')) {
			$bsd_date = 1;
		} else {
			my $test_busybox_date = `TZ="Australia/Melbourne" date -d "2015-02-28 11:00:00" 2>&1`;
			chomp $test_busybox_date;
			diag "Output of busybox date command:$test_busybox_date";
			if (($test_bsd_date) && ($test_bsd_date eq '2015/02/28 11:00:00')) {
				$busybox_date = 1;
			} else {
				$perl_date = 1;
			}
		}
	}
}

ok($timezone->timezone() =~ /^\w+(\/[\w\-\/+]+)?$/, "\$timezone->timezone() parses correctly");
if (($timezone->areas()) && ((scalar $timezone->areas()) > 1)) {
	ok((grep /^Australia$/, $timezone->areas()), "Found 'Australia' in \$timezone->areas()");
	ok((grep /^Melbourne$/, $timezone->locations('Australia')), "Found 'Melbourne' in \$timezone->areas('Australia')");
	if (!$timezone->win32_registry()) {
		my $comment = $timezone->comment('Australia/Melbourne');
		ok($comment =~ /Victoria/smx, "\$timezone->comment('Australia/Melbourne') contains /Victoria/");
		diag("Comment for 'Australia/Melbourne' is '$comment'");
	}
}
my $tz = $timezone->timezone();
my $directory = $timezone->directory();
if ($ENV{TZDIR}) {
	if ($directory =~ /^(.*)$/) {
		$directory = $1;
	}
}
my $current_year = (localtime)[5] + 1900;
my $start_year = $current_year - 3;
my $end_year = $current_year + 2;
if (($^O eq 'MSWin32') || ($^O eq 'cygwin')) {
} elsif ($^O eq 'solaris') {
	diag(`zdump -c $start_year,$end_year -v $tz | tail`);
} else {
	diag(`zdump -c $start_year,$end_year -v $directory/$tz | tail`);
}
my $todo;
if ($^O eq 'MSWin32') {
} elsif ($bsd_date) {
	diag("bsd test of early date:" . `TZ="Australia/Melbourne" date -r "-2172355201" +"%Y/%m/%d %H:%M:%S %Z" 2>&1`);
} elsif ($busybox_date) {
	diag("busybox test of early date:" . `TZ="Australia/Melbourne" date -d "1901-02-28 23:59:59 GMT" 2>&1`);
} elsif ($perl_date) {
	$todo = "perl does not always agree with date(1)";
} else {
	diag("gnu test of early date:" . `TZ="Australia/Melbourne" date -d "1901/02/28 23:59:59 GMT" +"%Y/%m/%d %H:%M:%S %Z" 2>&1`);
}
$TODO = $todo;

my $count = 0;
foreach my $area ($timezone->areas()) {
	foreach my $location ($timezone->locations($area)) {
		if ( $ENV{RELEASE_TESTING}) {
		} else {
			next if ("$area/$location" ne $tz);
		}
		$timezone->timezone("$area/$location");
		my $transition_time_index = 0;
		my @transitions = ($^O eq 'MSWin32') ? (get_windows_transition_times($timezone, $area, $location)) : ($timezone->transition_times());
		foreach my $transition_time (@transitions) {
			if (($Config{archname} !~ /^(?:amd64|x86_64)/) && ($transition_time > (2 ** 31) - 1)) {
			} elsif (($Config{archname} !~ /^(?:amd64|x86_64)/) && ($transition_time < -2 ** 31)) {
			} else {
				eval { gmtime $transition_time } or do { next };
				my $correct_date = get_external_date($area, $location, $transition_time);
				my $test_date = POSIX::strftime("%Y/%m/%d %H:%M:%S", $timezone->local_time($transition_time)) . q[ ] . $timezone->local_abbr($transition_time);
				SKIP: {
					if ($correct_date) {
						ok($test_date eq $correct_date, "Matched $test_date to $correct_date for $area/$location for \$timezone->local_time($transition_time)");
					} else {
						skip("system 'date' command did not produce any output at all for $area/$location", 1);
					}
				}
				my $revert_time = $timezone->time_local($timezone->local_time($transition_time));
				ok($revert_time <= $transition_time, "\$timezone->time_local(\$timezone->local_time(\$transition_time)) <= \$transition_time where $revert_time = $transition_time with a difference of " . ($revert_time - $transition_time) . " for $area/$location"); 
				my $revert_date = get_external_date($area, $location, $revert_time);
				SKIP: {
					if ($correct_date) {
						ok(strip_external_date($revert_date) eq strip_external_date($correct_date), "Matched $revert_date to $correct_date for $area/$location for \$timezone->time_local");
					} else {
						skip("system 'date' command did not produce any output at all for $area/$location", 1);
					}
				}
				SKIP: {
					local %ENV = %ENV;
					$ENV{TZ} = "$area/$location";
					my @local_time = $timezone->local_time($transition_time);
					$local_time[5] += 1900;
					my $time_local;
					eval {
						$time_local = Time::Local::timelocal(@local_time);
					} or do {
						chomp $@;
						skip("Time::Local::timelocal("  . join(',', @local_time) . ") threw an exception:$@", 1);
					};
					if ($revert_time <= $time_local) {
						ok($revert_time <= $time_local, "\$timezone->time_local() <= Time::Local::time_local() where $revert_time = $time_local with a difference of " . ($revert_time - $time_local) . " for $area/$location"); 
					} else {
						my $test_time_local = get_external_date($area, $location, $time_local);
						SKIP: {
							if ($correct_date and $test_time_local) {
								if ($test_time_local eq $correct_date) {
									ok($revert_time <= $time_local, "\$timezone->time_local() <= Time::Local::time_local() where $revert_time = $time_local with a difference of " . ($revert_time - $time_local) . " for $area/$location"); 
								} else {
									diag("Time::Local::local_time(" . join(',', @local_time) . ") returned $time_local which translated back to $test_time_local for $area/$location");
								}
							} else {
								skip("system 'date' command did not produce any output at all for $area/$location", 1);
							}
						}
					}
				}
				$transition_time -= 1;
				$correct_date = get_external_date($area, $location, $transition_time);
				$test_date = POSIX::strftime("%Y/%m/%d %H:%M:%S", $timezone->local_time($transition_time)) . q[ ] . $timezone->local_abbr($transition_time);
				SKIP: {
					if ($correct_date) {
						if ($test_date eq $correct_date) {
							ok($test_date eq $correct_date, "Matched $test_date to $correct_date for $area/$location for \$timezone->local_time - 1");
						} else {
							my $todo = q[];
							if (($^O eq 'MSWin32') && ($test_date ne $correct_date)) {
								my $change_tz = $correct_date;
								if ($change_tz =~ s/Standard/Summer/smx) {
									if ($test_date eq $change_tz) {
										$todo = "MSWin32 C# is broken in the hour after moving from DST to STD";
									}
								}
							}
							local $TODO = $todo;
							ok($test_date eq $correct_date, "Matched $test_date to $correct_date for $area/$location for \$timezone->local_time - 1");
						}
					} else {
						skip("system 'date' command did not produce any output at all for $area/$location", 1);
					}
				}
				$revert_time = $timezone->time_local($timezone->local_time($transition_time));
				ok($revert_time <= $transition_time, "\$timezone->time_local(\$timezone->local_time(\$transition_time)) <= \$transition_time where $revert_time = $transition_time with a difference of " . ($revert_time - $transition_time) . " for $area/$location"); 
				$revert_date = get_external_date($area, $location, $revert_time);
				SKIP: {
					if ($correct_date) {
						ok(strip_external_date($revert_date) eq strip_external_date($correct_date), "Matched $revert_date to $correct_date for $area/$location for \$timezone->time_local - 1");
					} else {
						skip("system 'date' command did not produce any output at all for $area/$location", 1);
					}
				}
				SKIP: {
					local %ENV = %ENV;
					$ENV{TZ} = "$area/$location";
					my @local_time = $timezone->local_time($transition_time);
					$local_time[5] += 1900;
					my $time_local;
					eval {
						$time_local = Time::Local::timelocal(@local_time);
					} or do {
						chomp $@;
						skip("Time::Local::timelocal("  . join(',', @local_time) . ") threw an exception:$@", 1);
					};
					if ($revert_time <= $time_local) {
						ok($revert_time <= $time_local, "\$timezone->time_local() <= Time::Local::time_local() where $revert_time = $time_local with a difference of " . ($revert_time - $time_local) . " for $area/$location"); 
					} else {
						my $test_time_local = get_external_date($area, $location, $time_local);
						SKIP: {
							if ($correct_date and $test_time_local) {
								if ($test_time_local eq $correct_date) {
									ok($revert_time <= $time_local, "\$timezone->time_local() <= Time::Local::time_local() where $revert_time = $time_local with a difference of " . ($revert_time - $time_local) . " for $area/$location"); 
								} else {
									diag("Time::Local::local_time(" . join(',', @local_time) . ") returned $time_local which translated back to $test_time_local for $area/$location");
								}
							} else {
								skip("system 'date' command did not produce any output at all for $area/$location", 1);
							}
						}
					}
				}

				$transition_time += 2;
				$correct_date = get_external_date($area, $location, $transition_time);
				$test_date = POSIX::strftime("%Y/%m/%d %H:%M:%S", $timezone->local_time($transition_time)) . q[ ] . $timezone->local_abbr($transition_time);
				SKIP: {
					if ($correct_date) {
						ok($test_date eq $correct_date, "Matched $test_date to $correct_date for $area/$location for \$timezone->local_time + 1");
					} else {
						skip("system 'date' command did not produce any output at all for $area/$location", 1);
					}
				}
				$revert_time = $timezone->time_local($timezone->local_time($transition_time));
				ok($revert_time <= $transition_time, "\$timezone->time_local(\$timezone->local_time(\$transition_time)) <= \$transition_time where $revert_time = $transition_time with a difference of " . ($revert_time - $transition_time) . " for $area/$location"); 
				$revert_date = get_external_date($area, $location, $revert_time);
				SKIP: {
					if ($correct_date) {
						ok(strip_external_date($revert_date) eq strip_external_date($correct_date), "Matched $revert_date to $correct_date for $area/$location for \$timezone->time_local + 1");
					} else {
						skip("system 'date' command did not produce any output at all for $area/$location", 1);
					}
				}
				SKIP: {
					local %ENV = %ENV;
					$ENV{TZ} = "$area/$location";
					my @local_time = $timezone->local_time($transition_time);
					$local_time[5] += 1900;
					my $time_local;
					eval {
						$time_local = Time::Local::timelocal(@local_time);
					} or do {
						chomp $@;
						skip("Time::Local::timelocal("  . join(',', @local_time) . ") threw an exception:$@", 1);
					};
					if ($revert_time <= $time_local) {
						ok($revert_time <= $time_local, "\$timezone->time_local() <= Time::Local::time_local() where $revert_time = $time_local with a difference of " . ($revert_time - $time_local) . " for $area/$location"); 
					} else {
						my $test_time_local = get_external_date($area, $location, $time_local);
						SKIP: {
							if ($correct_date and $test_time_local) {
								if ($test_time_local eq $correct_date) {
									ok($revert_time <= $time_local, "\$timezone->time_local() <= Time::Local::time_local() where $revert_time = $time_local with a difference of " . ($revert_time - $time_local) . " for $area/$location"); 
								} else {
									diag("Time::Local::local_time(" . join(',', @local_time) . ") returned $time_local which translated back to $test_time_local for $area/$location");
								}
							} else {
								skip("system 'date' command did not produce any output at all for $area/$location", 1);
							}
						}
					}
				}
				$transition_time_index += 1;
				$count += 1;
				$count = $count % 2;
				if (defined $timezone->tz_definition()) {
					ok($timezone->tz_definition(), "TZ definition for $area/$location is " . $timezone->tz_definition());
				}
				if ($count == 0) {
					Time::Zone::Olson->reset_cache();
					$timezone = Time::Zone::Olson->new();
					$timezone->timezone("$area/$location");
				} else {
					$timezone->reset_cache();
				}
			}
		}
	}
}

sub strip_external_date {
	my ($date) = @_;
	if ($date =~ /^(\d{4}\/\d{2}\/\d{2}[ ]\d{2}:\d{2}:\d{2})[ ]/smx) {
		return $1;
	} else {
		warn "Failed to parse date";
		return $date;
	}
}

sub get_external_date {
	my ($area, $location, $unix_time) = @_;
	my $untainted_unix_time;
	if ($unix_time =~ /^(\-?\d+)$/) {
		($untainted_unix_time) = ($1);
	} else {
		die "Failed to parse transition time $unix_time";
	}
	my $formatted_date;
	if ($^O eq 'MSWin32') {
		my %mapping = Time::Zone::Olson->win32_mapping();
		my $win32_time_zone = $mapping{"$area/$location"};
		my $gm_strftime = POSIX::strftime("%Y/%m/%d %H:%M:%S", gmtime $untainted_unix_time);
		my $cwd = Cwd::cwd();
		$cwd =~ /^(.*)$/; # untainting cwd;
		$cwd = $1;
		$cwd =~ s/[\/]/\\/smxg;
		$formatted_date = `$cwd\\date.exe "$gm_strftime" "$win32_time_zone"`;
	} elsif ($perl_date) {
		$formatted_date = `TZ="$area/$location" perl -MPOSIX -e 'print POSIX::strftime("%Y/%m/%d %H:%M:%S %Z", localtime($untainted_unix_time))'`;
	} elsif ($bsd_date) {
		$formatted_date = `TZ="$area/$location" date -r $untainted_unix_time +"%Y/%m/%d %H:%M:%S %Z"`;
	} elsif ($busybox_date) {
		my $gm_strftime = POSIX::strftime("%Y-%m-%d %H:%M:%S GMT", gmtime $untainted_unix_time);
		$formatted_date = `TZ="$area/$location" date -d "$gm_strftime"`;
	} else {
		my $gm_strftime = POSIX::strftime("%Y/%m/%d %H:%M:%S GMT", gmtime $untainted_unix_time);
		$formatted_date = `TZ="$area/$location" date -d "$gm_strftime" +"%Y/%m/%d %H:%M:%S %Z"`;
	}
	if ($? != 0) {
		diag("external date command exited with a $? for $area/$location at " . POSIX::strftime("%Y/%m/%d %H:%M:%S GMT", gmtime $untainted_unix_time));
	}
	chomp $formatted_date;
	return $formatted_date;
}

sub get_windows_transition_times {
	my ($timezone, $area, $location) = @_;
	my %mapping = Time::Zone::Olson->win32_mapping();
	my $win32_time_zone = $mapping{"$area/$location"};
	require Win32API::Registry;

	my $year = (localtime)[5] + 1900;
	my $timezone_specific_registry_path = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones\\" . $mapping{"$area/$location"};
	Win32API::Registry::RegOpenKeyEx(Win32API::Registry::HKEY_LOCAL_MACHINE(), $timezone_specific_registry_path, 0, Win32API::Registry::KEY_QUERY_VALUE(), my $timezone_specific_subkey) or Carp::croak( "Failed to open LOCAL_MACHINE\\$timezone_specific_registry_path:$EXTENDED_OS_ERROR");
	Win32API::Registry::RegQueryValueEx( $timezone_specific_subkey, 'TZI', [], [], my $binary, []) or Carp::croak("Failed to read LOCAL_MACHINE\\$timezone_specific_registry_path\\TZI:$EXTENDED_OS_ERROR");
	my ($bias, $standard_bias, $daylight_bias, $standard_year, $standard_month, $standard_day_of_week, $standard_week, $standard_hour, $standard_minute, $standard_second, $standard_millisecond, $daylight_year, $daylight_month, $daylight_day_of_week, $daylight_week, $daylight_hour, $daylight_minute, $daylight_second, $daylight_millisecond) = unpack 'lllSSSSSSSSSSSSSSSS', $binary;
        my $dst_start_time = $timezone->_get_time_for_wday_week_month_year_offset(
            day    => $daylight_day_of_week,
            week   => $daylight_week,
            month  => $daylight_month,
            year   => $year,
            offset => ($daylight_hour * 3600) + ($daylight_minute * 60) + $daylight_second + (($bias + $standard_bias) * 60)
        );
        my $dst_end_time = $timezone->_get_time_for_wday_week_month_year_offset(
            day    => $standard_day_of_week,
            week   => $standard_week,
            month  => $standard_month,
            year   => $year,
            offset => ($standard_hour * 3600) + ($standard_minute * 60) + $standard_second + (($bias + $daylight_bias) * 60)
        );
	return ($dst_start_time, $dst_end_time);
}

Test::More::done_testing();
