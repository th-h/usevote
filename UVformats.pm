#----------------------------------------------------------------------
  package UVformats;
#----------------------------------------------------------------------

=head1 NAME

UVformats - Methoden zur Stringformatierung

=head1 SYNOPSIS

  value  <name-of-key>
  append <name-of-key>

  fill-left   <width> <character>
  fill-right  <width> <character>
  fill-center <width> <character>

  justify	 <name-of-key> <width>
  justify-before <name-of-key> <width>
  justify-behind <name-of-key> <width>
  
  first-words  <width>
  drop-words   <width>
  create-lines <width>

  multi-graph <width> <position> <count>
  multi-line  <width> <count>

  quote <string>
  replace <original-string> <replacement-string>
  sprintf <format-string>

  generate_date_header

=head1 DESCRIPTION

Dieses Modul stellt verschiedenste Methoden bereit, um die Strings in 
den Templates auf die unterschiedlichste Art zu formatieren. 

Dieses Modul beschraenkt sich auf die Beschreibung der Funktionen. Ihre
Einbindung wird in UVtemplates beschrieben.

=head1 FUNCTIONS

=over 3

=cut

#----------------------------------------------------------------------

use strict;
use vars qw(@ISA @EXPORT $VERSION $functions);

use Exporter;
$VERSION = 0.01;

@ISA = qw(Exporter);
@EXPORT = qw( getFunctions );

use Text::Wrap;
#use POSIX qw(strftime);
use Email::Date;

#----------------------------------------------------------------------

sub getFunctions{
  return $functions;
}

#----------------------------------------------------------------------
=item value

Gibt den Wert eines Schluessel zurueck. 

  new-key := value 'old-key' | <other-functions> ...

Diese Funktion sollte dann eingesetzt werden, wenn man einen virtuellen
Schluessel erzeugen will. D.h. der Bezeichner nicht im Template als
Schluessel vorhanden ist. Durch den Einsatz von value wird der Wert eines
anderen Schluessel kopiert und kann dann weiter formatiert werden.

=cut

sub value{
  my ($data, $value, $key) = @_;
  return $data->getKey($key);
}

#----------------------------------------------------------------------

=item append

Den Wert eines anderen Schluessels an den bisherigen String anhaengen.

  ... | append 'other-key' | ...

Per default wird als Trenner der beiden String ein Leerzeichen verwendet.
Soll dieses entfallen oder ein anderes Zeichen benutzt werden, so kann
ein dementsprechender drittere Parameter angegeben werden.

  ... | append 'other-key' ''  | ...
  ... | append 'other-key' '_' | ...

Im ersten Beispiel wird der Wert von C<other-key> nahtlos hinzugefuegt.
Im zweiten statt des Leerzeichens '_' benutzt.

=cut

sub append{
  my ($data, $value, $key, $sep) = @_;

  $sep = ' ' unless defined($sep);

  return $value. $sep. $data->getConvKey($key);
}

#----------------------------------------------------------------------

=item fill-left, fill-right, fill-center

Fuellt den String entsprechend mit Zeichen auf bis die gewuenschte
Laenge erreicht ist. Bei C<fill-left> werden die Zeichen vorranggestellt,
bei C<fill-right> angehaengt. C<fill-center> verteilt die Zeichen 
gleichmaessig vor und nach dem String.

  ... | fill-left 72 '.' | ...

Wird kein zweiter Parameter angegeben, wird automatisch das Leerzeichen
benutzt.

  ... | fill-right 60 | ...

Ist der String bereits laenger als gewuenscht, wird er nicht weiter
veraendert und auch nicht verkuerzt.

=cut

sub fill_left{ 
  my ($data, $value, $width, $char) = @_;

  $width ||= 72;
  $char  = ' ' unless (defined($char) && length($char) == 1);

  my $fill = $width - length($value);

  $value = $char x $fill . $value if ($fill > 0);

  return $value;
}

sub fill_right{ 
  my ($data, $value, $width, $char) = @_;

  $width ||= 72;
  $char  ||= ' ';

  my $fill = $width - length($value);

  $value .= $char x $fill if ($fill > 0);

  return $value;
}

sub fill_both{ 
  my ($data, $value, $width, $char) = @_;

  $width ||= 72;
  $char  ||= ' ';

  my $fill = $width - length($value);
  
  if ($fill > 0){
    my $left  = int($fill / 2);
    my $right = $fill - $left;

    $value = $char x $left . $value . $char x $right; 
  }

  return $value;
}

#----------------------------------------------------------------------

=item justify, justify-before, justify-behind

Fuegt zwischen den existierenden String und dem Wert des angegebenen 
Schluessel genau so viele Leerzeichen ein, damit die gewuenschte 
Stringlaenge erreicht wird.

  ... | justify-behind 'key' 72 | ...

