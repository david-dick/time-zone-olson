#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Time::Zone::Olson();
use POSIX();
use English qw( -no_match_vars );
use Encode();
use Cwd();

if ($^O eq 'MSWin32') {
} elsif ($^O eq 'cygwin') {
	delete $ENV{PATH};
} else {
	$ENV{PATH} = '/bin:/usr/bin';
}
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

if ($ENV{TZ}) {
	diag("TZ environment variable is $ENV{TZ}");
}
my $timezone = Time::Zone::Olson->new();
ok($timezone, "Time::Zone::Olson->new() generates an object");

if ($timezone->location()) {
	$ENV{TZ} = $timezone->area() . '/' . $timezone->location();
} elsif ($timezone->area()) {
	$ENV{TZ} = $timezone->area();
}
if (defined $ENV{TZ}) {
	diag("Determined timezone is $ENV{TZ}");
} elsif (defined $timezone->timezone()) {
	diag("Timezone did not parse into area/location:" . $timezone->timezone());
} else {
	diag("Timezone could not be determined");
}
if (defined $ENV{TZDIR}) {
	diag("TZDIR has been set to $ENV{TZDIR}");
} else {
	diag("TZDIR has not been set");
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
	diag "Output of gnu date command:$test_gnu_date";
	if (($test_gnu_date) && ($test_gnu_date eq '2015/02/28 11:00:00')) {
	} else {
		my $test_bsd_date = `TZ="Australia/Melbourne" date -r 1425081600 +"%Y/%m/%d %H:%M:%S" 2>&1`;
		chomp $test_bsd_date;
		diag "Output of bsd date command:$test_bsd_date";
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

my $pack_q_ok = 0;
eval { my $q = pack 'q>', 2 ** 33; my $p = unpack 'q>', $q; $pack_q_ok = 1; };
diag"Results of unpack:$@";

if ($^O eq 'MSWin32') {
	ok(!defined $timezone->directory(), "\$timezone->directory() is not defined for $^O");
} else {
	ok(-e $timezone->directory(), "\$timezone->directory() returns the correct directory");
}
if (!$timezone->timezone()) {
	$timezone->timezone('UTC');
	diag("$^O does not have a default timezone, setting to " . $timezone->timezone());
}
diag("Local timezone has been determined to be " . $timezone->timezone() );
ok($timezone->timezone() =~ /^\w+(?:\/[\w\-\/]+)?$/, "\$timezone->timezone() parses correctly");
if ($timezone->location()) {
	ok($timezone->area() . '/' . $timezone->location() eq $timezone->timezone(), "\$timezone->area() and \$timezone->location() contain the area and location of the current timezone");
} elsif (defined $timezone->area()) {
	ok($timezone->area() eq $timezone->timezone(), "\$timezone->area() and \$timezone->location() contain the area and location of the current timezone");
} elsif (defined $timezone->area()) {
	diag("Local timezone does not have an area");
}
if (($timezone->areas()) && ((scalar $timezone->areas()) > 1)) {
	ok((grep /^Australia$/, $timezone->areas()), "Found 'Australia' in \$timezone->areas()");
	ok((grep /^Melbourne$/, $timezone->locations('Australia')), "Found 'Melbourne' in \$timezone->areas('Australia')");
	if ($^O eq 'MSWin32') {
		diag("$^O comment for Australia/Melbourne is '" . Encode::encode('UTF-8', $timezone->comment('Australia/Melbourne'), 1) . "'");
		ok($timezone->comment('Australia/Melbourne') =~ /^[(](?:GMT|UTC)[+]10:00[)][ ]/smx, "\$timezone->comment('Australia/Melbourne') contains //^[(]GMT[+]10:00[)][ ]");
	} else {
		ok($timezone->comment('Australia/Melbourne') =~ /Victoria/smx, "\$timezone->comment('Australia/Melbourne') contains /Victoria/");
	}
} else {
	diag("No timezone areas are available");
}
my $now = time;
my @correct_localtime = localtime $now;
my @test_localtime = $timezone->local_time($now);
my $matched = 1;
foreach my $index (0 .. (( scalar @correct_localtime )- 1)) {
	if ($correct_localtime[$index] eq $test_localtime[$index]) {
	} else {
		diag("Missed wantarray location (1) test for $^O on index $index ('$correct_localtime[$index]' eq '$test_localtime[$index]')");
		$matched = 0;
	}
}
foreach my $index (0 .. (( scalar @test_localtime )- 1)) {
	if ($correct_localtime[$index] eq $test_localtime[$index]) {
	} else {
		diag("Missed wantarray location (2) test for $^O on index $index ('$correct_localtime[$index]' eq '$test_localtime[$index]')");
		$matched = 0;
	}
}

ok($matched, "Matched wantarray localtime");
if (!$matched) {
	diag("Seconds since UNIX epoch is:$now");
	diag("Time::Zone::Olson produces:" . join ', ', @test_localtime);
	diag("perl localtime produces   :" . join ', ', @correct_localtime);
	if ($^O ne 'MSWin32') {
		diag(`ls -la /etc/localtime`);
		my $current_timezone = $timezone->timezone();
		my $directory = $timezone->directory();
		diag("Permissions of $directory/$current_timezone is " . `ls -la $directory/$current_timezone`);
		diag("Content of $directory/$current_timezone is " . `cat $directory/$current_timezone | base64`);
		diag("Content of /etc/localtime is " . `cat /etc/localtime | base64`);
	}
}

DST_TIME: {
	my $area = 'Australia';
	my $location = 'Brisbane';
	my $timezone = Time::Zone::Olson->new();
	$timezone->timezone("$area/$location");
	my $dst_time = 1677628520;
	my $correct_date = get_external_date($area, $location, $dst_time);
	if (defined $correct_date) {
		my $test_date = POSIX::strftime('%Y/%m/%d %H:%M:%S', $timezone->local_time($dst_time)) . q[ ] . $timezone->local_abbr($dst_time);
		ok($test_date eq $correct_date, Encode::encode("UTF-8", "Matched $test_date to $correct_date for $area/$location", 1));
	}
	$area = 'Asia';
	$location = 'Tehran';
	$timezone->timezone("$area/$location");
	$dst_time = 1678394828;
	$correct_date = get_external_date($area, $location, $dst_time);
	if (defined $correct_date) {
		my $test_date = POSIX::strftime('%Y/%m/%d %H:%M:%S', $timezone->local_time($dst_time)) . q[ ] . $timezone->local_abbr($dst_time);
		ok($test_date eq $correct_date, Encode::encode("UTF-8", "Matched $test_date to $correct_date for $area/$location", 1));
	}
}

my $melbourne_offset;
my $melbourne_date;
DATE: {
	my $todo;
	if ($perl_date) {
		$todo = "perl does not always agree with date(1)";
	}
	local $TODO = $todo;
	foreach my $area ($timezone->areas()) {
		foreach my $location ($timezone->locations($area)) {
			my $correct_date = get_external_date($area, $location, $now);
			$timezone->timezone("$area/$location");
			if ($timezone->timezone() eq 'Australia/Melbourne') {
				$melbourne_offset = $timezone->local_offset($now);
				$melbourne_date = $timezone->local_time($now);
			}
			my $test_date = POSIX::strftime('%Y/%m/%d %H:%M:%S', $timezone->local_time($now)) . q[ ] . $timezone->local_abbr($now);
			ok($test_date eq $correct_date, Encode::encode("UTF-8", "Matched $test_date to $correct_date for $area/$location", 1));
			my @local_time = $timezone->local_time($now);
			my $revert_time = $timezone->time_local(@local_time);
			ok($revert_time <= $now, "\$timezone->time_local(\$timezone->local_time(\$now)) <= \$now where $revert_time = $now with a difference of " . ($revert_time - $now) . " for $area/$location"); 
			my @leap_seconds = $timezone->leap_seconds();
			die "Leap seconds found in $area/$location" if (scalar @leap_seconds);
		}
	}
}
if (defined $melbourne_offset) {
	ok((defined $melbourne_offset) && (($melbourne_offset == 600) or ($melbourne_offset == 660)), "Correctly returned the offset for Melbourne/Australia is either 600 or 660 minutes");

	$timezone->offset($melbourne_offset);
	my $test_date = $timezone->local_time($now);
	ok($test_date eq $melbourne_date, "Matched $test_date to $melbourne_date for when manually setting offset to $melbourne_offset minutes");
	my @local_time = $timezone->local_time($now);
	my $revert_time = $timezone->time_local(@local_time);
	ok($revert_time <= $now, "\$timezone->time_local(\$timezone->local_time(\$now)) == \$now when manually setting offset to $melbourne_offset minutes");

	$timezone = Time::Zone::Olson->new( 'offset' => $melbourne_offset );
	$test_date = $timezone->local_time($now);
	ok($test_date eq $melbourne_date, "Matched $test_date to $melbourne_date for when manually setting offset to $melbourne_offset minutes");
	@local_time = $timezone->local_time($now);
	$revert_time = $timezone->time_local(@local_time);
	ok($revert_time <= $now, "\$timezone->time_local(\$timezone->local_time(\$now)) == \$now when manually setting offset to $melbourne_offset minutes");

	$timezone->timezone("Australia/Melbourne");

	if (($^O eq 'linux') || ($^O =~ /bsd/)) {
		ok($timezone->equiv("Australia/Hobart") && !$timezone->equiv("Australia/Perth") && !$timezone->equiv("Australia/Hobart", 0), "Successfully compared Melbourne to Perth and Hobart timezones");
	} else {
		if (!$timezone->equiv("Australia/Hobart")) {
			diag("$^O does not agree that Melbourne and Hobart time are the same from now on");
		}
		ok(!$timezone->equiv("Australia/Perth"), "Successfully compared Melbourne to Perth timezones");
		if ($timezone->equiv("Australia/Hobart", 0)) {
			diag("$^O does not agree that Melbourne and Hobart time have NOT been the same since the UNIX epoch");
		}
	}
	if (!$matched) {
		my @test_localtime = $timezone->local_time($now);
		diag("Time::Zone::Olson produces for " . $timezone->timezone() . ":" . join ', ', @test_localtime);
		if ($^O eq 'MSWin32') {
		} elsif ($^O eq 'solaris') {
			diag("date returns " . `date`);
		}
	}
}
diag("Now is $now");
Test::More::done_testing();

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
		$formatted_date = `TZ="$area/$location" perl -MPOSIX -e 'print POSIX::strftime(q[%Y/%m/%d %H:%M:%S %Z], localtime($untainted_unix_time))'`;
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

