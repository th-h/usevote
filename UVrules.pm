# UVrules: Module with rule functions for usevote
# Used by uvvote.pl, UVconfig.pm

package UVrules;
 
use strict;
use vars qw (@ISA @EXPORT $VERSION @rules);
use UVconfig;
use UVmessage;
 
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(@rules);
 
# Module version
$VERSION = "0.3"; 

# ---------------------------------------------------------------------
# Erlaeuterung zur Regelpruefung (to be translated)
# ---------------------------------------------------------------------
# Um Stimmen mit multiplen Abstimmungspunkten auf ihre Sinnfaelligkeit 
# pruefen zu koennen, koennen in Usevote verschiedenste Regeln
# fuer solche Pruefungen definiert werden. 
#
# Die Regeln bestehen aus zwei Teilen. Einer IF-Klausel und einer THEN-
# Klausel. Die IF-Klausel bestimmt, ob die Stimme mit der THEN-Klausel
# verglichen werden soll. Passt sie auf diese, ist die Stimme in Ordnung,
# wenn nicht liegt ein Fehler vor.
#
# Ein kleines Beispiel: "IF S.. THEN .SS"
# Wenn beim ersten Punkt mit Ja oder Nein gestimmt wurde, dann muss
# bei den anderen beiden Punkten auch ein Ja oder Nein vorliegen.
#
# Die Stimmabgabe JNE wuerde also gegen die obige Regel verstossen,
# JJN nicht. EEJ wuerde ebenfalls gueltig sein, da die Regel nicht unter
# die IF-Klausel faellt und somit keine Ueberpruefung der THEN-Klausel
# erfolgt.
#
#
# ---------------------------------------------------------------------
# Implementierung
# ---------------------------------------------------------------------
# Um eine moeglichst einfache Ueberpruefung der Stimmen vorzunehmen,
# bietet es sich an, aus den beiden Klauseln regulaere Ausdruecke zu
# generieren. Diese wuerden dann auf die Stimme angewandt werden.
# 
# Bei der Umwandlung in regulaere Audruecke kommt uns die Notation
# der Regeln bereits entgegen. So kann der Punkt als beliebige Stimme
# beibehalten werden. Die grossen Buchstaben bleiben ebenfalls bis
# auf S erhalten, da die zu pruefenden Stimmen aus den Buchstaben
# 'JNE' bestehen.
#
# So muessen wir zur Ueberpruefung von direkten Stimmen nur 'S' in
# eine Klasse mit [JN] und I in eine Klasse mit [EN] umwandeln.
#
# 'J..' => 'J..', 'NNE' => 'NNE', 'S..' => '[JN]..'
#
# Bei den indirekten Stimmabgaben wird es schon schwieriger. Hier 
# muessten alle Moeglichkeiten eines Strings gebaut werden, um zu
# testen ob mindestens eine Version matcht.
#
# '.jjj' => '.(j..|.j.|..j)
#
# Je komplexer die Regeln, um so mehr Moeglichkeiten muessten
# konstruiert werden, um einen geschlossenen regulaeren Ausdruck
# zu erhalten.
#
# Wir koennen den Regex aber auch einfach aufbauen, in dem wir
# nicht alle Faelle betrachten die moeglich sind, sondern nur die
# Faelle die nicht erlaubt sind. 
# 
# D.h. soll an einer Stelle ein Ja stehen, erlauben wir dort
# nur Nein und Enthaltungen. Passt eine Stimme auf diesen Regex,
# kann sie unmoeglich die Vorgabe enthalten.
# 
# 'nnnn' => '[JE][JE][JE][JE]'
#
# Besteht eine Stimme also nur aus Ja und Enthaltung, wissen wir
# das kein einziges Nein enthalten seien kann. Die Stimme passt
# also nicht auf unser Muster.
#
# Tritt hingegen nur ein einziges J auf, passt der regulaere Ausdruck
# nicht mehr, und wir wissen, dass die Stimme die Regel erfuellt.
#
# Wie wir sehen koennen, ist der negative Ausdruck leichter zu
# bilden als der positive. 
#
#
# Da eine Stimme nun sowohl aus direkten, als auch indirekten
# Stimmen bestehen kann (z.B. 'Jnnn..') muessen wir die Stimme
# zerlegen. Wir bilden einen positiven Regex fuer die Grossbuch-
# staben und einen negativen Regex fuer die kleinen.
#
# Passt eine Stimme dann auf den positiven Regex und nicht auf
# den negativen Regex, so entspricht sie der urspruenglichen
# Regel.
#
# Ein Beispiel: 'Sss..' (Der erste Punkt und der zweite oder dritte
# Punkt muessen ein Ja oder Nein sein.)
#
# positiver Regex: '[JN]...'	muss erfuellt werden
# negativer Regex: '.EE.'	darf nicht erfuellt werden
#
# JJNN => positiv matcht => negativ matcht nicht => Regel erfuellt
# ENJE => positiv matcht nicht => Regel nicht erfuellt
# NEEJ => positiv matcht => negativ matcht => Regel nicht erfuellt
#
#
# Mit Hilfe dieser Technik, lassen sich einfach Regex bilden, die
# ebenso einfach ueberprueft werden koennen.


