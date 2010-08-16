# UVsendmail: functions for sending mails
# Used by uvvote.pl, uvcfv.pl

package UVsendmail;

use strict;
use UVconfig;
use UVtemplate;
use MIME::Words;
use Text::Wrap qw(wrap $columns);

# Set columns for Text::Wrap
$columns = $config{rightmargin};

use vars qw($VERSION);

# Module version
$VERSION = "0.9";

my $num = 0;

##############################################################################
# generation of acknowledge and error mails (don't sends them out yet)       #
# each mail is saved in a different file and a control file containing       #
# filename and envelope-to address is generated.                             #
# Parameters: mail address, fixed part of subject and body of mail (strings) #
##############################################################################
 
sub mail {
  my ($addr, $subject, $text, $reference, $replyto) = @_;
 
  # address set?
  if ($addr) {
    # generate mail to sender
  
    my $template = UVtemplate->new();
    $template->setKey('from' => mimeencode($config{mailfrom}));
    $template->setKey('subject' => mimeencode("$config{votename} - $subject"));
    $template->setKey('address' => $addr);
    $template->setKey('reference' => $reference) if ($reference);
    $template->setKey('reply-to' => $replyto) if ($replyto);
    $template->setKey('usevote-version' => $usevote_version);

    my $message = $template->processTemplate($config{'tpl_mailheader'});
    $message .= "\n" . $text;

    # get envelope-to addresses
    my $envaddr = $addr;
    $envaddr .= " $config{mailcc}" if ($config{mailcc});

    my $mailfile = '';

    # search for file names
    do {
      $num++;
      $mailfile = "$config{tmpdir}/ack.$num";
    } while (-e $mailfile);
    
    # write mail in a file and append a line at the control file

    open (CONTROL, ">>$config{controlfile}") or print STDERR "\n\n",
      UVmessage::get("SENDMAIL_ERROPENCONTROL", (FILE => $config{controlfile})), "\n"; 
    print CONTROL "$mailfile\t$envaddr\n";
    close (CONTROL) or print STDERR "\n\n",
      UVmessage::get("SENDMAIL_ERRCLOSECONTROL", (FILE => $config{controlfile})), "\n";

    open (MAIL, ">$mailfile") or print STDERR "\n\n",
      UVmessage::get("SENDMAIL_ERROPENMAIL", (FILE => $config{controlfile})), "\n";
    print MAIL $message;
    close (MAIL) or print STDERR "\n\n",
      UVmessage::get("SENDMAIL_ERRCLOSEMAIL", (FILE => $config{controlfile})), "\n";

  }
}                                                                                      


##############################################################################
# Send previously generated acknowledge or error mails.                      #
# Depending on configuration mails are piped to your MTA or send via SMTP.   #
##############################################################################

