# UVreadmail: functions for reading and processing mailfiles
# Used by uvvote.pl, uvcfv.pl, uvbounce.pl

package UVreadmail;

use strict;
use UVconfig;
use UVmessage;
use MIME::QuotedPrint;
use MIME::Base64;
use MIME::Parser;
use Mail::Box::Manager;
use POSIX qw(strftime);

use vars qw($VERSION);

# Module version
$VERSION = "0.11";

sub process {

  # $filename: file containing bounces or (if POP3 is enabled) where
  #            mails should be saved
  # $callsub:  reference to a sub which should be called for each mail
  # $caller:   0 = uvvote.pl, 1 = uvcfv.pl, 2 = uvbounce.pl
  #            3 = uvbounce.pl but POP3 disabled (overrides $config{pop3}
  #

  my ($filename, $callsub, $caller) = @_;
  my ($voter_addr, $voter_name, $body);
  my $count = 0;
  my ($pop3server, $pop3user, $pop3pass, $pop3delete, $pop3uidlcache);
  my @mails = ();
  $caller ||= 0;

  if ($config{pop3} && $caller<3) {

    if ($caller == 1) {
      # Ballot request (personal = 1 set in usevote.cfg) from uvcfv.pl
      $pop3server = $config{pop3server_req} . ':' . $config{pop3port_req};
      $pop3user = $config{pop3user_req};
      $pop3pass = $config{pop3pass_req};
      $pop3delete = $config{pop3delete_req};
      $pop3uidlcache = $config{pop3uidlcache_req};
    } elsif ($caller == 2) {
      # called from uvbounce.pl
      $pop3server = $config{pop3server_bounce} . ':' . $config{pop3port_bounce};
      $pop3user = $config{pop3user_bounce};
      $pop3pass = $config{pop3pass_bounce};
      $pop3delete = $config{pop3delete_bounce};
      $pop3uidlcache = $config{pop3uidlcache_bounce};
    } else {
      $pop3server = $config{pop3server} . ':' . $config{pop3port};
      $pop3user = $config{pop3user};
      $pop3pass = $config{pop3pass};
      $pop3delete = $config{pop3delete};
      $pop3uidlcache = $config{pop3uidlcache};
    }

    # read list of seen mails (UIDLs)
    my %uidls = ();  # hash for quick searching
    my @uidls = ();  # array to preserve order
    my $cacheexist = 1;
    open (UIDLCACHE, "<$pop3uidlcache") or $cacheexist = 0;
    if ($cacheexist) {
      while (my $uidl = <UIDLCACHE>) {
        chomp ($uidl);
        $uidls{$uidl} = 1;
        push (@uidls, $uidl);
      }     
      close (UIDLCACHE);
    }

    print UVmessage::get("READMAIL_STATUS"), "\n" unless ($caller == 2);

    # open POP3 connection and get new mails
    use Net::POP3;
    my $pop = Net::POP3->new($pop3server)
      or die UVmessage::get("READMAIL_NOCONNECTION") . "\n\n";

    my $mailcount = $pop->login($pop3user, $pop3pass);

    die UVmessage::get("READMAIL_NOLOGIN") . "\n\n" unless ($mailcount);

    for (my $n=1; $n<=$mailcount; $n++) {
      my $uidl = $pop->uidl($n);
      if ($uidl) {
        next if ($uidls{$uidl});
        $uidls{$uidl} = 1;
        push (@uidls, $uidl);
      }
      my $mailref = $pop->get($n)
         or print STDERR UVmessage::get("READMAIL_GET_PROBLEM", (NR => $n)) . "\n";
      my $mail = join ('', @$mailref);
      my $fromline = 'From ';
      if ($mail =~ /From: .*?<(.+?)>/) {
        $fromline .= $1;
      } elsif ($mail =~ /From:\s+?(\S+?\@\S+?)\s/) {
        $fromline .= $1;
      } else {
        $fromline .= 'foo@bar.invalid';
      }
      $fromline .= ' ' . strftime ('%a %b %d %H:%M:%S %Y', localtime) . "\n";
      push (@mails, $fromline . $mail);
      if ($pop3delete) {
        $pop->delete($n)
          or print STDERR UVmessage::get("READMAIL_DEL_PROBLEM", (NR => $n)) . "\n";
      }
    }

    # save UIDLs
    my $uidlerr = 0;
    open (UIDLCACHE, ">$pop3uidlcache") or $uidlerr = 1;
    if ($uidlerr) {
      print STDERR UVmessage::get("READMAIL_UIDL_PROBLEM") . "\n";
      print STDERR UVmessage::get("READMAIL_UIDL_PROBLEM2") . "\n";
    } else {
      print UIDLCACHE join("\n", @uidls);
      close (UIDLCACHE) or print STDERR UVmessage::get("READMAIL_UIDL_CLOSE") . "\n";
    }

    $pop->quit();

  # Mailbox / Maildir
  } else {

    my $readfilename;

    if ($caller==0) {
      # called from uvvote.pl: use configured mailbox file
      $readfilename = $config{votefile};
    } else {
      # else use filename provided in function call
      $readfilename = $filename;
      # and create backup archive filename
      $filename .= '.processed';
    }

    my $mgr = Mail::Box::Manager->new;
    my $folder;

    eval{
      $folder = $mgr->open( folder => $readfilename,
                create => 0,
                access => 'rw',
                type   => $config{mailboxtype},
                expand => 'LAZY',
                remove_when_empty => 0,
              );
    };
    die UVmessage::get("READMAIL_NOMAILFILE", (FILE => $readfilename)) . "\n\n" if $@;

    # Iterate over the messages.
    foreach (@$folder) {
      my $mail = $_->string;
      $_->delete();
      my $fromline = 'From ';
      if ($mail =~ /From: .*?<(.+?)>/) {
        $fromline .= $1;
      } elsif ($mail =~ /From:\s+?(\S+?\@\S+?)\s/) {
        $fromline .= $1;
      } else {
        $fromline .= 'foo@bar.invalid';
      }
      $fromline .= ' ' . localtime($_->timestamp()) . "\n";
      push (@mails, $fromline . $mail);
    }
  }

  # make archive of all mails
  my $fileproblem = 0;
  open (VOTES, ">$filename") or $fileproblem = 1;
  if ($fileproblem) {
    print STDERR UVmessage::get("READMAIL_ARCHIVE_PROBLEM",
                 (FILE => $filename)) . "\n";
  } else {
    print VOTES join ("\n", @mails);
    close (VOTES)
      or print STDERR UVmessage::get("READMAIL_ARCHIVE_CLOSE",
                      (FILE => $filename)) . "\n";
  }

  foreach my $mail (@mails) {
    next unless $mail;

    # split mail into array and remove first line (from line)
    my @mail = split(/\n/, $mail);
    shift (@mail) if ($mail[0] =~ /^From /);

    # generate MIME-Parser object for the mail
    my $parser = new MIME::Parser;
    # headers are to be decoded
    $parser->decode_headers(1);
    # don't write into file
    $parser->output_to_core(1);

    # read mail
    my $entity = $parser->parse_data(join("\n", @mail));
    my $head = $entity->head;

    # extract address and name
    my $from = $head->get('From') || '';

    if ($from =~ /\s*([^<]\S+\@\S+[^>]) \((.+)\)/) {
      ($voter_addr, $voter_name) = ($1, $2);
    } elsif ($from =~ /\s*\"?([^\"]+)\"?\s*<(\S+\@\S+)>/) {
      ($voter_name, $voter_addr) = ($1, $2);
      $voter_name =~ s/\s+$//;  # kill spaces at the end
    } elsif ($from =~ /\s*<?(\S+\@[^\s>]+)>?[^\(\)]*/) {
      ($voter_addr, $voter_name) = ($1, '');
    } else {
      # initialize with empty value
      $voter_addr = '';
      $voter_name = '';
    }

    # look at reply-to?
    if ($config{replyto}) {

      my $replyto = Mail::Field->new('Reply-To', $head->get('Reply-To'));

      # Address in Reply-To?
      ($voter_addr) = $replyto->addresses() if ($replyto->addresses());

      # Name in reply-to?
      if ($replyto->names()) {
         my ($nametmp) = $replyto->names();
         $voter_name = $nametmp unless ($nametmp =~ /^\s*$/);
      }

    }

    # decode body
    my $encoding = $head->get('Content-Transfer-Encoding') || '';
    if ($encoding =~ /quoted-printable/i) {
      $body = decode_qp($entity->stringify_body);
    } elsif ($encoding =~ /base64/i) {
      $body = decode_base64($entity->stringify_body);
    } else {
      $body = $entity->stringify_body;
    }

    my $h_date = $head->get('Date') || '';
    chomp $h_date;

    # call referred sub and increase counter
    &$callsub($voter_addr, $voter_name, $h_date, $entity, \$body);
    $count++;
  } 

  return $count;
}

1;
