#!/usr/bin/perl -w

###############################################################################
# UseVoteGer 4.12 Stimmauswertung
# (c) 2001-2014 Marc Langer <uv@marclanger.de>
# 
# This script package is free software; you can redistribute it and/or
# modify it under the terms of the GNU Public License as published by the
# Free Software Foundation.
#
# Use this script to create voter lists and results.
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
use Date::Parse;
use FindBin qw($Bin);
use lib $Bin;
use UVconfig;
use UVmenu;
use UVmessage;
use UVtemplate;

my %opt_ctl = ();

print STDERR "\n$usevote_version Stimmauswertung - (c) 2001-2005 Marc Langer\n\n";

# unrecognized parameters remain in @ARGV (for "help")
Getopt::Long::Configure(qw(pass_through bundling));

# recognized parameters are written into %opt_ctl
GetOptions(\%opt_ctl, qw(l|list v|voters r|result n|nodup m|multigroup o|onegroup c|config-file=s f|result-file=s));

if (!$opt_ctl{r} && ($opt_ctl{m} || $opt_ctl{o})) {
  print STDERR "Die Optionen -m bzw. -o koennen nur in Verbindung mit -r verwendet werden!\n\n";
  help(); # show help and exit
} elsif (@ARGV || !($opt_ctl{l} || $opt_ctl{v} || $opt_ctl{r})) {
  # additional parameters passed
  help(); # show help and exit
} elsif ($opt_ctl{l} && $opt_ctl{v}) {
  print STDERR "Die Optionen -l und -v duerfen nicht zusammen verwendet werden!\n\n";
  help(); # show help and exit
} elsif ($opt_ctl{m} && $opt_ctl{o}) {
  print STDERR "Die Optionen -m und -o duerfen nicht zusammen verwendet werden!\n\n";
  help(); # show help and exit
}

# get config file name (default: usevote.cfg) and read it
my $cfgfile   = $opt_ctl{c} || "usevote.cfg";
UVconfig::read_config($cfgfile);

# Overwrite result file if started with option -f
$config{resultfile} = $opt_ctl{f} if ($opt_ctl{f});

read_resultfile($opt_ctl{n});

exit 0;


##############################################################################
# Read result file and (optionally) sort out duplicate votes                 #
# Parameters: 1 if no duplicates should be deleted, else 0                   #
##############################################################################

