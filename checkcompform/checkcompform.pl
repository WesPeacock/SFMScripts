#!/usr/bin/env perl
my $USAGE = "Usage: $0 [--inifile inifile.ini] [--section checkcompform] [--recmark lx] [--hmmark hm] [--eolrep #] [--reptag __hash__] [--debug] [file.sfm]";
=pod
This script 
It also includes code to:
	- process command line options including debugging

The ini file should have sections with syntax like this:
[section]
Param1=Value1
Param2=Value2

=cut
use 5.020;
use utf8;
use open qw/:std :utf8/;

use strict;
use warnings;
use English;
use Data::Dumper qw(Dumper);

use File::Basename;
my $scriptname = fileparse($0, qr/\.[^.]*/); # script name without the .pl

use Getopt::Long;
GetOptions (
	'inifile:s'   => \(my $inifilename = "$scriptname.ini"), # ini filename
	'section:s'   => \(my $inisection = "checkcompform"), # section of ini file to use
# additional options go here.
# 'sampleoption:s' => \(my $sampleoption = "optiondefault"),
	'recmark:s' => \(my $recmark = "lx"), # record marker, default lx
	'eolrep:s' => \(my $eolrep = "#"), # character used to replace EOL
	'reptag:s' => \(my $reptag = "__hash__"), # tag to use in place of the EOL replacement character
	# e.g., an alternative is --eolrep % --reptag __percent__

	# Be aware # is the bash comment character, so quote it if you want to specify it.
	#	Better yet, just don't specify it -- it's the default.
	'hmmark:s' => \(my $hmmark = "hm"), # homograph marker, default hm
	'mnmark:s' => \(my $mnmark = "mn"), # main entry marker, default mn
	'debug'       => \my $debug,
	) or die $USAGE;

# check your options and assign their information to variables here
$recmark =~ s/[\\ ]//g; # no backslashes or spaces in record marker
$hmmark =~ s/[\\ ]//g; # no backslashes or spaces in homograph marker

# if you have set the $inifilename & $inisection in the options, you only need to set the parameter variables according to the parameter names
use Config::Tiny;
my $config = Config::Tiny->read($inifilename, 'crlf');
die "Quitting: couldn't find the INI file $inifilename\n$USAGE\n" if !$config;
my $comparefilename = $config->{"$inisection"}->{comparefilename};
say STDERR "Compare File:$comparefilename";

my $gentag = $config->{"$inisection"}->{gentag};
#sfm & tag for input to hackFWdata script
say STDERR "Generated Tag:$gentag";

open my $comparefilefh, '<', $comparefilename or die "couldn't open compare file $comparefilename: $!";

my @cmpopledfile_in;
my $line = ""; # accumulated SFM record
while (<$comparefilefh>) {
	s/\R//g; # chomp that doesn't care about Linux & Windows
	#perhaps s/\R*$//; if we want to leave in \r characters in the middle of a line
	s/$eolrep/$reptag/g;
	$_ .= "$eolrep";
	if (/^\\$recmark /) {
		$line =~ s/$eolrep$/\n/;
		push @cmpopledfile_in, $line;
		$line = $_;
		}
	else { $line .= $_ }
	}
push @cmpopledfile_in, $line;

# generate array of the input file with one SFM record per line (opl)
my @opledfile_in;
$line = ""; # accumulated SFM record
while (<>) {
	s/\R//g; # chomp that doesn't care about Linux & Windows
	#perhaps s/\R*$//; if we want to leave in \r characters in the middle of a line 
	s/$eolrep/$reptag/g;
	$_ .= "$eolrep";
	if (/^\\$recmark /) {
		$line =~ s/$eolrep$/\n/;
		push @opledfile_in, $line;
		$line = $_;
		}
	else { $line .= $_ }
	}
push @opledfile_in, $line;

my %oplhash; # hash of opl'd file keyed by \lx(\hm);
my $oplline;
my $oplrecno =-1;
for $oplline (@opledfile_in) {
	$oplrecno++;
	next if ! ($oplline =~ m/\\$recmark ([^#]*)/);
	my $oplkey = $1;
	$oplkey .= $1 if ($oplline =~ m/\\$hmmark ([^#]*)/);
	$oplhash{$oplkey} = $oplrecno;
	}

for $oplline (@cmpopledfile_in) {
	next if ! ($oplline =~ m/\\$mnmark ([^#]*)/);
	my $main = $1;
	if (!defined $oplhash{$main}) {
		$oplline =~ m/\\$recmark ([^#]*)/;
		my $lx = $1;
		my $hm = "";
		if ($oplline =~ m/\\$hmmark ([^#]*)/) {
			$hm = $1;
			}
		my $reckey = $main;
		$reckey =~ s/[0-9]//g;
		say STDERR qq[Bad mn "$main" ref in lx/hm "$lx$hm", looking for "$reckey"];
		if (!defined $oplhash{$reckey}) {
			say STDERR "Nope, that failed too.";
			next;
			}
		my $chgline = @opledfile_in[$oplhash{$reckey}];
		$chgline =~ s/\\ps /\\$gentag#\\ps /;
		@opledfile_in[$oplhash{$reckey}] = $chgline;
		next;
		}
	$oplline =~ m/\\$recmark ([^#]*)/;
	my $reckey = $1;
	my $oplkey = $reckey;
	if ($oplline =~ m/\\$hmmark ([^#]*)/) {
		$oplkey = $reckey . $1;
		}
	if (!defined $oplhash{$oplkey}) {
		say STDERR qq[Bad lx/hm "$oplkey", trying "$reckey"];
		if (!defined $oplhash{$reckey}) {
			say STDERR "Nope, that failed too.";
			next;
			}
		else {
			$oplkey = $reckey;
			}
		}
	my $chgline = @opledfile_in[$oplhash{$oplkey}];
	$chgline =~ s/\\ps /\\$gentag#\\ps /;
	@opledfile_in[$oplhash{$oplkey}] = $chgline;
	}

for $oplline (@opledfile_in) {
# Insert code here to perform on each opl'ed line.
# Note that a next command will prevent the line from printing
say STDERR "oplline:", Dumper($oplline) if $debug;
#de_opl this line
	for ($oplline) {
		s/$eolrep/\n/g;
		s/$reptag/$eolrep/g;
		print;
		}
	}

