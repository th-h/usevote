#!/usr/bin/perl -w

###############################################################################
# UseVoteGer 4.09 Personalisierte Wahlscheine
# (c) 2001-2005 Marc Langer <uv@marclanger.de>
# 
# This script package is free software; you can redistribute it and/or
# modify it under the terms of the GNU Public License as published by the
# Free Software Foundation.
#
# Use this script to read mails and send back a CfV with unique ballot id
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
use Digest::MD5 qw(md5_hex);
use Text::Wrap qw(wrap $columns);
use FindBin qw($Bin);
use lib $Bin;
use UVconfig;
use UVmenu;
use UVmessage;
use UVreadmail;
use UVsendmail;
use UVtemplate;

my %opt_ctl = ();

print "\n$usevote_version Personalisierte Wahlscheine - (c) 2001-2005 Marc Langer\n\n";

# unknown parameters remain in @ARGV (for "help")
Getopt::Long::Configure(qw(pass_through bundling));

# Put known parameters in %opt_ctl
GetOptions(\%opt_ctl, qw(test t config-file=s c=s));

# test mode? (default: no)
my $test_only = $opt_ctl{test}          || $opt_ctl{t} || 0;

# # Additional parameters or invalid options? Show help and exit.
help() if (@ARGV);

# Get name auf config file (default: usevote.cfg) and read it
my $cfgfile   = $opt_ctl{'config-file'} || $opt_ctl{c} || "usevote.cfg";
UVconfig::read_config($cfgfile);

# Set columns for Text::Wrap
$columns = $config{rightmargin};

# read list of suspicious mail addresses from file
my @bad_addr = UVconfig::read_badaddr();

# exit if option "personal=1" in config file not set
unless ($config{personal}) {
  die wrap ('', '', UVmessage::get("ERR_NOTPERSONAL", (CFGFILE => $cfgfile))) . "\n\n";
}

# option -t used?
if ($test_only) {
  print_ballot();
  exit 0;
}

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

# check for tmp directory and domail file
unless (-d $config{tmpdir}) {
  mkdir ($config{tmpdir}, 0700)
    or die UVmessage::get("ERR_MKDIR", (DIR => $config{tmpdir})) . "\n$!\n\n";
}

# generate filename for mail archive
# normally unixtime is sufficient, if it is not unique append a number
my $file = my $base = "anforderung-" . time();
my $count = 0;
while ($count<1000 && (-e "$config{archivedir}/$file" || -e "$config{tmpdir}/$file")) {
  $file = "$base-" . ++$count;
}
die UVmessage::get("ERR_FILE_CREATION") . "\n\n" if ($count == 1000);

unless ($config{pop3}) {
  rename ($config{requestfile}, "$config{tmpdir}/$file")
    or die UVmessage::get("ERR_RENAME_MAILFILE") . "$!\n\n";
}
  
# wait, so that current mail deliveries can finalize
sleep 2;

# initiliaze random number generator
srand;

# read votes and process them
# for each mail pass a reference to the sub to be called
# The third parameter "1" shows that it is called from uvcfv.pl
$count = UVreadmail::process("$config{tmpdir}/$file", \&process_request, 1);
print "\n", UVmessage::get("CFV_NUMBER", (COUNT => $count)), "\n\n";
UVsendmail::send();

print UVmessage::get("INFO_TIDY_UP") . "\n\n";
rename("$config{tmpdir}/$file", "$config{archivedir}/$file");
chmod (0400, "$config{archivedir}/$file");

exit 0;


##############################################################################
# Evaluate a ballot request                                                  #
# Called from UVreadmail::process() for every mail                           #
# Parameters: Voter address and name, date header of vote mail (strings),    #
#             complete header and body (references to Strings)               #
##############################################################################