C<justify-behind> haengt den Wert des Schluessel an das Ende des Strings,
C<justify-before> stellt es davor.

  justify-behind: existing-string.........value-of-key
  justify-before: value-of-key.........existing-string

C<justify> ist lediglich ein Alias auf C<justify-behind>.

Sind die beiden Strings zusammen länger als die gewuenschte
Zeilenlaenge, wird automatisch einen Zeilenbruch eingefuegt
und beide Zeilen entsprechend mit Leerzeichen gefuellt.

  very-very-very-long-existing-string.........\n
  ...................and-a-too-long-new-string

=cut

sub justify_behind{
  my ($data, $value, $key, $width) = @_;
  return _justify( $value, $data->getConvKey($key), $width);
}

sub justify_before{
  my ($data, $value, $key, $width) = @_;
  return _justify( $data->getConvKey($key), $value, $width);
}

sub _justify{
  my ($lval, $rval, $width) = @_;

  my $sep = ' ';

  if (length($lval.$rval) >= $width ){
    # wir basteln zwei zeilen
    $lval .= $sep x ($width - length($lval));
    $rval = $sep x ($width - length($rval)) . $rval;

    return $lval."\n".$rval;

  }else{
    my $fill = $width - length($lval) - length($rval);
    return $lval . $sep x $fill . $rval;
  }
}

#----------------------------------------------------------------------

=item first-words

Gibt nur die ersten Worte eines Strings zurueck, die vollstaendig
innerhalb der angegebenen Laenge liegen.

=cut

sub first_words{
  my ($data, $value, $width) = @_;

  my @words = split('\s+', $value);
  my $string;

  $string .= shift(@words);

  while(@words && (length($string) + length($words[0]) + 1) < $width){
    $string .= ' ' . shift(@words);
  }

  return $string;
}

=item drop-words

Alle Woerter am Anfang des Strings entfernen, die komplett innerhalb
der angegebenen Laenge liegen.

=cut

sub drop_words{
  my ($data, $value, $width) = @_;

  my @words = split('\s+', $value);

  # das erste "Wort" immer verwerfen, egal wie lang es ist
  my $first  = shift(@words);
  my $length = length($first);

  while (@words && ( $length + length($words[0]) + 1 ) < $width ){
    $length += length($words[0]) + 1;
    shift(@words);
  }

  return join(' ', @words);
}

=item create-lines

Zerlegt einen String in einen Array, in dem die einzelnen Zeilen nicht
laenger als die gewuenschte Anzahl Zeichen sind.

  absatz := value 'key' | create-lines 72 

Mit Hilfe dieser Funktion ist es moeglich, ueberlange Zeilen zu Absatzen
umzuformatieren.

Die Funktion erzeugt intern eine Liste, die jeweils den Schluessel C<line>
mit dem entsprechenden String als Wert enthaelt. 

Im Template wird der so Absatz dann mit Hilfe des Schleifen-Syntax
eingebunden:

  [@absatz|[line]\n]

Achtung! Da die Funktion keinen String zurueckgibt, sollte sie am Ende
der Kette stehen, da die normalen Formatierungsfunktionen einen String
als Input erwartern!

=cut

sub create_lines{
  my ($data, $value, $width) = @_;

  my @words = split('\s+', $value);

  my @lines;

  while (@words){
    my $string .= shift(@words);

    while(@words && (length($string) + length($words[0]) + 1) < $width){
      $string .= ' ' . shift(@words);
    }

    my $new = $data->new( line => $string );
    push(@lines, $new);
  }

  return \@lines;
}

#----------------------------------------------------------------------

=item multi-graph, multi-line

Spezielle Funktionen, um eine bestimmte graphische Ausgabe fuer
Votings mit mehreren Abstimmungspunkten zu erzeugen:

  Punkt 1 --------------------------+
  Punkt 2a ------------------------+|
  Punkt 2b -----------------------+||
  Punkt 3 -----------------------+|||
                                 ||||
  Name of Voter 1                jjnn
  Name of Voter 2                nnjj

C<multi-graph> ist hierbei für die Formatierung der einzelnen Abstimmungspunkte 
zustaendig.

  multi-graph 'key' 'width' 'pos-key' 'max-key'

Der erste Parameter gibt den Schluessel an, dessen Wert als Abstimmungspunkt
ausgegeben werden soll. C<width> die Laenge des zu erzeugenden Strings.
C<pos-key> und C<max-key> sind die Namen der Schluessel, in denen stehen
muss, um den wievielten Abstimmungspunkt es sich handelt (per default 'pos')
und wieviele Abstimmungspunkte es insgesamt gibt ('anzpunkte').

C<multi-line> erzeugt einfach nur einen String in der gewuenschten
Laenge, der entsprechend der Anzahl der Abstimmungspunkte mit '|'
abschliesst.

=cut

