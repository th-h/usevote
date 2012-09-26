# UVconfig: Reads config files and tests configuration
# Used by all components

package UVconfig;

use strict;
use Net::Domain qw(hostname hostfqdn hostdomain);
use UVmessage;
use vars qw(@ISA @EXPORT $VERSION $usevote_version %config %messages
            @rules @groups $bdsg_regexp $bdsg2_regexp %ids %functions);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($usevote_version %config %messages @rules @groups
             $bdsg_regexp $bdsg2_regexp %ids %functions);

# Module version
$VERSION = "0.18";

# Usevote version
$usevote_version = "UseVoteGer 4.11";

sub read_config {

  my ($cfgfile, $redir_errors) = @_;
  
  # Default configuration options (overwritten in usevote.cfg)
  %config = (votefile             => "votes",
             votename             => "unkonfiguriertes Usevote",
             resultfile           => "ergebnis.alle",
             rulefile             => "usevote.rul",
             badaddrfile          => "mailpatterns.cfg",
             messagefile          => "messages.cfg",
             idfile               => "scheinkennungen",
             requestfile          => "anforderung",
             errorfile            => "errors.log",
             lockfile             => "usevote.lock",
             replyto              => 0,
             personal             => 0,
             proportional         => 0,
             bdsg                 => 0,
             onestep              => 0,
             multigroup           => 0,
             voteack              => 1,
             voteaccount          => "<> (unkonfiguriertes Usevote)",
             mailfrom             => "<> (unkonfiguriertes Usevote)",
             envelopefrom         => "<>",
             mailboxtype          => "mbox",
             mailstart            => "^From ",
             archivedir           => "fertig",
             tmpdir               => "tmp",
             templatedir          => "templates",
             formats              => "UVformats.pm",
             domailfile           => "tmp/domail",
             controlfile          => "tmp/ack.control",
             mailcmd              => "sendmail -oi -oem",
             mailcc               => "",
             sleepcmd             => "sleep 1",
             clearcmd             => "clear",
             pager                => "less",
             pop3                 => 0,
             pop3server           => "localhost",
             pop3port             => 110,
             pop3user             => "default",
             pop3pass             => "default",
             pop3delete           => 0,
             pop3uidlcache        => "uidlcache",
             pop3server_req       => "localhost",
             pop3port_req         => 110,
             pop3user_req         => "default",
             pop3pass_req         => "default",
             pop3delete_req       => 0,
             pop3uidlcache_req    => "uidlcache_req",
             pop3server_bounce    => "localhost",
             pop3port_bounce      => 110,
             pop3user_bounce      => "default",
             pop3pass_bounce      => "default",
             pop3delete_bounce    => 0,
             pop3uidlcache_bounce => 'uidlcache_bounce',
             smtp                 => 0,
             smtpserver           => 'localhost',
             smtpport             => 25,
             smtphelo             => hostfqdn(),
             fqdn                 => hostfqdn(),
             smtpauth             => 0,
             smtpuser             => '',
             smtppass             => '',
             name_re              => '[a-zA-ZäöüÄÖÜß-]{2,} +.*[a-zA-ZäöüÄÖÜß]{2,}',
             ja_stimme            => '(J\s*A|J|(D\s*A\s*)?F\s*U\s*E\s*R)',
             nein_stimme          => '(N\s*E\s*I\s*N|N|(D\s*A\s*)?G\s*E\s*G\s*E\s*N)',
             enth_stimme          => '(E|E\s*N\s*T\s*H\s*A\s*L\s*T\s*U\s*N\s*G)',
             ann_stimme           => 'A\s*N\s*N\s*U\s*L\s*L\s*I\s*E\s*R\s*U\s*N\s*G',
             condition1           => '$yes>=2*$no', # twice as many yes as no
             condition2           => '$yes>=60',    # min 60 yes votes
             prop_formula         => '$yes/$no',
             tpl_ack_mail         => 'ack-mail',
             tpl_bouncelist       => 'bouncelist',
             tpl_mailheader       => 'mailheader',
             tpl_result_multi     => 'result-multi',
             tpl_result_single    => 'result-single',
             tpl_result_prop      => 'result-proportional',
             tpl_votes_multi      => 'votes-multi',
             tpl_votes_single     => 'votes-single',
             tpl_voterlist        => 'voterlist',
             tpl_ballot           => 'ballot',
             tpl_ballot_request   => 'ballot-request',
             tpl_ballot_personal  => 'ballot-personal',
             tpl_addr_reg         => 'address-not-registered',
             tpl_no_ballotid      => 'no-ballotid',
             tpl_wrong_ballotid   => 'wrong-ballotid',
             tpl_bdsg_error       => 'bdsg-error',
             tpl_cancelled        => 'cancelled',
             tpl_invalid_account  => 'invalid-account',
             tpl_invalid_name     => 'invalid-name',
             tpl_multiple_votes   => 'multiple-votes',
             tpl_no_ballot        => 'no-ballot',
             tpl_no_votes         => 'no-votes',
             tpl_rule_violated    => 'rule-violated',
             begin_divider        => 'Alles vor dieser Zeile bitte loeschen',
             end_divider          => 'Alles nach dieser Zeile bitte loeschen',
             nametext             => 'Dein Realname, falls nicht im FROM-Header:',
             nametext2            => 'Waehlername:',
             addresstext          => 'Waehleradresse:',
             ballotidtext         => 'Wahlscheinkennung:',
             bdsgtext             => 'Datenschutzklausel - Zustimmung',
             bdsgfile             => 'bdsgtext.cfg',
             rightmargin          => 72,
             usevote_version      => $usevote_version); # needed for use in templates

  # read config
  read_file($cfgfile);

  # read message file
  open (RES, "<$config{messagefile}")
     or die "Could not read message file $config{messagefile}!\n\n";
  my @lines = <RES>;
  close(RES);

  foreach my $line (@lines) {
    chomp($line);
    $line =~ s/^#.*//;        # Delete comments
    if ($line =~ m/^\s*([A-Za-z0-9_-]+)\s*=\s*(.+)\s*$/){
      $messages{$1} = $2;
    }
  } 

  # missing "groupX =" lines in config file?
  die UVmessage::get("CONF_NOGROUPS", CONFIGFILE=>$cfgfile) . "\n\n" unless (@groups);

  # redirect errors to a file if desired by calling script
  open (STDERR, ">$config{errorfile}") if ($redir_errors);

  # check for data protection law? read text for ballot
  parse_bdsgtext() if ($config{bdsg});

  # personalized ballots? read ballot IDs
  read_ballot_ids() if ($config{personal});

  load_formats() if ($config{formats});
 
}


