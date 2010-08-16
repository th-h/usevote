#!/usr/bin/perl -w

###############################################################################
# UseVoteGer 4.09 Wahldurchfuehrung
# (c) 2001-2005 Marc Langer <uv@marclanger.de>
# 
# This script package is free software; you can redistribute it and/or
# modify it under the terms of the GNU Public License as published by the
# Free Software Foundation.
#
# The script reads usenet vote ballots from mailbox files. The format
# can be set by changing the option "mailstart".
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
use UVmenu;
use UVmessage;
use UVreadmail;
use UVsendmail;
use UVrules;
use UVtemplate;

my $clean = 0;
my %opt_ctl = ();

print "\n$usevote_version Wahldurchfuehrung - (c) 2001-2005 Marc Langer\n\n";

# unknown parameters remain in @ARGV (for "help")
Getopt::Long::Configure(qw(pass_through bundling));

# Put known parameters in %opt_ctl
GetOptions(\%opt_ctl, qw(test t config-file=s c=s));

# Get name auf config file (default: usevote.cfg) and read it
my $cfgfile   = $opt_ctl{'config-file'} || $opt_ctl{c} || "usevote.cfg";

# test mode? (default: no)
my $test_only = $opt_ctl{test}          || $opt_ctl{t} || 0;

if (@ARGV){
  # additional parameters passed

  if ($ARGV[0] eq "clean") {
    $clean = 1;
  } else {
    # print help and exit program
    help();
  }
}

UVconfig::read_config($cfgfile, 1);  # read config file, redirect errors to log
UVrules::read_rulefile();            # read rules from file

# read list of suspicious mail addresses from file
my @bad_addr = UVconfig::read_badaddr();

