#!/usr/bin/perl
use strict;
use warnings;

# Codex renders conversation content inside the terminal's alternate screen.
# Its CLI prints the updater result only after leaving that screen, so require
# that ordering before creating the marker consumed by resume-codex.sh.
my $marker = shift @ARGV;
exit 2 if !defined($marker) || @ARGV;

my $enter_alt = "\e[?1049h";
my $leave_alt = "\e[?1049l";
my $success = 'Update ran successfully! Please restart Codex.';
my $buffer = '';
my $saw_alt = 0;
my $in_alt = 0;
my $candidate = 0;
my $keep = length($success) - 1;

while (1) {
	my $read = read(STDIN, my $chunk, 8192);
	last if !defined($read) || $read == 0;
	$buffer .= $chunk;

	while (1) {
		my @events = (
			[index($buffer, $enter_alt), 'enter', length($enter_alt)],
			[index($buffer, $leave_alt), 'leave', length($leave_alt)],
			[index($buffer, $success), 'success', length($success)],
		);
		@events = sort { $a->[0] <=> $b->[0] } grep { $_->[0] >= 0 } @events;
		last if !@events;

		my ($index, $type, $length) = @{$events[0]};
		$buffer = substr($buffer, $index + $length);
		if ($type eq 'enter') {
			$saw_alt = 1;
			$in_alt = 1;
			$candidate = 0;
		} elsif ($type eq 'leave') {
			$in_alt = 0 if $saw_alt;
		} elsif ($saw_alt && !$in_alt) {
			$candidate = 1;
		}
	}

	$buffer = substr($buffer, -$keep) if length($buffer) > $keep;
}

exit 1 if !$candidate || $in_alt;
open(my $file, '>', $marker) or exit 3;
close($file) or exit 3;
exit 0;