##############################################################################
# read config file                                                           #
##############################################################################

sub read_file {

  my $cfgfile = shift;
  my $CONFIG;
  open ($CONFIG, "<$cfgfile") or die "Could not find config file $cfgfile!\n\n";

  while (<$CONFIG>) {
    next if (/^#/);     # line is a comment
    chomp;              # delete \n
    s/\r//;             # delete \r if present
    s/([^\\])#.*$/$1/;  # Remove comments not starting at beginning of line.
                        # (ignore escaped comment sign \#)


    if (/^include (\S+)$/) {
      # include other config file
      read_file($1);

    } elsif (my($key, $value) = split (/\s*=\s*/, $_, 2)) {
      # delete trailing spaces
      $value =~ s/\s*$//;

      # evaluate quotation marks
      $value =~ s/^\"([^\"]+[^\\\"])\".*$/$1/;
      $value =~ s/\\"/"/g;

      if ($key =~ /^group(\d+)$/) {
        my $num = $1;
        $groups[$num-1] = $value;    # internal index starts at 0
      } else {
        $config{$key} = $value;
      }
    }
  }

  close ($CONFIG);

}


##############################################################################
# parse data protection law texts                                            #
##############################################################################

sub parse_bdsgtext {

  open (BDSG, "<$config{bdsgfile}") or die UVmessage::get("CONF_NOBDSGFILE",
                            ('BDSGFILE' => "$config{bdsgfile}")) . "\n\n";
  my @bdsg = <BDSG>;
  close BDSG;

  $config{bdsginfo} = '';

  foreach my $line (@bdsg) {
    $config{bdsginfo} .= $line unless ($line =~ /^\s*#/);
  }

  my $bdsgtmp = $config{bdsginfo};
  $bdsgtmp =~ s/\"/\\\"/g;
  $bdsgtmp =~ s/\'/\\\'/g;
  $bdsgtmp =~ s/\(/\\\(/g;
  $bdsgtmp =~ s/\)/\\\)/g;
  $bdsgtmp =~ s/\[/\\\[/g;
  $bdsgtmp =~ s/\]/\\\]/g;
  $bdsgtmp =~ s/\./\\\./g;
  $bdsgtmp =~ s/\!/\\\!/g;
  my @bdsgtext = split(' ', $bdsgtmp);

  # Build Regular Expression from single words.
  # There has to be at least a space between two words, additional characters
  # are allowed, e.g. quotation marks (but no letters)
  $bdsg_regexp = join('\s\W*?', @bdsgtext);

  # Build Regular Expression from $config{bdsgtext}
  $bdsg2_regexp = join('\s\W*?', split(' ', $config{bdsgtext}));
}
  

##############################################################################
# Read suspicious mail addresses (normally mailpatterns.cfg)                 #
##############################################################################

sub read_badaddr {
  
  my @bad_addr = ();

  open (BADADDR, "<$config{badaddrfile}") or die 
    UVmessage::get("CONF_NOBADADDR",(BADADDRFILE => $config{badaddrfile})) . "\n\n";

  while (<BADADDR>) {
    chomp;
    # Comment line? Not only whitespaces?
    if (/^[^#]/ && /[^\s]/) {
      push(@bad_addr, $_);
    }
  }

  close (BADADDR);
  return @bad_addr;
}


##############################################################################
# Read ballot IDs                                                            #
##############################################################################

sub read_ballot_ids {
  # open file with ballot ids
  open(FILE, "<$config{idfile}") or return 1;
  while (<FILE>) {
    chomp;
    # Format: mailaddress (whitespace) ballot ID
    if (/^(.+@.+)\s+([a-z0-9]+)/) {
      # $1=mailadresse, $2=ballot ID
      $ids{$1} = $2;
    }
  }
  close(FILE);
  return 0;
}


##############################################################################
# Funktionen für Templates laden                                             #
##############################################################################

sub load_formats {
  my $modules = $config{formats};

  my @modules = split(/\s*,\s*/, $modules);

  foreach my $module (@modules){
    if (-r $module){
      require $module;
    }
  }
}


##############################################################################
# config test                                                                #
##############################################################################

sub test_config {
  print UVmessage::get("CONF_CONFIG"), "\n\n";
  foreach my $option (keys %config) {
    print "$option = $config{$option}\n";
  }

  print "\n", UVmessage::get("CONF_TEST_RULES");
  if (@rules) {
    print "\n\n";
    for (my $n=0; $n<@rules; $n++) {
      my $text = UVrules::rule_print($n);
      print $text;
    }
    print "\n";
  } else {
    print UVmessage::get("CONF_NO_RULES"), "\n\n";
  }
}

1;