# option -t used?
if ($test_only) {
  UVconfig::test_config();
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

# Set columns for Text::Wrap
$columns = $config{rightmargin};

# check for tmp and archive directory
unless (-d $config{archivedir}) {
  mkdir ($config{archivedir}, 0700)
    or die UVmessage::get("ERR_MKDIR", (DIR=>$config{archivedir})) . "$!\n\n";
}

unless (-d $config{tmpdir}) {
  mkdir ($config{tmpdir}, 0700)
    or die UVmessage::get("ERR_MKDIR", (DIR=>$config{tmpdir})) . "$!\n\n";
}

if ($clean) {
  # Program has been startet with "clean" option:
  # save votes and send out acknowledge mails
  make_clean();

} else {
  # normal processing

  # generate file names for result file
  # normally unixtime is sufficient, if it is not unique append our PID
  my $ext = time;

  opendir (TMP, $config{tmpdir});
  my @tmpfiles = readdir (DIR);
  closedir (TMP);
  opendir (FERTIG, $config{archivedir});
  my @fertigfiles = readdir (FERTIG);
  closedir (FERTIG);

  # append PID if necessary
  $ext .= "-$$" if (grep (/$ext/, @tmpfiles) || grep (/$ext/, @fertigfiles));

  my $thisresult = "ergebnis-" . $ext;
  my $thisvotes = "stimmen-" . $ext;
  
  # POP3 not activated: rename votes file
  unless ($config{pop3}) {
    print UVmessage::get("VOTE_RENAMING_MAILBOX"), "\n";
    rename ($config{votefile}, "$config{tmpdir}/$thisvotes")
       or die UVmessage::get("ERR_RENAME_MAILFILE") . "$!\n\n";
  
    #  wait, so that current mail deliveries can finalize
    sleep 2;
  }

  # open results file
  open (RESULT, ">>$config{tmpdir}/$thisresult")
     or die UVmessage::get("VOTE_WRITE_RESULTS", (FILE=>$thisresult)) . "\n\n";

  # read votes and process them
  # for each mail pass a reference to the sub to be called
  my $count = UVreadmail::process("$config{tmpdir}/$thisvotes", \&process_vote, 0);

  close (RESULT)
     or print STDERR UVmessage::get("VOTE_CLOSE_RESULTS", (FILE=>$thisresult)) . "\n";

  # no mails: exit here
  unless ($count) {
    print UVmessage::get("VOTE_NO_VOTES") . "\n\n";
    exit 0;
  }

  if ($config{onestep}) {
    # everything should be done in one step
    print "\n" . UVmessage::get("VOTE_NUM_VOTES", (COUNT=>$count)) . "\n";
    make_clean();

  } else {

    print "\n", UVmessage::get("VOTE_NOT_SAVED", (COUNT=>$count)), "\n",
          wrap('', '', UVmessage::get("VOTE_FIRSTRUN")), "\n\n";
  }
}

exit 0;

END {
  close (STDERR);

  # delete lockfile
  unlink $config{lockfile} if ($config{lockfile});

  if (-s $config{errorfile}) {
    # errors ocurred
    print '*' x $config{rightmargin}, "\n",
          UVmessage::get("VOTE_ERRORS",(FILE => $config{errorfile})), "\n",
          '*' x $config{rightmargin}, "\n\n";
    open (ERRFILE, "<$config{errorfile}");
    print <ERRFILE>;
    close (ERRFILE);
    print "\n";
  } else {
    unlink ($config{errorfile});
  }
}


sub sighandler {
  my ($sig) = @_;
  die "\n\nSIG$sig: deleting lockfile and exiting\n\n";
} 


##############################################################################
# Evaluation of a vote mail                                                  #
# Called from UVreadmail::process() for each mail.                           #
# Parameters: voter address and name, date header of the vote mail (strings) #
#             complete header (reference to array), body (ref. to strings)   #
##############################################################################

sub process_vote {
  my ($voter_addr, $voter_name, $h_date, $entity, $body) = @_;

  my @header = split(/\n/, $entity->stringify_header);
  my $head = $entity->head;
  my $msgid = $head->get('Message-ID');
  chomp($msgid) if ($msgid);

  my @votes = ();              # the votes
  my @set;                     # interactively changed fields
  my @errors = ();             # recognized errors (show menu for manual action)
  my $onevote = 0;             # 0=no votes, 1=everything OK, 2=vote cancelled
  my $voteerror = "";          # error message in case of invalid vote
  my $ballot_id = "";          # ballot id (German: Wahlscheinkennung)

  # found address?
  if ($voter_addr) {
    # search for suspicious addresses
    foreach my $element (@bad_addr) {
      if ($voter_addr =~ /^$element/) {
        push (@errors, 'SuspiciousAccount');
        last;
      }
    }
  } else {
    # found no address in mail (perhaps violates RFC?)
    push (@errors, 'InvalidAddress');
  }

  # personalized ballots?
  if ($config{personal}) {
    if ($$body =~ /$config{ballotidtext}\s+([a-z0-9]+)/) {
      $ballot_id = $1;
      # Address registered? ($ids is set in UVconfig.pm)
      if ($ids{$voter_addr}) {
        push (@errors, 'WrongBallotID') if ($ids{$voter_addr} ne $ballot_id);
      } else {
        push (@errors, 'AddressNotRegistered');
      }
    } else {
      push (@errors, 'NoBallotID');
    }
  }
      
  # evaluate vote strings
  for (my $n=0; $n<@groups; $n++) {

    # counter starts at 1 in ballot
    my $votenum = $n+1;
    my $vote = "";
    
    # a line looks like this: #1 [ VOTE ] Group
    # matching only on number and vote, because of line breaks likely
    # inserted by mail programs

    # duplicate vote?
    if ($$body =~ /#$votenum\W*?\[\s*?(\w+)\s*?\].+?#$votenum\W*?\[\s*?(\w+)\s*?\]/s) {
      push (@errors, "DuplicateVote") if ($1 ne $2);
    }

    # this matches on a single appearance:
    if ($$body =~ /#$votenum\W*?\[(.+)\]/) {
      # one or more vote strings were found
      $onevote = 1;
      my $votestring = $1;
      if ($votestring =~ /^\W*$config{ja_stimme}\W*$/i) {
        $vote = "J";
      } elsif ($votestring =~ /^\W*$config{nein_stimme}\W*$/i) {
        $vote = "N";
      } elsif ($votestring =~ /^\W*$config{enth_stimme}\W*$/i) {
        $vote = "E";
      } elsif ($votestring =~ /^\s*$/) {
        # nothing has been entered between the [ ]
        $vote = "E";
      } elsif ($votestring =~ /^\W*$config{ann_stimme}\W*$/i) {
        $vote = "A";
        $onevote = 2;        # Cancelled vote: set $onevote to 2
      } elsif (!$votes[$n]) {
        # vote not recognized
        $vote = "E";
        push (@errors, 'UnrecognizedVote #' . $votenum . "#$votestring");
      }
      push (@votes, $vote);
    } else {
      # vote not found
      push (@votes, 'E');
      push (@errors, 'UnrecognizedVote #' . $votenum . '#(keine Stimmabgabe fuer "'
           . $groups[$n] . '" gefunden)');
    }
  }

  if ($onevote == 0) {
    push (@errors, "NoVote") unless ($onevote);
  } elsif ($onevote == 1) {
    # check rules
    my $rule = UVrules::rule_check(\@votes);
    push (@errors, "ViolatedRule #$rule") if ($rule);
  } else {
    # cancelled vote: replace all votes with an A
    @votes = split(//, 'A' x scalar @votes);
  }

  # Evaluate Data Protection Law clause (not on cancelled votes)
  if ($config{bdsg} && $onevote<2) {

    # Text in ballot complete and clause accepted?
    # Should read like this: #a [ STIMME ] Text
    # (Text is configurable in usevote.cfg)
    unless ($$body =~ /$bdsg_regexp/s &&
            $$body =~ /#a\W*?\[\W*?$config{ja_stimme}\W*?\]\W*?$bdsg2_regexp/is) {

      push (@errors, 'InvalidBDSG');
    }
  }

  # Name in body?
  if ($$body =~ /($config{nametext}|$config{nametext2})( |\t)*(\S.+?)$/m) {
    $voter_name = $3;
    $voter_name =~ s/^\s+//; # strip leading spaces
    $voter_name =~ s/\s+$//; # strip trailing spaces
  }

  if ($voter_name) {
    # Name invalid?
    push (@errors, 'InvalidName') unless ($voter_name =~ /$config{name_re}/);
  } else {
    # no name found:
    push (@errors, 'NoName') unless ($voter_name);
  }

  # Errors encountered?
  if (@errors) {
    my $res = UVmenu::menu(\@votes, \@header, $body, \$voter_addr, \$voter_name,
                           \$ballot_id, \@set, \@errors);
    return 0 if ($res eq 'i');      # "Ignore": Ignore vote, don't save

    my $tpl;

    # Check Ballot ID stuff
    if ($config{personal}) {
      if ($ballot_id) {
        if ($ids{$voter_addr}) {
          if ($ids{$voter_addr} ne $ballot_id) {
            $voteerror = UVmessage::get("VOTE_INVALID_BALLOTID");
            $tpl = $config{tpl_wrong_ballotid};
          }
        } else {
          $voteerror = UVmessage::get("VOTE_UNREGISTERED_ADDRESS");
          $tpl = $config{tpl_addr_reg};
        }
      } else {
        $voteerror = UVmessage::get("VOTE_MISSING_BALLOTID");
        $tpl = $config{tpl_no_ballotid};
      }
  
      # generate error mail (if error occurred)
      if ($tpl) {
        my $template = UVtemplate->new();
        $template->setKey('head' => $entity->stringify_header);
        $template->setKey('body' => $$body);
        my $msg = $template->processTemplate($tpl);
        UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
      }
    }
  }
  
  # Check rules and send error mail unless rule violation was ignored in the use menu
  # or another error was detected
  if (grep(/ViolatedRule/, @errors) && !$voteerror && (my $rule = UVrules::rule_check(\@votes))) {
    $voteerror = UVmessage::get("VOTE_VIOLATED_RULE", (RULE=>$rule));
    my $template = UVtemplate->new();
    $template->setKey('body'  => $$body);
    $template->setKey('rules' => UVrules::rule_print($rule-1));
    my $msg = $template->processTemplate($config{tpl_rule_violated});
    UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
  }

  if (!$voteerror && @errors) {

    # turn errors array into hash

    my %error;
    foreach my $error (@errors) {
      $error{$error} = 1;
    }

    # Check uncorrected errors
    if ($error{InvalidBDSG}) {
      my $template = UVtemplate->new();
      my $msg = $template->processTemplate($config{tpl_bdsg_error});
      UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
      return 0;
    } elsif ($error{NoVote}) {
      $voteerror = UVmessage::get("VOTE_NO_VOTES");
      my $template = UVtemplate->new();
      $template->setKey('body'  => $$body);
      my $msg = $template->processTemplate($config{tpl_no_votes});
      UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
    } elsif ($error{SuspiciousAccount}) {
      $voteerror = UVmessage::get("VOTE_INVALID_ACCOUNT");
      my $template = UVtemplate->new();
      $template->setKey('head' => $entity->stringify_header);
      $template->setKey('body'  => $$body);
      my $msg = $template->processTemplate($config{tpl_invalid_account});
      UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
    } elsif ($error{InvalidAddress}) {
      $voteerror = UVmessage::get("VOTE_INVALID_ADDRESS");
    } elsif ($error{InvalidName}) {
      $voteerror = UVmessage::get("VOTE_INVALID_REALNAME");
      my $template = UVtemplate->new();
      $template->setKey('head' => $entity->stringify_header);
      $template->setKey('body'  => $$body);
      my $msg = $template->processTemplate($config{tpl_invalid_name});
      UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
    } elsif ($error{DuplicateVote}) {
      $voteerror = UVmessage::get("VOTE_DUPLICATES");
      my $template = UVtemplate->new();
      $template->setKey('head' => $entity->stringify_header);
      $template->setKey('body'  => $$body);
      my $msg = $template->processTemplate($config{tpl_multiple_votes});
      UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
    }
  }

  # check voter name
  unless ($voter_name || $voteerror) {
    $voteerror = UVmessage::get("VOTE_MISSING_NAME");
    my $template = UVtemplate->new();
    $template->setKey('head' => $entity->stringify_header);
    $template->setKey('body'  => $$body);
    my $msg = $template->processTemplate($config{tpl_invalid_name});
    UVsendmail::mail($voter_addr, "Fehler", $msg, $msgid) if ($config{voteack});
  }

  # set mark for cancelled vote
  $onevote = 2 if ($votes[0] eq 'A');

  # create comment line for result file
  my $comment;
  if ($config{personal}) {
    # Personalized Ballots: insert ballot id
    $comment = "($ballot_id)";
  } else {
    $comment = "()";
  }

  if (@set) {
    $comment .= ' '.UVmessage::get("VOTE_FILE_COMMENT", (FIELDS => join(', ', @set)));
  }

  # write result file
  print RESULT "A: $voter_addr\n";
  print RESULT "N: $voter_name\n";
  print RESULT "D: $h_date\n";
  print RESULT "K: $comment\n";

  # invalid vote?
  if ($voteerror) {
    print RESULT "S: ! $voteerror\n";

  # cancelled vote?
  } elsif ($onevote == 2) {
    print RESULT "S: * Annulliert\n";

    if ($config{voteack}) {
      # send cancellation acknowledge
      my $template = UVtemplate->new();
      my $msg = $template->processTemplate($config{tpl_cancelled});
      UVsendmail::mail($voter_addr, "Bestaetigung", $msg, $msgid);
    }

  } else {
    print RESULT "S: ", join ("", @votes), "\n";

    # send acknowledge mail?
    if ($config{voteack}) {

      my $template = UVtemplate->new();
      $template->setKey(ballotid        => $ballot_id);
      $template->setKey(address         => $voter_addr);
      $template->setKey(name            => $voter_name);

      for (my $n=0; $n<@groups; $n++) {
        my $vote = $votes[$n];
        $vote =~ s/^J$/JA/;
        $vote =~ s/^N$/NEIN/;
        $vote =~ s/^E$/ENTHALTUNG/;
        $template->addListItem('groups', pos=>$n+1, vote=>$vote, group=>$groups[$n]);
      }
   
      my $msg = $template->processTemplate($config{'tpl_ack_mail'});
      UVsendmail::mail($voter_addr, "Bestaetigung", $msg, $msgid);
    }
  }
}


##############################################################################
# Send out acknowledge mails and tidy up (we're called as "uvvote.pl clean") #
##############################################################################

sub make_clean {

  # send mails
  UVsendmail::send();

  print UVmessage::get("INFO_TIDY_UP"), "\n";

  # search unprocessed files
  opendir (DIR, $config{tmpdir});
  my @files = readdir DIR;
  closedir (DIR);

  my @resultfiles = grep (/^ergebnis-/, @files);
  my @votefiles = grep (/^stimmen-/, @files);

  unless (@resultfiles) {
    print wrap('', '', UVmessage::get("VOTE_NO_NEW_RESULTS")), "\n\n";
    return 0;
  }   

  foreach my $thisresult (@resultfiles) {
    chmod (0400, "$config{tmpdir}/$thisresult");
    rename "$config{tmpdir}/$thisresult", "$config{archivedir}/$thisresult"
      or die UVmessage::get("VOTE_MOVE_RESULTFILE", (FILE=>$thisresult)) . "$!\n\n";
  }

  foreach my $thisvotes (@votefiles) {
    chmod (0400, "$config{tmpdir}/$thisvotes");
    rename "$config{tmpdir}/$thisvotes", "$config{archivedir}/$thisvotes"
      or die UVmessage::get("VOTE_MOVE_VOTEFILE", (FILE=>$thisvotes)) . "$!\n\n";
  }

  print UVmessage::get("VOTE_CREATING_RESULTS", (FILENAME=>$config{resultfile})), "\n";

  # search all result files
  opendir (DIR, "$config{archivedir}/");
  @files = grep (/^ergebnis-/, readdir (DIR));
  closedir (DIR);

  # Create complete result from all single result files.
  # The resulting file (ergebnis.alle) is overwritten as there could have been
  # made changes in the single result files
  open(RESULT, ">$config{resultfile}");
  foreach my $file (sort @files) {
    open(THISRESULT, "<$config{archivedir}/$file");
    print RESULT join('', <THISRESULT>);
    close(THISRESULT);
  }
  close(RESULT);

  print "\n";

}


##############################################################################
# Print help text (options and syntax) on -h or --help                       #
##############################################################################

sub help {
  print <<EOF;
Usage: uvvote.pl [-c config_file] [-t]
       uvvote.pl [-c config_file] clean
       uvvote.pl -h

Liest Mailboxen aus einer Datei oder per POP3 ein wertet die Mails
als Stimmzettel aus. Erst beim Aufruf mit der Option "clean" werden
die Ergebnisse endgueltig gespeichert und die Bestaetigungsmails
verschickt.

  -c config_file   liest die Konfiguration aus config_file
                   (usevote.cfg falls nicht angegeben)

  -t, --test       fuehrt einen Test der Konfiguration durch und
                   gibt das ermittelte Ergebnis aus.

  -h, --help       zeigt diesen Hilfetext an

EOF

  exit 0;
}
