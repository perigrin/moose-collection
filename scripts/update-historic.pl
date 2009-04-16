#!/usr/bin/perl

use Scriptalicious;
use autodie;
use Date::Parse;
use strict;
use warnings;

getopt;

open my $timeline, "<", (shift @ARGV)||".timeline";

my $line_iter = sub {
	my %line;
	@line{qw[ project version date ]}
		= split /\s+/, <$timeline>||(return undef);
	\%line;
};

my $day_iter = do {
	my @buffer;
	sub {
		while (!@buffer or $buffer[-1]{date} eq $buffer[0]{date}) {
			push @buffer, $line_iter->()||last;
		}
		splice @buffer, 0, $#buffer;
	}
};

my $checkout_version = sub {
	my $update = shift;
	my @cmds;
	push @cmds, "cd $update->{project}";
	push @cmds, "git checkout $update->{version}";
	my $rc = run_err(join "&&", @cmds);
	if ($rc) {
		moan "failed to check out $update->{version} ($update->{date})";
		say "you do it please then git tag $update->{version} kthx";
		system("cd $update->{project} && sh");
	}
};

run ("git checkout -f stable");
my $first_date = capture qw(git log -1 --pretty=format:%ai);

my $fix_out_of_date_modules = sub {
	my $which = shift || "HEAD";
	my @out_of_date = capture("git diff-files --name-only");
	for my $dir (@out_of_date) {
		chomp($dir);
		next unless -d "$dir/.git";
		my ($rc, $v) = capture_err("git rev-parse $which:$dir");
		chomp($v);
		if ($rc) {
			$v = capture("git rev-parse HEAD:$dir");
			chomp($v);
		}
		run("cd $dir; git checkout $v");
		run("git add $dir");
	}
};

my $commit = sub {
	my $prefix = "";
	if (!ref $_[0]) { $prefix = shift }
	my @updates = @_;
	my @diffs = capture qw(git diff-index --name-status HEAD);
	if (@diffs) {
		say "we're committing this:";
		print @diffs, "\n";
		abort unless prompt_Yn("ok?");
		run(
			"git", "commit", "-m",
			$prefix.join(", ", map
				{ "$_->{project} $_->{version}" }
					@updates
			),
		);
	}
};

while ( my @updates = $day_iter->() ) {
	my $date = $updates[0]{date};
	next unless $date ge $first_date;
	say "$date: ".@updates." new releases";

	my @stable_updates = grep { $_->{version} !~ m{_} } @updates;
	say "processing ".@stable_updates." stable updates";
	run("git checkout -f stable");
	$fix_out_of_date_modules->();
	for my $update (@stable_updates) {
		say "$update->{project} $update->{version}";
		$checkout_version->($update);
		run("git add $update->{project}");
	}
	$ENV{GIT_AUTHOR_DATE} = str2time($date)." +0000";
	$ENV{GIT_AUTHOR_NAME} = "The Moose Herd";
	$ENV{GIT_AUTHOR_EMAIL} = "moose\@perl.org";

	$commit->(@stable_updates);

	run("git checkout dev");
	$fix_out_of_date_modules->();
	run_err("git merge stable");
	$fix_out_of_date_modules->("MERGE_HEAD");
	$commit->("Merge 'stable' into 'dev': ", @stable_updates);

	$fix_out_of_date_modules->();

	for my $update (@updates) {
		$checkout_version->($update)
			if $update->{version} =~ m{_};
		run("git add $update->{project}");
	}

	$commit->(grep { $_->{version} =~ m{_} } @updates);
}

__END__
Example input:

MooseX-Role-Parameterized 0.03 2009-01-18
Class-MOP 0.76 2009-01-22
Moose 0.65 2009-01-22
MooseX-Singleton 0.14 2009-01-22
MooseX-Role-Parameterized 0.04 2009-01-31
Moose 0.66 2009-02-03
Moose 0.67 2009-02-04
Moose 0.68 2009-02-04
Mouse 0.15 2009-02-05
Mouse 0.16 2009-02-10