sub read_resultfile {
  my ($nodup) = @_;
  my $num = 0;
  my $invalid = '';
  my $inv_count = 0;
  my $validcount = 0;
  my $vote = {};
  my @votes = ();
  my @deleted = ();
  my @votecount = ();
  my %vnames = ();
  my %vaddr = ();
  my %lists = (J => '', N => '', E => '');     # for one-group format
  my $list = '';                               # for multiple-group format
  my %varname = (J => 'yes', N => 'no', E => 'abstain');

  # Initialization of the sum array
  for (my $group=0; $group<@groups; $group++) {
    $votecount[$group]->{J} = 0;
    $votecount[$group]->{N} = 0;
    $votecount[$group]->{E} = 0;
  }

  open(FILE, "<$config{resultfile}")
    or die UVmessage::get("COUNT_ERR_OPEN", (FILE=>$config{resultfile})) . "\n\n";

  # Read file
  while(<FILE>) {
    chomp;
    $num++;

    unless (/^(\w): (.*)$/) {
      print STDERR UVmessage::get("COUNT_ERR_RESULT",
                                  (FILE=>$config{resultfile}, LINE=>$num)) . "\n";
      next;
    }

    my $field = $1;
    my $content = $2;
    $vote->{$field} = $content;

    # End of a paragraph reached?
    if ($field eq 'S') {

      # The array @votes countains references to the hashes
      push (@votes, $vote);

      # For sorting and duplicate detection indexes are build from address and name.
      # These are hashes containing references to an array of index numbers of
      # the @votes array.
      #
      # Example: $vnames{'marc langer'}->[0] = 2
      #          $vnames{'marc langer'}->[1] = 10
      # Meaning: $votes[2] und $votes[10] contain votes of Marc Langer

      push (@{$vnames{lc($vote->{N})}}, $#votes);

      # Conversion in lower case, so that words with an upper case first
      # letter are not at the top after sorting
      push (@{$vaddr{lc($vote->{A})}}, $#votes);

      # reset $vote, begin a new vote
      $vote = {};
    }
  }    

  close(FILE);

  # delete cancelled votes
  foreach my $addr (keys %vaddr) {
    # Run through all votes belonging to a mail address and search for cancellation
    for (my $n=0; $n<=$#{$vaddr{$addr}}; $n++) {
      if ($votes[$vaddr{$addr}->[$n]]->{S} =~ /^\*/) {
        # delete from array
        push(@deleted, splice(@{$vaddr{$addr}}, 0, $n+1));
        $n=-1;
      }
    }
  }

  # sort out duplicates?
  unless ($nodup) {

    # search for duplicate addresses
    foreach my $addr (keys %vaddr) {

      # Run through all votes belonging to a mail address.
      # If one vote is deleted it has also to be deleted from the array
      # so that the following addresses move up. In the other case the
      # counter is incremented as long as further votes are to be compared.

      my $n=0;
      while ($n<$#{$vaddr{$addr}}) {

        my $ask = 0;

        if ($votes[$vaddr{$addr}->[$n]]->{S} =~ /!/ ||
            $votes[$vaddr{$addr}->[$n+1]]->{S} =~ /!/)  {

          # One of the votes is invalid: Ask votetaker
          $ask = 1;

        } else {

          # Convert date into unixtime (str2time is located in Date::Parse)
          my $date1 = str2time($votes[$vaddr{$addr}->[$n]]->{D});
          my $date2 = str2time($votes[$vaddr{$addr}->[$n+1]]->{D});

          # compare dates
          my $order = $date1 <=> $date2;

          # first date is earlier
          if ($order == -1) {
            push(@deleted, $vaddr{$addr}->[$n]);
            # delete first element from the array
            splice(@{$vaddr{$addr}}, $n, 1);

          # second date is earlier
          } elsif ($order == 1) {
            push(@deleted, $vaddr{$addr}->[$n+1]);
            # delete second element from the array
            splice(@{$vaddr{$addr}}, $n+1, 1);

          # both are equal (ask votetaker)
          } else {
            $ask = 1;
          }

        }

        # Has votetaker to be asked?
        if ($ask) {
          my $default = 0;
          my $res = UVmenu::dup_choice($votes[$vaddr{$addr}->[0]],
                                       $votes[$vaddr{$addr}->[1]],
                                       $default);

          if ($res == 1) {
            push(@deleted, $vaddr{$addr}->[0]);
            # delete first element from the array
            splice(@{$vaddr{$addr}}, $n, 1);

          } elsif ($res == 2) {
            push(@deleted, $vaddr{$addr}->[1]);
            # delete second element from the array
            splice(@{$vaddr{$addr}}, $n+1, 1);

          } else {
            # don't delete anything: increment counter
            $n++;
          }
        }
      }
    }

    # the same for equal names:
    foreach my $name (keys %vnames) {
      my $n = 0;
      while ($n<$#{$vnames{$name}}) {

        # check if vote was already deleted by prior address sorting
        if (grep(/^$vnames{$name}->[$n]$/, @deleted)) {
          # delete first element from the array
          splice(@{$vnames{$name}}, $n, 1);
          next;

        } elsif (grep(/^$vnames{$name}->[$n+1]$/, @deleted)) {
          # delete second element from the array
          splice(@{$vnames{$name}}, $n+1, 1);
          next;
        }

        # Convert date into unixtime (str2time is located in Date::Parse)
        my $date1 = str2time($votes[$vnames{$name}->[$n]]->{D});
        my $date2 = str2time($votes[$vnames{$name}->[$n+1]]->{D});

        # Set default for menu choice to the earlier vote
        my $default = ($date2 < $date1) ? 2 : 0;

        my $res = UVmenu::dup_choice($votes[$vnames{$name}->[$n]],
                                     $votes[$vnames{$name}->[$n+1]],
                                     $default);

        # delete first
        if ($res == 1) {
          push(@deleted, $vnames{$name}->[$n]);
          splice(@{$vnames{$name}}, $n, 1);

        # delete second
        } elsif ($res == 2) {
          push(@deleted, $vnames{$name}->[$n+1]);
          # delete second element from the array
          splice(@{$vnames{$name}}, $n+1, 1);
       
        # don't delete anything: increment counter
        } else {
          $n++;
        }
      }
    }

    print STDERR UVmessage::get("COUNT_DELETED", (NUM=>scalar @deleted)), "\n\n";
  }

  # Count votes and generate voter list
  
  my $list_tpl = UVtemplate->new();
  $list_tpl->setKey('groupcount' => scalar @groups);

  # reversed order as caption string for last column comes first
  for (my $n=$#groups; $n>=0; $n--) {
    $list_tpl->addListItem('groups', pos=>@groups-$n, group=>$groups[$n]);
  }
   
  # loop through all addresses
  foreach my $addr (sort keys %vaddr) {

    # loop through all votes for every address
    for (my $n=0; $n<@{$vaddr{$addr}}; $n++) {

      # Ignore vote if already deleted.
      # If $nodup is not set one single vote should remain
      unless (grep(/^$vaddr{$addr}->[$n]$/, @deleted)) {

        # extract $vote for simplier code
        my $vote = $votes[$vaddr{$addr}->[$n]];

        # vote is invalid if there is an exclamation mark
        if ($vote->{S} =~ /!/) {
          $inv_count++;
        } else {
          # split vote string into single votes and count
          my @splitvote = split(//, $vote->{S});
          if (@groups != @splitvote) {
            die UVmessage::get("COUNT_ERR_GROUPCOUNT", (ADDR=>$addr, NUM1=>scalar @splitvote,
                      NUM2=>scalar @groups), RESULTFILE=>$config{resultfile}), "\n\n";
          }
          for (my $group=0; $group<@splitvote; $group++) {
            $votecount[$group]->{$splitvote[$group]}++;
          }
          $validcount++;
        }

        if ($opt_ctl{l} || $opt_ctl{v}) {

          # vote is invalid if there is an exclamation mark
          if ($vote->{S} =~ /!/) {
            $list_tpl->addListItem('invalid', (name=>$vote->{N}, mail=>$vote->{A}, reason=>$vote->{S}));

          # in other cases the vote is valid: generate list of votes
          } else {

            # one-group or multiple-group format?
            # must use multiple-group data structure for voter list (2. CfV)!
            if ($#groups || $opt_ctl{l}) {
              $list_tpl->addListItem('multi', (name=>$vote->{N}, mail=>$vote->{A}, vote=>$vote->{S}));
            } else {
              my ($votestring) = split(//, $vote->{S});
              $list_tpl->addListItem($varname{$votestring}, (name=>$vote->{N}, mail=>$vote->{A}));
            }

          }
        }
      }
    }
  }

  if ($opt_ctl{r}) {

    my $tplname;
    my $result_tpl = UVtemplate->new();
    $result_tpl->setKey('votename' => $config{votename});
    $result_tpl->setKey('numvalid' => $validcount);
    $result_tpl->setKey ('numinvalid', $inv_count);

    # proportional vote?
    if ($config{proportional}) {
      $tplname = $config{'tpl_result_prop'};
      for (my $group=0; $group<@votecount; $group++) {
        # calculate conditions
        my $yes = $votecount[$group]->{J};
        my $no = $votecount[$group]->{N};
        my $cond1 = eval $config{condition1};
        my $proportion = 0;

        # don't evaluate if division by zero
        unless ($config{prop_formula} =~ m#.+/(.+)# && eval($1)==0) {
          $proportion = eval $config{prop_formula};
        }
  
        # generate result line
        $result_tpl->addListItem('count', (yes        => $votecount[$group]->{J},
                                           no         => $votecount[$group]->{N},
                                           cond1      => $cond1,
                                           proportion => $proportion,
                                           result     => '', # must be set manually
                                           group      => $groups[$group]));
      }

    } else {
      # use one-group or multiple-group format?
      if (@groups == 1 && (!($config{multigroup} || $opt_ctl{m}) || $opt_ctl{o})) {
        $tplname = $config{'tpl_result_single'};
        my $yes = $votecount[0]->{J};
        my $no = $votecount[0]->{N};
        my $acc1 = eval $config{condition1};
        my $acc2 = eval $config{condition2};
        $result_tpl->setKey('yes' => $votecount[0]->{J});
        $result_tpl->setKey('no' => $votecount[0]->{N});
        $result_tpl->setKey('numabstain' => $votecount[0]->{E});
        $result_tpl->setKey('cond1' => $acc1);
        $result_tpl->setKey('cond2' => $acc2);

      } else {
        $tplname = $config{'tpl_result_multi'};
        $result_tpl->setKey('numabstain' => 0);

        for (my $group=0; $group<@votecount; $group++) {
          # calculate conditions
          my $yes = $votecount[$group]->{J};
          my $no = $votecount[$group]->{N};
          my $cond1 = eval $config{condition1};
          my $cond2 = eval $config{condition2};
  
          # generate result line
          $result_tpl->addListItem('count', (yes    => $votecount[$group]->{J},
                                             no     => $votecount[$group]->{N},
                                             cond1  => $cond1,
                                             cond2  => $cond2,
                                             result => ($cond1 && $cond2),
                                             group  => $groups[$group]));

        }
      }

      $result_tpl->setKey ('numabstain', $votecount[0]->{E}) if (@votecount == 1);
    }

    print $result_tpl->processTemplate($tplname);

  }

  if ($opt_ctl{v}) {

    # one-group or multiple-group format?
    if ($#groups) {
      print $list_tpl->processTemplate($config{'tpl_votes_multi'});
    } else {
      print $list_tpl->processTemplate($config{'tpl_votes_single'});
    }

  } elsif ($opt_ctl{l}) {
    print $list_tpl->processTemplate($config{'tpl_voterlist'});
  }

}


##############################################################################
# Print help text (options and syntax) on -h or --help                       #
##############################################################################

sub help {
  print STDERR <<EOF;
Usage: uvcount.pl [-c config_file] [-f result_file] [-l | -v] [-r [-m | -o]] [-n]
       uvcount.pl -h

Zaehlt Stimmen und gibt Waehlerlisten aus.

  -c config_file   liest die Konfiguration aus config_file
                   (usevote.cfg falls nicht angegeben)

  -f result_file   liest die Stimmen aus result_file (ueberschreibt
                   die "resultfile"-Angabe aus der Konfigurationsdatei)

  -l, --list       Gibt eine Liste aller Waehler aus (ohne Stimmen).

  -v, --voters     Wie -l, aber mit Angabe der abgegebenen Stimmen.

  -r, --result     Ausgabe des Endergebnisses (kann mit -l oder -v
                   kombiniert werden).

  -m, --multigroup Benutzt auch bei Eingruppenabstimmungen das
                   Mehrgruppenformat beim Endergebnis (ueberschreibt
                   die Einstellung aus usevote.cfg).
                   Nur in Kombination mit -r verwendbar, schliesst -o aus.

  -o, --onegroup   Benutzt bei Eingruppenabstimmungen immer das
                   Eingruppenformat beim Endergebnis (ueberschreibt
                   die Einstellung aus usevote.cfg).
                   Nur in Kombination mit -r verwendbar, schliesst -m aus.

  -n, --nodup      Verzichtet auf das Aussortieren von doppelten
                   Stimmabgaben. Nicht empfohlen!

  -h, --help       zeigt diesen Hilfetext an

EOF

  exit 0;
}