sub send {
  unless (-e $config{controlfile}) {
    print "\n", UVmessage::get("SENDMAIL_NOMAILS", (FILE => $config{controlfile})),
          "\n\n";
    return 0;
  }

  open (CONTROL, "<$config{controlfile}") or die "\n\n",
    UVmessage::get("SENDMAIL_ERROPENCONTROL", (FILE => $config{controlfile})), "\n";
  my @mailinfo = <CONTROL>;
  close (CONTROL);

  print UVmessage::get("SENDMAIL_SENDING"), "\n";

  if ($config{smtp}) {
    # send mails via SMTP
    use Net::SMTP;
    my $smtp = Net::SMTP->new("$config{smtpserver}:$config{smtpport}",
                              Hello => $config{smtphelo});
    die UVmessage::get("SENDMAIL_SMTP_CONNREFUSED") . "\n\n" unless ($smtp);
    if ($config{smtpauth}) {
      $smtp->auth($config{smtpuser}, $config{smtppass})
        or die UVmessage::get("SENDMAIL_SMTP_CONNREFUSED") . "\n" .
               $smtp->code() . ' ' . $smtp->message() . "\n";
    }

    my $errors = 0;
    my $missingfiles = 0;

    open (CONTROL, ">$config{controlfile}") or die  "\n\n",
      UVmessage::get("SENDMAIL_ERROPENCONTROL", (FILE => $config{controlfile})), "\n";

    foreach my $mail (@mailinfo) {

      chomp ($mail);
      next unless $mail;

      my ($file, $envelope) = split(/\t/, $mail);
      my $notfound = 0;
      open (MAIL, "<$file") or $notfound = 1;
      if ($notfound) {
        print STDERR UVmessage::get("SENDMAIL_ERRNOTFOUND") . "\n";
        $missingfiles++;
        next;
      }
      my $message = join('', <MAIL>);
      close (MAIL);

      next unless $message;

      $smtp->reset();
      $smtp->mail($config{envelopefrom});
      unless ($smtp->ok()) {
        print STDERR UVmessage::get("SENDMAIL_SMTP_INVRCPT", (RCPT => $envelope)),
                     "\n", $smtp->code(), ' ', $smtp->message(), "\n";
        $errors++;
        next;
      }
        
      my $onesent = 0;
      my $onefail = 0;
      foreach my $addr (split(/ +/, $envelope)) {
        $smtp->to($addr);
        if ($smtp->ok()) {
          $onesent = 1;
        } else {
          print CONTROL ($onefail ? " " : "$file\t");
          print CONTROL $addr;
          print STDERR UVmessage::get("SENDMAIL_SMTP_INVRCPT", (RCPT => $envelope)),
                       "\n", $smtp->code(), ' ', $smtp->message(), "\n";
          $errors++;
          $onefail = 1;
          next;
        }
      }

      print CONTROL "\n" if ($onefail);
      next unless $onesent;

      $smtp->data();
      if ($smtp->ok()) {
        $smtp->datasend($message);
        $smtp->dataend();
      }
      unless ($smtp->ok()) {
        print STDERR UVmessage::get("SENDMAIL_SMTP_INVRCPT", (RCPT => $envelope)),
                     "\n", $smtp->code(), ' ', $smtp->message(), "\n";
        $errors++;
        next; 
      }
      unlink ($file) unless ($onefail);
    }

    $smtp->quit();
    close (CONTROL) or die "\n\n",
      UVmessage::get("SENDMAIL_ERRCLOSECONTROL", (FILE => $config{controlfile})), "\n";

    if ($errors) {
      print STDERR "\n".wrap('', '', "$errors ".UVmessage::get("SENDMAIL_ERROCCURED"))."\n\n";
    }

    if ($missingfiles) {
      print STDERR wrap('', '', "$missingfiles " .
                   UVmessage::get("SENDMAIL_MISSINGFILES")), "\n\n";
    }

  } else {

    foreach my $mail (@mailinfo) {
      next unless $mail;
      chomp($mail);
      my ($file, @rcpt) = split(/\s+/, $mail);
      open (DOMAIL, ">>$config{domailfile}");
      print DOMAIL "$config{mailcmd} ";
      foreach my $rcpt (@rcpt) {
        print DOMAIL "'$rcpt' ";
      }
      print DOMAIL "<$file && rm $file ; $config{sleepcmd}\n";
      close (DOMAIL)
        or print STDERR "\n\n", UVmessage::get("SENDMAIL_ERRCLOSEDOMAIL"), "\n";
    }
    chmod(0700, $config{domailfile});
    system($config{domailfile});

  }

  opendir (DIR, $config{tmpdir});
  my @files = grep (/^ack\.\d+/, readdir (DIR));
  closedir (DIR);
  return 0 if (@files);

  unlink $config{controlfile} or print STDERR "\n\n",
    UVmessage::get("SENDMAIL_ERRDELCONTROL", (FILE => $config{controlfile})), "\n";

  unless ($config{smtp}) {
    unlink $config{domailfile} or print STDERR "\n\n",
      UVmessage::get("SENDMAIL_ERRDELCONTROL", (FILE => $config{domailfile})), "\n";
  }

}


