#!/usr/bin/perl -w

###############################################################################
# UseVoteGer 4.09 Bounce-Verarbeitung
# (c) 2001-2005 Marc Langer <uv@marclanger.de>
# 
# This script package is free software; you can redistribute it and/or
# modify it under the terms of the GNU Public License as published by the
# Free Software Foundation.
#
# Use this script to process bounce messages and generate a list of
# undeliverable voter adresses.
#
# Many thanks to:
# - Ron Dippold (Usevote 3.0, 1993/94)
# - Frederik Ramm (German translation, 1994)
# - Wolfgang Behrens (UseVoteGer 3.1, based on Frederik's translation, 1998/99)
# - Cornell Binder for some good advice and code fragments
#
# This is a complete rewrite of UseVoteGer 3.1 in Perl (former versions were
# written in C). Not all functions of Usevote/UseVoteGer 3.x are implemented!
###############################################################################

use strict;
use Getopt::Long;
use FindBin qw($Bin);
use lib $Bin;
use UVconfig;
use UVreadmail;
use UVtemplate;

my %opt_ctl = ();
my %bounces = ();
my $pop3 = 0;

print STDERR "\n$usevote_version Bounce-Verarbeitung - (c) 2001-2005 Marc Langer\n\n";

# unknown parameters remain in @ARGV (for "help")
Getopt::Long::Configure(qw(pass_through bundling));

# Put known parameters in %opt_ctl
GetOptions(\%opt_ctl, qw(h|help f|file config-file=s c=s));

# Get name auf config file (default: usevote.cfg) and read it
my $cfgfile   = $opt_ctl{'config-file'} || $opt_ctl{c} || "usevote.cfg";
UVconfig::read_config($cfgfile);

# check POP3 settings in usevote.cfg and combination with -f parameter
$pop3 = 1 if ($config{pop3} && !$opt_ctl{f});

# Additional parameters or invalid options? Show help and exit. 
help() if ($opt_ctl{h} || !(@ARGV || $pop3));

# check for lock file
if (-e $config{lockfile}) {
  my $lockfile = $config{lockfile};

  # don't delete lockfile in END block ;-)
  $config{lockfile} = '';

  # exit
  die UVmessage::get("ERR_LOCK", (FILE=>$lockfile)) . "\n\n";
}

# safe exit (delete lockfile)
$SIG{QUIT} = 'sighandler';
$SIG{INT} = 'sighandler';
$SIG{KILL} = 'sighandler';
$SIG{TERM} = 'sighandler';
$SIG{HUP} = 'sighandler';

# create lock file
open (LOCKFILE, ">$config{lockfile}");
close (LOCKFILE);

# read and process mails
# for each mail pass a reference to the sub to be called

if ($pop3) {
  unless (-d $config{archivedir}) {
    mkdir ($config{archivedir}, 0700)
      or die UVmessage::get("ERR_MKDIR", (DIR => $config{archivedir})) . "$!\n\n";
  }

  # mails are saved in file
  # normally unixtime is sufficient for a unique file name, else append PID
  my $ext = time;
 
  opendir (ARCHIVE, $config{archivedir});
  my @fertigfiles = readdir (ARCHIVE);
  closedir (ARCHIVE);
 
  # append PID if file name already exists
  $ext .= "-$$" if (grep (/$ext/, @fertigfiles));
 
  my $file = "$config{archivedir}/bounces-" . $ext;
  UVreadmail::process($file, \&process_bounce, 2);   # 2 = POP3

} else {
  foreach my $file (@ARGV) {
    UVreadmail::process($file, \&process_bounce, 3); # 3 = existing file
  }
}

my $template = UVtemplate->new();

foreach my $address (sort keys %bounces) {
  my $name = $bounces{$address};
  my $request = 0;
  my $text;
  if ($name eq '***request***') {
    $name = '';
    $text = UVmessage::get ("BOUNCE_BALLOT") . "\n";
  } else {
    $text = UVmessage::get ("BOUNCE_ACKMAIL") . "\n";
  }
  $name = ' ' unless($name);
  $template->addListItem('bounces', name=>$name, mail=>$address, bouncetext=>$text);
}

print $template->processTemplate($config{'tpl_bouncelist'});
exit 0;


##############################################################################
# Evaluate a bounce                                                          #
# This sub is called from UVreadmail::process() for every mail               #
# Parameters: voter address and name, date header (strings)                  #
#             complete header and body (references to strings)               #
##############################################################################

sub process_bounce {
  # last element of @_ is the body, other stuff not needed here
  my $body = pop;
  my ($address, $name);

  # search body for voter name and address
  if ($$body =~ /$config{addresstext}\s+(\S+@\S+)/) {
    $address = $1;
    if ($$body =~ /$config{nametext2}\s+(.*)$/m) {
      $name = $1;
      $bounces{$address} = $name;
    } elsif ($$body =~ /$config{nametext}/) {
      # Text from this config option does only appear in ballots,
      # not in acknowledge mails. So this has to be a bounced ballot request
      $bounces{$address} = '***request***';
    } else {
      $bounces{$address} = '';
    }
  }
}


END {
  # delete lockfile
  unlink $config{lockfile} if ($config{lockfile});
}

sub sighandler {
  my ($sig) = @_;
  die "\n\nSIG$sig: deleting lockfile and exiting\n\n";
}


##############################################################################
# Print help text (options and syntax) on -h or --help                       #
##############################################################################

sub help {
  print <<EOF;
Usage: uvbounce.pl [-c config_file] [-f] DATEI1 [DATEI2 [...]]
       uvbounce.pl -h

Liest Bounces aus den uebergebenen Dateien oder aus einer POP3-Mailbox ein
(Verhalten haengt von usevote.cfg ab) und generiert eine Liste von
unzustellbaren Adressen, die an den 2. CfV oder das Result angehaengt
werden kann. Falls POP3 in usevote.cfg eingeschaltet und die Option -f
(siehe unten) nicht benutzt wurde, werden die uebergebenen Dateinamen
ignoriert.

  -c config_file   liest die Konfiguration aus config_file
                   (usevote.cfg falls nicht angegeben)

  -f, --file       liest die Bounces aus den uebergebenen Dateien, auch
                   wenn in der Konfigurationsdatei POP3 eingeschaltet ist.
                   Diese Option wird benoetigt, falls zwar die Stimmzettel
                   per POP3 eingelesen werden sollen, nicht aber die Bounces.

  -h, --help       zeigt diesen Hilfetext an

EOF

  exit 0;
}
