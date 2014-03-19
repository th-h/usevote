# UVmenu: menu for interaction with the votetaker
# Used by uvvote.pl, uvcfv.pl, uvcount.pl
 
package UVmenu;
 
use strict;
use UVconfig;
use UVmessage;
use UVrules;
use vars qw($VERSION);

use Text::Wrap qw(wrap $columns);
 
# Module version
$VERSION = "0.4";

##############################################################################
# Menu for interaction with the votetaker                                    #
# Parameters: votes list and header (references to arrays)                   #
#             Body, Mailadress, Name, Ballot ID,                             #
#             Voting (references to strings)                                 #
#             List of newly set fields (reference to array)                  #
#             List of errors to correct (Array-Ref)                          #
# Return Values: 'w': proceed                                                #
#                'i': ignore (don't save vote)                               #
##############################################################################

sub menu {
  my ($votes, $header, $body, $addr, $name, $ballot_id, $voting, $set, $errors) = @_;
  my $input = "";
  my $voter_addr = $$addr || '';
  my $voter_name = $$name || '';
  my @newvotes = @$votes;
  my $mailonly = 0;
  my %errors;
  $$ballot_id ||= '';

  foreach my $error (@$errors) {

    # unrecognized vote: extract group number und display warning
    if ($error =~ /^UnrecognizedVote #(\d+)#(.+)$/) {
      $errors{UnrecognizedVote} ||= UVmessage::get("MENU_UNRECOGNIZEDVOTE");
      $errors{UnrecognizedVote} .= "\n  " . UVmessage::get("MENU_UNRECOGNIZED_LIST")
                                          . " #$1: $2";

    # violated rule: extract rule number and display warning
    } elsif ($error =~ /^ViolatedRule #(\d+)$/) {
      $errors{ViolatedRule} ||= UVmessage::get("MENU_VIOLATEDRULE", (RULE => "#$1"));

    } else {
      # special handling if called from uvballot.pl
      $mailonly = 1 if ($error =~ s/Ballot$//);

      # get error message for this error from messages.cfg
      $errors{$error} = UVmessage::get("MENU_" . uc($error));
    }
  }

  # This loop is only left by 'return'
  while (1) {

    system($config{clearcmd});
    print "-> $config{votename} <-\n";
    print UVmessage::get("MENU_PROBLEMS") . "\n";

    foreach my $error (keys %errors) {
      print "* $errors{$error}\n";
    }

    my $menucaption = UVmessage::get("MENU_CAPTION");
    print "\n\n$menucaption\n";
    print "=" x length($menucaption), "\n\n";

    # don't print this option if called from uvcfv.pl
    unless ($mailonly) {
      print "(0) ", UVmessage::get("MENU_DIFF_BALLOT"), "\n";
    }

    print "(1) ", UVmessage::get("MENU_SHOW_MAIL"), "\n\n",
          UVmessage::get("MENU_CHANGE_PROPERTIES"), "\n",
          "(2) ", UVmessage::get("MENU_ADDRESS"), " [$voter_addr]\n";

    # don't print these options if called from uvcfv.pl
    unless ($mailonly) {
      print "(3) ", UVmessage::get("MENU_NAME"), " [$voter_name]\n";
      print "(4) ", UVmessage::get("MENU_VOTES"), " [", @$votes, "]\n";
      print "(5) ", UVmessage::get("MENU_BALLOT_ID"), " [$$ballot_id]\n"
        if ($config{personal});
      print "(6) ", UVmessage::get("MENU_BDSG"), "\n" if ($config{bdsg});
      print "(7) ", UVmessage::get("MENU_VOTING"), " [", $$voting, "]\n";
    }

    print "\n",
          "(i) ", UVmessage::get("MENU_IGNORE"), "\n",
          "(w) ", UVmessage::get("MENU_PROCEED"), "\n\n",
          UVmessage::get("MENU_PROMPT");

    do { $input = <STDIN>; } until ($input);
    chomp $input;
    print "\n";

    # only accept 1, 2, i and w if called from uvcfv.pl
    next if ($mailonly && $input !~ /^[12iw]$/i);

    if ($input eq '0') {
      # ignore SIGPIPE (Bug in more and less)
      $SIG{PIPE} = 'IGNORE';
      open (DIFF, "|$config{diff} - $config{sampleballotfile} | $config{pager}");
      print DIFF $$body, "\n";
      close (DIFF);

    } elsif ($input eq '1') {
      system($config{clearcmd});
      # ignore SIGPIPE (Bug in more and less)
      $SIG{PIPE} = 'IGNORE';
      open (MORE, "|$config{pager}");
      print MORE join("\n", @$header), "\n\n", $$body, "\n";
      close (MORE);
      
      print "\n", UVmessage::get("MENU_GETKEY");
      $input = <STDIN>;

    } elsif ($input eq '2') {
      my $sel;
      do {
        print "[a] ", UVmessage::get("MENU_ADDRESS_OK"), "\n",
              "[b] ", UVmessage::get("MENU_ADDRESS_CHANGE"), "\n",
              "[c] ", UVmessage::get("MENU_ADDRESS_INVALID"), "\n\n",
              UVmessage::get("MENU_PROMPT");
        $sel = <STDIN>;
      } until ($sel =~ /^[abc]$/i);
      if ($sel =~ /^a$/i) {
        delete $errors{SuspiciousAccount};
        delete $errors{InvalidAddress};
        next;
      } elsif ($sel =~ /^c$/i) {
        delete $errors{SuspiciousAccount};
        $errors{InvalidAddress} = UVmessage::get("MENU_INVALIDADDRESS") . " " .
                                  UVmessage::get("MENU_INVALIDADDRESS2");
        next;
      }
        
      do {
        print "\n", UVmessage::get("MENU_ADDRESS_PROMPT"), " ";
        $voter_addr = <STDIN>;
        chomp ($voter_addr);
      } until ($voter_addr);
      $$addr = $voter_addr;
      push (@$set, 'Adresse');
      delete $errors{SuspiciousAccount};
      delete $errors{InvalidAddress};
      check_ballotid(\%errors, \$voter_addr, $ballot_id, \%ids);

    } elsif ($input eq '3') {
      my $sel;
      do {
        print "[a] ", UVmessage::get("MENU_NAME_OK"), "\n",
              "[b] ", UVmessage::get("MENU_NAME_CHANGE"), "\n",
              "[c] ", UVmessage::get("MENU_NAME_INVALID"), "\n\n",
              UVmessage::get("MENU_PROMPT");
        $sel = <STDIN>;
      } until ($sel =~ /^[abc]$/i);
      if ($sel =~ /^a$/i) {
        delete $errors{InvalidName};
        next;
      } elsif ($sel =~ /^c$/i) {
        $errors{InvalidName} = UVmessage::get("MENU_INVALIDNAME");
        next;
      }
      print UVmessage::get("MENU_NAME"), ": ";
      $voter_name = <STDIN>;
      chomp ($voter_name);
      $$name = $voter_name;
      push (@$set, 'Name');
      delete $errors{NoName};
      delete $errors{InvalidName};

      $errors{InvalidName} = UVmessage::get("MENU_INVALIDNAME")
        unless ($voter_name =~ /$config{name_re}/);
 
    } elsif ($input eq '4') {
      # set votes

      my $sel;
      do {
        print "[a] ", UVmessage::get("MENU_VOTES_OK"), "\n",
              "[b] ", UVmessage::get("MENU_VOTES_RESET"), "\n",
              "[c] ", UVmessage::get("MENU_VOTES_INVALID"), "\n",
              "[d] ", UVmessage::get("MENU_VOTES_CANCELLED"), "\n\n",
              UVmessage::get("MENU_PROMPT");
        $sel = <STDIN>;
      } until ($sel =~ /^[abcd]$/i);
      if ($sel =~ /^[ad]$/i) {
        delete $errors{NoVote};
        delete $errors{UnrecognizedVote};
        delete $errors{ViolatedRule};
        delete $errors{DuplicateVote};
        if ($sel =~ /^d$/i) {
          # cancelled vote: replace all votes with an A
          @$votes = split(//, 'A' x scalar @groups);
          push @$set, 'Stimmen';
          # some errors are irrelevant when cancelling a vote:
          delete $errors{InvalidName};
          delete $errors{NoName};
          delete $errors{InvalidBDSG};
          delete $errors{InvalidAddress};
          delete $errors{SuspiciousAccount};
        }
        next;
      } elsif ($sel =~ /^c$/i) {
        $errors{NoVote} = UVmessage::get("MENU_INVALIDVOTE");
        next;
      }

      # Set columns for Text::Wrap
      $columns = $config{rightmargin};
      print "\n", wrap('', '', UVmessage::get("MENU_VOTES_REENTER_ASK")), "\n\n";
      print UVmessage::get("MENU_VOTES_REENTER_LEGEND"), "\n";

      for (my $n=0; $n<@groups; $n++) {
        my $voteinput = "";
        $votes->[$n] ||= 'E';

        # repeat while invalid character entered
        while (!($voteinput =~ /^[JNE]$/)) {
          my $invalid = $#groups ? 0 : 1;
          print UVmessage::get("MENU_VOTES_REENTER", (GROUP => $groups[$n]));
          $voteinput = <STDIN>;
          chomp $voteinput;
          $voteinput ||= $votes->[$n];
          $voteinput =~ tr/jne/JNE/;
        }
        
        # valid input, save new votes
        $newvotes[$n] = $voteinput;
      } 

      print "\n\n";
      my $oldvotes = UVmessage::get("MENU_VOTES_REENTER_OLD");
      my $newvotes = UVmessage::get("MENU_VOTES_REENTER_NEW");
      my $oldlen = length($oldvotes);
      my $newlen = length($newvotes);
      my $maxlen = 1 + (($newlen>$oldlen) ? $newlen : $oldlen);
      print $oldvotes, ' ' x ($maxlen - length($oldvotes)), @$votes, "\n",
            $newvotes, ' ' x ($maxlen - length($newvotes)), @newvotes, "\n\n";

      do {
        print "[a] ", UVmessage::get("MENU_VOTES_REENTER_ACK"), "    ",
              "[b] ", UVmessage::get("MENU_VOTES_REENTER_NACK"), "\n\n", 
               UVmessage::get("MENU_PROMPT");
        $sel = <STDIN>;
      } until ($sel =~ /^[ab]$/i);

      next if ($sel =~ /^b$/i);
      @$votes = @newvotes;
      push @$set, 'Stimmen';
      delete $errors{UnrecognizedVote};
      delete $errors{DuplicateVote};
      delete $errors{NoVote};
      delete $errors{ViolatedRule};

      if (my $rule = UVrules::rule_check($votes)) {
        $errors{ViolatedRule} = UVmessage::get("MENU_VIOLATEDRULE", (RULE => "#$rule"));
      }

    } elsif ($input eq '5' && $config{personal}) {
      print "\n", UVmessage::get("MENU_BALLOT_ID"), ": ";
      $$ballot_id = <STDIN>;
      chomp ($$ballot_id);
      push (@$set, 'Kennung');
      check_ballotid(\%errors, \$voter_addr, $ballot_id, \%ids);

    } elsif ($input eq '6' && $config{bdsg}) {
      my $sel;
      do {
        print "[a] ", UVmessage::get("MENU_BDSG_ACCEPTED"), "\n",
              "[b] ", UVmessage::get("MENU_BDSG_DECLINED"), "\n\n",
              UVmessage::get("MENU_PROMPT");
        $sel = <STDIN>;
      } until ($sel =~ /^[ab]$/i);

      if ($sel =~ /^a$/i) {
        delete $errors{InvalidBDSG};
      } else {
        $errors{InvalidBDSG} = UVmessage::get("MENU_INVALIDBDSG");
      }

    } elsif ($input eq '7') {
      my $sel;
      do {
        print "[a] ", UVmessage::get("MENU_VOTING_CORRECT"), "\n",
              "[b] ", UVmessage::get("MENU_VOTING_WRONG"), "\n\n",
              UVmessage::get("MENU_PROMPT");
        $sel = <STDIN>;
      } until ($sel =~ /^[ab]$/i);

      if ($sel =~ /^a$/i) {
        delete $errors{NoVoting};
        delete $errors{WrongVoting};
      } else {
        $errors{WrongVoting} = UVmessage::get("MENU_WRONGVOTING");
      }

    } elsif ($input =~ /^i$/i) {
      my $ignore = UVmessage::get("MENU_IGNORE_STRING");
      # Set columns for Text::Wrap
      $columns = $config{rightmargin};
      print wrap('', '', UVmessage::get("MENU_IGNORE_WARNING",
                                        (MENU_IGNORE_STRING => $ignore)
                                       ));
      if (<STDIN> eq "$ignore\n") {
        print "\n";
        return "i";
      }

    } elsif ($input =~ /^w$/i) {

      if (keys %errors) {
        if ((keys %errors)==1 && $errors{UnrecognizedVote}) {
          # unrecognized vote lines aren't errors if votetaker
          # did not change them
          @$errors = ();
        } else {
          # Set columns for Text::Wrap
          $columns = $config{rightmargin};
          @$errors = keys %errors;
          my $warning = ' ' . UVmessage::get("MENU_ERROR_WARNING") . ' ';
          my $length = length($warning);
          print "\n", '*' x (($config{rightmargin}-$length)/2), $warning,
                '*' x (($config{rightmargin}-$length)/2), "\n\n",
                wrap('', '', UVmessage::get("MENU_ERROR_TEXT")), "\n\n",
                '*' x $config{rightmargin}, "\n\n",
                UVmessage::get("MENU_ERROR_GETKEY");
          my $input = <STDIN>;
          next if ($input !~ /^y$/i);
          print "\n";
        }
      } else {
        @$errors = ();
      }
 
      system($config{clearcmd});
      print "\n", UVmessage::get("MENU_PROCESSING"), "\n";
      return "w";
    }
  }

  sub check_ballotid {
    my ($errors, $voter_addr, $ballot_id, $ids) = @_;

    return 0 unless ($config{personal});

    delete $errors->{NoBallotID};
    delete $errors->{WrongBallotID};
    delete $errors->{AddressNotRegistered};

    if ($$ballot_id) {
      if ($ids->{$$voter_addr}) {
        if ($ids->{$$voter_addr} ne $$ballot_id) {
          # ballot id incorrect
          $errors->{WrongBallotID} = UVmessage::get("MENU_WRONGBALLOTID");
        }
      } else {
        $errors->{AddressNotRegistered} = UVmessage::get("MENU_ADDRESSNOTREGISTERED");
      } 
    } else {
      $errors->{NoBallotID} = UVmessage::get("MENU_NOBALLOTID");
    }
  }

}


##############################################################################
# Menu for sorting out duplicate votings manually                            #
# Parameters: References to hashes with the paragraphs from the result file  #
#             and the default value                                          #
# Return value: selected menu item (1, 2 or 0)                               #
##############################################################################

sub dup_choice {
  my ($vote1, $vote2, $default) = @_;

  print STDERR "\n", UVmessage::get("MENU_DUP_VOTE"), "\n\n";
  print STDERR UVmessage::get("MENU_DUP_FIRST"), "\n";
  print STDERR "A: $vote1->{A}\n";
  print STDERR "N: $vote1->{N}\n";
  print STDERR "D: $vote1->{D}\n";
  print STDERR "K: $vote1->{K}\n";
  print STDERR "S: $vote1->{S}\n\n";
  print STDERR UVmessage::get("MENU_DUP_SECOND"), "\n";
  print STDERR "A: $vote2->{A}\n";
  print STDERR "N: $vote2->{N}\n";
  print STDERR "D: $vote2->{D}\n";
  print STDERR "K: $vote2->{K}\n";
  print STDERR "S: $vote2->{S}\n\n";
  print STDERR "1: ", UVmessage::get("MENU_DUP_DELFIRST"), "\n",
               "2: ", UVmessage::get("MENU_DUP_DELSECOND"), "\n",
               "0: ", UVmessage::get("MENU_DUP_DELNONE"), "\n\n";

  my $input;

  do {
    print STDERR UVmessage::get("MENU_PROMPT"), "[$default] ";
    $input = <STDIN>;
    chomp $input;
  } until ($input eq '' || ($input >= 0 && $input<3));

  return $input || $default;
}

1;