sub process_request {
  my ($voter_addr, $voter_name, $h_date, $entity, $body) = @_;

  my @header = split(/\n/, $entity->stringify_header);
  my $head = $entity->head;
  my $msgid = $head->get('Message-ID');
  chomp($msgid) if ($msgid);

  # found address?
  if ($voter_addr) {
    # check for suspicious addresses
    foreach my $element (@bad_addr) {
      if ($voter_addr =~ /^$element/) {
        my (@votes, @set, $ballot_id); # irrelevant, but necessary for UVmenu::menu()
        my @errors = ('SuspiciousAccountBallot');
        my $res = UVmenu::menu(\@votes, \@header, $body, \$voter_addr, \$voter_name, \$ballot_id, \@set, \@errors);

        # "Ignore": don't deliver a ballot
        return 0 if ($res eq 'i');
        if (@errors) {
          # send error mail if address hasn't been accepted
          my $template = UVtemplate->new();
          $template->setKey('head' => $entity->stringify_header);
          $template->setKey('body' => $$body);
          my $msg = $template->processTemplate($config{tpl_invalid_account});
          UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid);
          return 0;
        }
        last;
      }
    }
  } else  {
 
    # no address found in mail (non-RFC compliant?)
    my (@votes, @set, $ballot_id); # irrelevant, but necessary for UVmenu::menu()
    my @errors = ('InvalidAddressBallot');
    my $res = UVmenu::menu(\@votes, \@header, $body, \$voter_addr, \$voter_name, \$ballot_id, \@set, \@errors);

    # "ignore" or address not ok: no ballot can be sent
    return 0 if (@errors || $res eq 'i');
  }

  my $subject = UVmessage::get("CFV_SUBJECT");
  my $template = UVtemplate->new();
  my $ballot_id = "";

  #if ($ballot_id ne $ids{$voter_addr}) {
  if ($ids{$voter_addr}) {
    $ballot_id = $ids{$voter_addr};
    $template->setKey('alreadysent' => 1) if ($ballot_id = $ids{$voter_addr});
  } else {
    # generate new ballot id from the MD5 sum of header, body and a random value
    $ballot_id = md5_hex($entity->stringify_header . $body . rand 65535);
    $ids{$voter_addr} = $ballot_id;

    # write ballot id to file
    open(IDFILE, ">>$config{idfile}")
      or die UVmessage::get("CFV_ERRWRITE", (FILE => $config{idfile})) . "\n\n";
    print IDFILE "$voter_addr $ballot_id\n";
    close(IDFILE) or die UVmessage::get("CFV_ERRCLOSE") . "\n\n";
  }

  $template->setKey('ballotid' => $ballot_id);
  $template->setKey('address'  => $voter_addr);
  $template->setKey('bdsginfo' => $config{bdsginfo});

  for (my $n=0; $n<@groups; $n++) {
     $template->addListItem('groups', pos=>$n+1, group=>$groups[$n]);
  }

  my $msg = $template->processTemplate($config{'tpl_ballot_personal'});

  # $config{voteaccount} is the Reply-To address:
  UVsendmail::mail($voter_addr, $subject, $msg, $msgid, $config{voteaccount});

}


##############################################################################
# Print dummy personalized ballot in STDOUT for checking purposes            #
# Called if command line argument -t is present                              #
##############################################################################

sub print_ballot {
  my $template = UVtemplate->new();

  # generate new ballot id
  my $ballot_id = md5_hex(rand 65535);

  $template->setKey('ballotid' => $ballot_id);
  $template->setKey('address'  => 'dummy@foo.invalid');
  $template->setKey('bdsginfo' => $config{bdsginfo});

  for (my $n=0; $n<@groups; $n++) {
     $template->addListItem('groups', pos=>$n+1, group=>$groups[$n]);
  }

  my $msg = $template->processTemplate($config{'tpl_ballot_personal'});

  print $msg, "\n";
}


##############################################################################
# Handle Signals and delete lock files when exiting                          #
##############################################################################

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
Usage: uvcfv.pl [-c config_file] [-t]
       uvcfv.pl -h

Liest Mailboxen ein und beantwortet alle Mails mit personalisierten CfVs.

  -c config_file   liest die Konfiguration aus config_file
                   (usevote.cfg falls nicht angegeben)

  -t, --test       gibt einen Dummy-Wahlschein fuer Pruefzwecke aus

  -h, --help       zeigt diesen Hilfetext an

EOF

  exit 0;
}