##############################################################################
# Read usevote.rul and check rules for correct syntax                        #
##############################################################################
  
sub read_rulefile {
  @rules = ();

  open (RULES, "<$config{rulefile}")
    or die UVmessage::get("RULES_ERROPENFILE", (FILE => $config{rulefile})) . "\n\n";
 
  while (<RULES>) {
    chomp;
    s/#.*$//;  # delete comments
 
    # does line match correct if-then syntax?
    if (/^\s*if\s+(\S+)\s+then\s+(\S+)\s*$/) {
      my $if   = $1;
      my $then = $2;

      # $num contains the rule's array index
      my $num = @rules;
 
      # check for correct length of condition
      my $errortext;
      if (length($if) < @groups) {
        $errortext = UVmessage::get("RULES_TOOSHORT", (NUM=>$num+1, TYPE=>"if"));
 
      } elsif (length($if) > @groups) {
        $errortext = UVmessage::get("RULES_TOOLONG", (NUM=>$num+1, TYPE=>"if"));
 
      } elsif (length($then) < @groups) {
        $errortext = UVmessage::get("RULES_TOOSHORT", (NUM=>$num+1, TYPE=>"then"));
 
      } elsif (length($then) > @groups) {
        $errortext = UVmessage::get("RULES_TOOLONG", (NUM=>$num+1, TYPE=>"then"));
      }
      die $errortext . ": $_\n\n" if ($errortext);
 
      # check for correct characters in conditions
      if ($if !~ /^[JjNnEeSsHhIi\.]+$/) {
        die UVmessage::get ("RULES_INVCHARS", (NUM=>$num+1, TYPE=>"if")) . ": $if\n\n";

      } elsif ($then !~ /^[JjNnEeSsHhIi\.]+$/) {
        die UVmessage::get ("RULES_INVCHARS",
                            (NUM=>$num+1, TYPE=>"if")) . ": $then\n\n";
      }
 
      # Zur Speicherung der Regeln (to be translated):
      # - if_compl und then_compl sind die kompletten Bedingungen als Strings,
      #   werden fuer die Sprachausgabe der Regeln benoetigt
      # - zusaetzlich werden der if- und then-Teil fuer die einfachere
      #   Verarbeitung in zwei Teile gesplittet: Eine Positiv-Regex, die auf
      #   die Grossbuchstaben (explizite Forderungen, UND-Verknuepfungen)
      #   matched, und eine Negativ-Regex, die bei den Kleinbuchstaben
      #   (optionale Felder, ODER-Verknuepfungen) verwendet wird.

      my %rule = ( if_compl   => $if,
                   if_pos     => make_regex_pos($if),
                   if_neg     => make_regex_neg($if),
                   then_compl => $then,
                   then_pos   => make_regex_pos($then),
                   then_neg   => make_regex_neg($then) );
 
      push (@rules, \%rule);

    }
  }
}
 

##############################################################################
# Generates a RegEx for positive matching of the rules                       #
#                                                                            #
# All lower case characters are replaced with dots, as they are to be        #
# matched by the negativ RegEx. Furthermore the symbol S is replaced by [JN] #
# and I is replaced by [EN] (for use in combined votings when only one       #
# option may be accepted and the others must be rejected or abstained.       #
# As a result we have a regular expression that can be matched against the   #
# received votes.                                                            #
##############################################################################
  
sub make_regex_pos {
  my $pat = $_[0];
 
  $pat =~ s/[hijens]/./g;
  $pat =~ s/S/[JN]/g;
  $pat =~ s/H/[EJ]/g;
  $pat =~ s/I/[EN]/g;
 
  return $pat;
}
 

##############################################################################
# Generates a RegEx for negative matching of the rules                       #
#                                                                            #
# All upper case characters are replaced with dots, as they are to be        #
# matched by the positiv RegEx. If lower case characters are found the       #
# condition is reversed, so that we are able to match votes *not*            #
# corresponding to this rule                                                 #
##############################################################################
  
