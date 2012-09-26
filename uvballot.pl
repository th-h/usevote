#!/usr/bin/perl -w

###############################################################################
# UseVoteGer 4.11 Wahlscheingenerierung
# (c) 2001-2012 Marc Langer <uv@marclanger.de>
# 
# This script package is free software; you can redistribute it and/or
# modify it under the terms of the GNU Public License as published by the
# Free Software Foundation.
#
# Use this script to create the ballot which can be inserted into the CfV.
# Not for personal ballots (personal=1 in usevote.cfg), use uvcfv.pl instead.
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
use Text::Wrap qw(wrap $columns);
use FindBin qw($Bin);
use lib $Bin;
use UVconfig;
use UVtemplate;

my %opt_ctl = ();

print STDERR "\n$usevote_version Wahlscheingenerierung - (c) 2001-2005 Marc Langer\n\n";

# unknown parameters remain in @ARGV (for "help")
Getopt::Long::Configure(qw(pass_through bundling));

# Put known parameters in %opt_ctl
GetOptions(\%opt_ctl, qw(t|template c|config-file=s));

# Additional parameters or invalid options? Show help and exit.
help() if (@ARGV);

# Get name auf config file (default: usevote.cfg) and read it
my $cfgfile   = $opt_ctl{c} || "usevote.cfg";
UVconfig::read_config($cfgfile);

# Set columns for Text::Wrap
$columns = $config{rightmargin};

if ($config{personal}) {
  print_ballot_personal();
} else {
  print_ballot();
}

exit 0;


##############################################################################
# Print out a proper ballot                                                  #
##############################################################################

sub print_ballot {

  my $template = UVtemplate->new();

  $template->setKey('votename' => $config{votename});
  $template->setKey('nametext' => $config{nametext});
  $template->setKey('bdsg'     => $config{bdsg});
  $template->setKey('bdsgtext' => $config{bdsgtext});
  $template->setKey('bdsginfo' => $config{bdsginfo});

  for (my $n=0; $n<@groups; $n++) {
     $template->addListItem('groups', pos=>$n+1, group=>$groups[$n]);
  }

  print $template->processTemplate($config{'tpl_ballot'});

}


##############################################################################
# Generate a ballot request (if personalized ballots are activated)          #
##############################################################################

sub print_ballot_personal {
  my $template = UVtemplate->new();
  $template->setKey('mailaddress' => $config{mailfrom});
  print $template->processTemplate($config{'tpl_ballot_request'});
}


##############################################################################
# Print help text (options and syntax) on -h or --help                       #
##############################################################################

sub help {
  print STDERR <<EOF;
Usage: uvballot.pl [-c config_file]
       uvballot.pl -h

Generiert den Wahlschein fuer den CfV. Bei personalisierten Wahlscheinen
(personal = 1 in usevote.cfg) wird nur ein Dummy-Abschnitt mit Hinweisen
zur Wahlscheinanforderung ausgegeben.

  -c config_file   liest die Konfiguration aus config_file
                   (usevote.cfg falls nicht angegeben)

  -h, --help       zeigt diesen Hilfetext an

EOF

  exit 0;
}
