#!/usr/bin/env perl
my $USAGE = "Usage: $0 [--inifile inifile.ini] [--section section] [--recmark lx] [--hmmark hm] [--debug] [file.sfm]";
=pod
FLEx v 8.3 import flags cross-references that don't exist.

This script creates dummy entries based on the form that refers to them.
This is similar to MakeCompForm.pl but doesn't require two different fields.

This script reads an ini file for:
	* a list of Reference field Markers
	* probably only \rf

It opl's the SFM file.
It grinds over the opl'ed file building a hash of entry/homograph#
It grinds again finding references. If the referenced form is in the hash, ignore it.
Otherwise, create a dummy entry with a pointer to the main entry it occurs in.
Should replicate the part of speech
Add the dummy entry to the hash.

The ini file should have sections with syntax like this:
[MissingRf]
RfSFMs=Rf1,Rf2...
e.g.
RfSFMs=rf
=cut
use 5.020;
use utf8;
use open qw/:std :utf8/;

use strict;
use warnings;
use English;
use Data::Dumper qw(Dumper);

sub buildlxkey {
# simple function that returns the contents of the record marker field
# assumes the homograph marker occurs only under the main record marker
# i.e., doesn't handle homographs on subentries
# $recmark and $hmmark do not have leading backslash
	my ($line, $recmark, $hmmark) =@_;
	my $lxkey = "";
	if ($line =~ /\\$recmark ([^#]*)#.*/) {
		$lxkey = $1;
		if ($line =~ /\\$hmmark ([^#]*)#/) {
			$lxkey .= $1;
			}
		}
	return $lxkey;
	}

use File::Basename;
my $scriptname = fileparse($0, qr/\.[^.]*/); # script name without the .pl

use Getopt::Long;
GetOptions (
	'inifile:s'   => \(my $inifilename = "$scriptname.ini"), # ini filename
	'section:s'   => \(my $inisection = "MissingRf"), # section of ini file to use
# additional options go here.
# 'sampleoption:s' => \(my $sampleoption = "optiondefault"),
	'recmark:s' => \(my $recmark = "lx"), # record marker, default lx
	'hmmark:s' => \(my $hmmark = "hm"), # homograh number marker, default hm
	'debug'       => \my $debug,
	) or die $USAGE;

# check your options and assign their information to variables here
$recmark =~ s/[\\ ]//g; # no backslashes or spaces in record marker

# if you need  a config file uncomment the following and modify it for the initialization you need.
# if you have set the $inifilename & $inisection in the options, you only need to set the parameter variables according to the parameter names
#=pod
use Config::Tiny;
my $config = Config::Tiny->read($inifilename, 'crlf');
my $RfSFMs = "rf";
if ($config) {
	$RfSFMs = $config->{"$inisection"}->{RfSFMs};
	}
else {
	say STDERR "Couldn't find the INI file: $inifilename";
	say STDERR "Using \\rf for the reference marker";
	}
$RfSFMs  =~ s/\,*$//; # no trailing commas
$RfSFMs  =~ s/ //g;  # no spaces
$RfSFMs  =~ s/\,/\|/g;  # use bars for or'ing
my $srchSFMs = qr/$RfSFMs/;
say STDERR "Search RfSFMs:$RfSFMs" if $debug;
#=cut
my $dt = (substr localtime(), 8,2) . "/" . (substr localtime(), 4,3) . "/" . (substr localtime(), 20,4); # " 2/Oct/2019"
$dt =~ s/ //g; # no leading space on day 1-9 of month
say STDERR "date:$dt" if $debug;

# generate array of the input file with one SFM record per line (opl)
my @opledfile_in;

my $line = ""; # accumulated SFM record
my $linecount = 0 ;
while (<>) {
	s/\R//g; # chomp that doesn't care about Linux & Windows
	#perhaps s/\R*$//; if we want to leave in \r characters in the middle of a line 
	s/#/\_\_hash\_\_/g;
	$_ .= "#";
	if (/^\\$recmark /) {
		$line =~ s/#$/\n/;
		push @opledfile_in, $line;
		$line = $_;
		}
	else { $line .= $_ }
	}
push @opledfile_in, $line;

my %oplhash; # hash of opl'd file keyed by \lx(\hm)
for my $oplline (@opledfile_in) {
# build hash
	my $lxkey = buildlxkey($oplline, $recmark, $hmmark);
	$oplhash{$lxkey} = $oplline if $lxkey;
	}
for my $oplline (@opledfile_in) {
	my $extralines ="";
	while ($oplline =~ /\\$srchSFMs\ ([^#]+)#/g ) {
		my $rflxkey = $1;
		my $lxkey = buildlxkey($oplline, $recmark, $hmmark);
		if ($rflxkey =~ /[?:;\/]/) {
			say STDERR "found bad character -- $& in \\$recmark $lxkey";
			say STDERR "\\$RfSFMs $rflxkey";
			}
		else {
			$rflxkey =~ /^(.*?)([1-9])?$/; # find any homograph number
			my $rflx = $1;
			my $rfhm = $2;
			if (! exists $oplhash{$rflxkey}) {
				$oplline =~ /\\ps\ ([^#]+)#/; #get the part of speech for propagation
				my $rfPS =$1;
				my $newmainref ="\\lx $rflx#" . (($rfhm) ? "\\hm $rfhm#" : "" ) . "\\mn $lxkey#\\cm created by MissingRf#\\ps $rfPS#\\ind $dt#\\dt $dt##";
				$oplhash{$rflx} = $newmainref;
				$extralines .= $newmainref;
				}
			}
		}
say STDERR "oplline:", Dumper($oplline) if $debug;
#de_opl the created line
	for ($extralines) {
		s/#/\n/g;
		s/\_\_hash\_\_/#/g;
		print;
		}
	}