sub mgraph{
  my ($data, $value, $width, $pkey, $okey) = @_;
  return unless $data;

  my $pos = $data->getKey($pkey || 'pos');
  my $of  = $data->getKey($okey || 'anzpunkte');

  my $gfx = '';
  
  $gfx = ' ---'.'-' x ($of-$pos) .'+'. '|' x ($pos - 1) if ($pos && $of);

  if (length($value.$gfx) < $width){
    $value = ' ' x ($width - length($value.$gfx)) . $value . $gfx;

  }elsif (length($value.$gfx) > $width){
    my @lines = _wrap($value, $width - length($gfx));
   
    $value = shift(@lines) . $gfx;
    $value = ' ' x ($width - length($value)) . $value;

    # Hilfzeile erzeugen
    $gfx = '    '.' ' x ($of-$pos) . '|' x ($pos) if ($pos && $of);

    foreach my $line (@lines){
      $value .= "\n".' ' x ($width - length($line.$gfx)) . $line . $gfx;
    }
  }

  return $value;
}

sub mgline{
  my ($data, undef, $width, $okey) = @_;
  return unless $data;

  my $of = $data->getKey($okey || 'anzpunkte') || 0;

  return ' ' x ($width - $of) . '|' x $of;
}


sub _wrap{
  my ($string, $width) = @_;

  my @words = split('\s+', $string);

  my @lines;

  while (@words){
    my $line .= shift(@words);

    while(@words && (length($line) + length($words[0]) + 1) < $width){
      $line .= ' ' . shift(@words);
    }

    push(@lines, $line);
  }

  return @lines;
}


#----------------------------------------------------------------------

=item quote

Stellt in einem (mehrzeiligem) String jeder Zeile den gewuenschten
Quotestring voran.

  body := value 'body' | quote '> '

=cut

sub quote{
  my ($data, $value, $quotechar) = @_;

  $quotechar = '> ' unless defined($quotechar);

  $value =~ s/^/$quotechar/mg;
  return $value;
}


#----------------------------------------------------------------------

=item replace

Ersetzt in einem String ein oder mehrere Zeichen durch eine beliebige
Anzahl anderer Zeichen. Diese Funktion kann z.B. genutzt werden, um
beim Result die Mailadressen zu verfremden (Schutz vor Adress-Spidern).

  mail := value 'mail' | replace '@' '-at-'

=cut

sub replace{
  my ($data, $value, $original, $replacement) = @_;

  $original = ' ' unless defined($original);
  $replacement = ' ' unless defined($replacement);

  $value =~ s/\Q$original\E/$replacement/g;
  return $value;
}


#----------------------------------------------------------------------

=item sprintf

Gibt Text oder Zahlen mittels der Funktion sprintf formatiert aus
(siehe "man 3 sprintf" oder "perldoc -f sprintf").

  proportion := value 'proportion' | sprintf '%6.3f'

=cut

sub sprintf{
  my ($data, $value, $format) = @_;

  $format = '%s' unless defined($format);

  return sprintf($format, $value);
}


#----------------------------------------------------------------------

=item generate_date_header

Gibt ein Datum im RFC822-Format zur Verwendung im Date:-Header einer
Mail aus.

  date := generate_date_header

=cut

sub generate_date_header{
  my ($data, $value, $format) = @_;
  #return strftime('%a, %d %b %Y %H:%M:%S %z', localtime);
  return format_date;
}

#----------------------------------------------------------------------

=item generate_msgid

Gibt eine Message-ID im RFC822-Format zur Verwendung im Message-ID:-Header
einer Mail aus.

  msgid := generate_msgid

=cut

sub generate_msgid{
  return ("<".$$.time().rand(999)."\@".$UVconfig::config{fqdn}.">");
}


#----------------------------------------------------------------------

BEGIN{
  %UVconfig::functions = ( %UVconfig::functions,
    value 		=> \&value,
    append		=> \&append,

    'fill-left'  	=> \&fill_left,
    'fill-right' 	=> \&fill_right,
    'fill-both'  	=> \&fill_both,

    justify		=> \&justify_behind,
    'justify-behind'	=> \&justify_behind,
    'justify-before' 	=> \&justify_before,

    'first-words' 	=> \&first_words,
    'drop-words' 	=> \&drop_words,

    'create-lines' 	=> \&create_lines,

    'multi-graph' 	=> \&mgraph,
    'multi-line'  	=> \&mgline,

    'quote'             => \&quote,
    'replace'           => \&replace,
    'sprintf'           => \&sprintf,

    'generate-date-header' => \&generate_date_header,
    'generate-msgid'    => \&generate_msgid
  );
}

1;

#----------------------------------------------------------------------

=back

=head1 SEE ALSO

L<UVtemplate>

=head1 AUTHOR

Cornell Binder <cobi@dex.de>
Marc Langer <usevote@marclanger.de>