##############################################################################
# Encodes a string for use in mail headers                                   #
#                                                                            #
# Parameters: $text = string to encode.                                      #
# Returns:  $newtext = encoded string.                                       #
##############################################################################
 
sub mimeencode {
  my ($text) = @_;
  my @words = split(/ /, $text);
  my $line = '';
  my @lines;
 
  foreach my $word (@words) {
    my $sameword = 0;
    $word =~ s/\n//g;
    my $encword;
    if ($word =~ /[\x7F-\xFF]/) {
      $encword = MIME::Words::encode_mimeword($word, 'Q', 'ISO-8859-1');
    } elsif (length($word) > 75) {
      $encword = MIME::Words::encode_mimeword($word, 'Q', 'us-ascii');
    } else {
      $encword = $word;
    }
 
    # no more than 75 chars per line allowed
    if (length($encword) > 75) {
      while ($encword) {
        if ($encword =~ /(^=\?[-\w]+\?\w\?)(.{55}.*?)((=.{2}|[^=]{3}).*\?=)$/) {
          addword($1 . $2 . '?=', \$line, \@lines, $sameword);
          $encword = $1 . $3;
        } else {
          addword($encword, \$line, \@lines, $sameword);
          $encword = '';
        }
        $sameword = 1;
      }
    } else {
      addword($encword, \$line, \@lines, $sameword);
    }
  }
 
  my $delim = (@lines) ? ' ' : '';
  push(@lines, $delim . $line) if ($line);
  return join('', @lines);
}
 

##############################################################################
# Adds a word to a MIME encoded string, inserts linefeed if necessary        #
#                                                                            #
# Parameters:                                                                #
#   $word = word to add                                                      #
#   $line = current line                                                     #
#   $lines = complete text (without current line)                            #
#   $sameword = boolean switch, indicates that this is another part of       #
#               the last word (for encoded words > 75 chars)                 #
##############################################################################
 
sub addword {
  my ($word, $line, $lines, $sameword) = @_;
 
  # If the passed fragment is a new word (and not another part of the
  # previous): Check if it is MIME encoded
  if (!$sameword && $word =~ /^(=\?[^\?]+?\?[QqBb]\?)(.+\?=[^\?]*)$/) {
 
    # Word is encoded, save without the MIME header
    # (e.g. "t=E4st?=" instead of "?iso-8859-1?q?t=E4st?=")
    my $charset = $1;
    my $newword = $2;

    if ($$line =~ /^(=\?[^\?]+\?[QqBb]\?)(.+)\?=$/) {
      # Previous word was encoded, too:
      # Delete the trailing "?=" and insert an underline character (=space)
      # (space between to encoded words is ignored)
      if ($1 eq $charset) {
        if (length($1.$2)+length($newword)>75) {
          my $delim = (@$lines) ? ' ' : '';
          push(@$lines, "$delim$1$2_?=\n");
          $$line = $word;
        } else {
          $$line = $1 . $2 . '_' . $newword;
        }
      } else {
        if (length("$$line $word")>75) {
          my $delim = (@$lines) ? ' ' : '';
	  push(@$lines, "$delim$1$2_?=\n");
          $$line = $word;
	} else {
          $$line = "$1$2_?= $word";
	}
      }
      return 0;
    }
  }

  # New word is not encoded: simply append it, but check for line length
  # and add a newline if necessary
  if (length($$line) > 0) {
    if (length($$line) + length($word) >= 75) {
      my $delim = (@$lines) ? ' ' : '';
      push(@$lines, "$delim$$line\n");
      $$line = $word;
    } else {
      $$line .= " $word";
    }
  } else {
    # line is empty
    $$line = $word;
  }
}

1;