sub make_regex_neg {
  my $pat = $_[0];
 
  # upper case characters are replaced with dots
  # (are covered by make_regex_pos)
  $pat =~ s/[HIJENS]/./g;
 
  # reverse lower case characters
  $pat =~ s/j/[NE]/g;
  $pat =~ s/n/[JE]/g;
  $pat =~ s/e/[JN]/g;
  $pat =~ s/s/E/g;
  $pat =~ s/h/N/g;
  $pat =~ s/i/J/g;
 
  # If the string contained only upper case characters they are now all
  # replaced with dots and the RegEx would match everything, i.e. declare
  # every vote as invalid. In this case an empty pattern is returned.
  $pat =~ s/^\.+$//;
 
  return $pat;
}
 

##############################################################################
# Check a voting for rule compliance                                         #
# Parameters: Votes (Reference to Array)                                     #
# Return value: Number of violated rule or 0 (everything OK)                 #
# (Internally rules are saved with indexes starting at 0)                    #
##############################################################################

sub rule_check {
  my ($voteref) = @_;

  # Turn array reference into a string
  my $vote = join ('', @$voteref);

  # For compliance with the rules every rule has to be matched against the
  # the vote. If the IF clause matches but not the THEN clause the vote is
  # invalid and the rule number is returned.

  for (my $n = 0; $n < @rules; $n++) {
    return $n+1 if ($vote =~ m/^$rules[$n]->{if_pos}$/ &&
                    $vote !~ m/^$rules[$n]->{if_neg}$/ &&
                not($vote =~ m/^$rules[$n]->{then_pos}$/ &&
                    $vote !~ m/^$rules[$n]->{then_neg}$/ ));
  }
 
  return 0;
} 


##############################################################################
# Print rules in human readable format                                       #
# Parameter: rule number                                                     #
# Return value: rule text                                                    #
##############################################################################
 
sub rule_print {
  my ($n) = @_;

  my $and = UVmessage::get ("RULES_AND");
  my $or = UVmessage::get ("RULES_OR");
  my $yes = UVmessage::get ("RULES_YES");
  my $no = UVmessage::get ("RULES_NO");
  my $abst = UVmessage::get ("RULES_ABSTAIN");

  $n++;
  my $text = UVmessage::get ("RULES_RULE") . " #$n:\n";
  $text .= "  " . UVmessage::get ("RULES_IF") . "\n";
 
  my @rule = split (//, $rules[$n-1]->{if_compl});
  my $firstrun = 1;
  my $fill = "";
 
  for (my $i=0; $i<@rule; $i++) {
    my $text1 = "";

    if ($rule[$i] eq 'J') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE", (VOTE=>$yes, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'N') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE", (VOTE=>$no, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'E') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE", (VOTE=>$abst, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'S') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE",
                               (VOTE=>"$yes $or $no", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'H') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE",
                               (VOTE=>"$abst $or $yes", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'I') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE",
                               (VOTE=>"$abst $or $no", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'j') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE", (VOTE=>$yes, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'n') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE", (VOTE=>$no, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'e') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE", (VOTE=>$abst, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 's') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE",
                               (VOTE=>"$yes $or $no", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'h') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE",
                               (VOTE=>"$abst $or $yes", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'i') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_IFCLAUSE",
                               (VOTE=>"$abst $or $no", GROUP=>$groups[$i]));
    }
 
    if ($text1) {
      if ($firstrun) {
        $text .= "    " . $text1 . "\n";
        $firstrun = 0;
      } else  {
        $text .= $fill . $text1 . "\n";
      }
    }
  }
 
  @rule = split (//, $rules[$n-1]->{then_compl});
  $text .= "  ..." . UVmessage::get ("RULES_THEN") . "\n";
  $firstrun = 1;
 
  for (my $i=0; $i<@rule; $i++) {
    my $text1 = "";
    if ($rule[$i] eq 'J') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE", (VOTE=>$yes, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'N') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE", (VOTE=>$no, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'E') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE", (VOTE=>$abst, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'S') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE",
                               (VOTE=>"$yes $or $no", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'H') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE",
                               (VOTE=>"$abst $or $yes", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'I') {
      $fill = "    $and ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE",
                               (VOTE=>"$abst $or $no", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'j') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE", (VOTE=>$yes, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'n') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE", (VOTE=>$no, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'e') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE", (VOTE=>$abst, GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 's') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE",
                               (VOTE=>"$yes $or $no", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'h') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE",
                               (VOTE=>"$abst $or $yes", GROUP=>$groups[$i]));
    } elsif ($rule[$i] eq 'i') {
      $fill = "    $or ";
      $text1 = UVmessage::get ("RULES_THENCLAUSE",
                               (VOTE=>"$abst $or $no", GROUP=>$groups[$i]));
    }
 
    if ($text1) {
      if ($firstrun) {
        $text .= "    " . $text1 . "\n";
        $firstrun = 0;
      } else  {
        $text .= $fill . $text1 . "\n";
      }
    }
  }
  return $text . "\n";
}

1;
