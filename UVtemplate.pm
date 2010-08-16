#----------------------------------------------------------------------
package UVtemplate;
#----------------------------------------------------------------------

=head1 NAME

UVtemplate - Templateverarbeitung und String-Formatierungen

=head1 SYNOPSIS

  use UVtemplate;

  $plate  = UVtemplate->new([%keys]);

            $plate->setKey(%keys);
  $item   = $plate->addListItem($name, %keys);

  $string = $plate->processTemplate($file);

=head1 DESCRIPTION

Mit Hilfe von UVtemplate, wird die komplette Aufbereitung und 
Formatierung der Programmausgaben nicht nur ausgelagert sondern
auch so flexibiliert, dass sie jederzeit angepasst werden kann,
ohne das im eigentlichen Programmcode veraendert werden muss.

Auf Programmseite wird eine Datenstruktur mit Schluessel-Wert
Paaren erzeugt. In den Template-Dateien werden dann spaeter die
jeweiligen Schluessel, durch ihre im Programm festgelegten 
Werte ersetzt. Zusaetzlich ist es moeglich Schluessel zu Listen
zusammenzufassen.

Da es sich bei den Templates um Ascii-Texte handelt, gibt es 
zusaetzlich die Moeglichkeit die Werte der Schluessel zuformatieren
um eine einheitliche Ausgabe zu ermoeglichen. D.h. es kann z.B. durch 
das Anhaengen von Leerzeichen dafuer gesorgt werden, das ein Schluessel
einer Liste immer 60 Zeichen lang ist um ansehnliche Tabellen auszugeben.

=head1 FUNCTIONS

=over 3

=cut

#----------------------------------------------------------------------

use strict;
use vars qw( $VERSION $functions @dirs);
use UVconfig;

$VERSION = 0.1;

#----------------------------------------------------------------------

=item new

Eine neues Objekt vom Typ UVtemplate anlegen. 

  my $plate = UVtemplate->new();

Als Parameter koennen gleich beliebig viele Schluessel-Wert-Paare
uebergeben werden.

=cut

sub new{
  my $class = shift;
  my $self  = {};

  if (ref($class)){
    $self->{FATHER} = $class;
    bless($self, ref($class));

  }else{
    bless($self, $class);
  }

  $self->setKey(@_);

  return $self;
}

=item setKey

Schluessel und zugehoerige Werte im Objekt speichern.

  $plate->setKey( vote-addr => 'to-vote@dom.ain' );
  $plate->setKey( datenschutz => 1);

Ist der zu speichernde Schluessel bereits vorhanden, wird er
durch den neuen Wert ueberschrieben.

=cut

sub setKey{
  my $self = shift;
  my %param = @_;

  foreach my $key (keys(%param)){
    $self->{KEYS}->{$key} = $param{$key};
  }
}

=item addListItem

Erzeugt ein neues Objekt vom Typ UVtemplate und fuegt es der 
angebenen Liste hinzu.

  $plate->addListItem(name => 'Musterman', email => 'em@il');

Da sich Listen wie normale Schluessel-Wert Paare verhalten, 
wird die Liste als Array ueber UVtemplate-Objekte unter dem
definiertem Schluessel abgelegt. Ist dieser Schluessel bereits
gesetzt und enthaehlt keinen Array, so bricht die Funktion ab.

=cut

sub addListItem{
  my $self = shift;
  my $list = shift;

  # pruefen ob key angegeben ist und falls key vorhanden
  # eine liste vorliegt
  return unless ($list && (not($self->{KEYS}->{$list}) ||
    UNIVERSAL::isa($self->{KEYS}->{$list}, 'ARRAY')));

  # neues Element erzeugen
  my $new = $self->new( @_ );

  # an listen anhaengen
  push(@{$self->{KEYS}->{$list}}, $new);

  # referenz zurueckgeben
  return $new;
}

=item getKey($key)

Den Wert eines Schluessel ermitteln.

  my $value = $plate->getKey('email');

Ist der Wert im Objekt nicht gesetzt, wird - falls es sich um ein
Element einer Liste handelt - rekursiv beim Vater weiter gesucht.

So stehen allen Kindern auch die Schluessel-Wert Paare ihrer Eltern
zur Verfuegung.

Zum Schluss wird noch geprueft, ob der Schluessel in usevote.cfg
gesetzt wurde. Dadurch sind alle Konfigurationsoptionen direkt
in Templates nutzbar.

=cut

sub getKey{
  my $self = shift;
  my $key  = $_[0];

  my $value;

  do{
    $value = $self->{KEYS}->{$key};
    $self  = $self->{FATHER};

  }while(!defined($value) && $self);

  if (!defined($value) && defined($config{$key})) {
    $value = $config{$key};
  }

  return $value;
}

#----------------------------------------------------------------------

sub getRules{
  my $self = shift;

  do{
    return $self->{RULES} if ($self->{RULES});
    $self = $self->{FATHER};
  }while($self);

  return;
}

=item getConvKey{

Einen Format ermitteln.

  my $value = $plate->getConvKey('email-adresse');

Diese Funktion ueberprueft ob eine Formatierung mit den entsprechenden
Schluessel definiert ist und ruft dementsprechend die dort definierten
Funktionen ueber der Datenstruktur auf.

Ist kein solches Format definiert, wird der Wert des Schluessel mit
einem solchen Namen zurueckgegeben. (Es wird intern getKey aufgerufen).

=cut

sub getConvKey{
  my $self = shift;
  my $key  = $_[0] || return;

  my $rules = $self->getRules();
  my $value = $self->getKey($key);
  
  $value = '' unless (defined($value));

  if ($rules && ($rules->{$key})){
    my @funcs = @{$rules->{$key}};

    foreach my $func (@funcs){
      my ($name, @params) = @$func;
  
      if ($functions->{$name}){
        $value = $functions->{$name}->($self, $value, @params);
    
      }else{
        print STDERR "format function '$name' not found!\n";
      }
    }
  }

  return $value;
}

#----------------------------------------------------------------------

=item processTemplate

Daten des Objekts in ein Template einfuegen.

  my $string = $plate->processTemplate('template/info.txt');

Die angebene Datei wird eingelesen, zerlegt und danach
die enstprechenden Platzhalter durch die (formatierten) 
Werte aus der Datenstruktur ersetzt.

=cut

sub processTemplate{
  my $self = shift;
  my $file = $_[0] || return;

  my ($rules, $body) = _split_file($file);

  # konvertierungsregeln parsen
  $self->{RULES} = _parse_rules($rules);

  # template zerlegen (zuerst fuehrende leerzeilen entfernen!)
  $body =~ s/^\n+//s;	
  my $token = UVtemplate::scan->new(string => $body);

  # daten einsetzen
  return $token->processData($self);
}

sub _split_file{
  my $file = $_[0] || return;

  my $fname = _complete_filename($file);

  unless ($fname){
    print STDERR "couldnt find '$file'\n";
    return;
  }

  my (@rules, @body);

  open(PLATE, $fname);
  my @lines = <PLATE>;
  close(PLATE);

  my $body = 0;

  foreach my $line (@lines){
    if ($line =~ m/^== TEMPLATE/){
      $body = 1;

    }else{
      if ($body){
        push(@body, $line);

      }else{
        push(@rules, $line);
      }
    }
  }

  # falls kein Separator definiert war, wird der komplette Text
  # als Body interpretiert. Es gibt keine Regeln!
  
  unless ($body){
    @body  = @rules;
    @rules = ();
  }

  # und nun wieder zu Strings zusammenpappen
  return (join('', @rules), join('', @body));
}

sub _complete_filename{
  my $file = $_[0] || return;

  my $dirs = $UVconfig::config{templatedir};
     @dirs = split(/\s*,\s*/, $dirs) if $dirs;

  my $fname;

  foreach my $dir (@dirs, '.'){
    $fname = "$dir/$file";
    return $fname if (-r $fname);
  }
}

#----------------------------------------------------------------------
# Konvertierungs-Regeln
#----------------------------------------------------------------------

sub _parse_rules{
  my $string = $_[0] || return;

  my @stack;
  my $rules = {};

  my $this = [];
    
  while (length($string) > 0){
    _strip_chars(\$string);

    my $token = _parse_token(\$string);

    if ($token){
      push(@stack, $token);
      
      _strip_chars(\$string);

      if ($string =~ s/^:=//){
        # neuen Schluessel vom Stack holen
        my $key = pop(@stack);
	
	# restlichen Stack auf alten Schluessel packen
	push(@$this, [ @stack ]);
	@stack = ();

	# neuen Schluessel anlegen
	$rules->{$key} = $this = [];

      }elsif($string =~ s/^\|//){
        # stack auf schluessel packen
	push(@$this, [ @stack ]);
	@stack = ();
      }

    }else{
      # fehlermeldung ausgeben (nacharbeiten!)
      print STDERR "Syntaxerror in Definition\n";
      return;
    }
  }

  # den Rest vom Stack abarbeiten
  push(@$this, [ @stack ]) if @stack;

  return $rules;
}

sub _strip_chars{
  my $line = $_[0] || return;

  # führenden whitespace entfernen
  $$line =~ s/^\s+//;

  # kommentare bis zum nächsten Zeilenumbruch entfernen
  $$line =~ s/^#.*$//m;
}


sub _parse_token{
  my $string = shift;

  if ($$string =~ s/^(["'])//){
    return _parse_string($string, $1);

  }else{
    return _parse_ident($string);
  }
}


sub _parse_string{
  my ($string, $limit) = @_;

  my $value;

  while ($$string){
    if ($$string =~ s/^$limit//){
      $$string =~ s/^\s*//;
      return $value;

    }elsif($$string =~ s/^\\(.)//){
      $value .= $1;
    
    }else{
      $$string =~ s/^[^$limit\\]*//;
      $value .= $&;
    }
  }

  # end of line 
  return $value;
}


sub _parse_ident{
  my $string = shift;

  if ($$string =~ s/^([A-Za-z0-9-]+)\s*//){
    return $1;
  }

  return;
}

#----------------------------------------------------------------------

BEGIN{
  $functions = \%UVconfig::functions;
}

#----------------------------------------------------------------------
#----------------------------------------------------------------------
package UVtemplate::scan;
#----------------------------------------------------------------------
#----------------------------------------------------------------------

sub new{
  my $class = shift;
  my %param = @_;

  my $self  = {};
  bless($self, $class);

  $self->parseFile($param{file})     if defined($param{file});
  $self->parseString($param{string}) if defined($param{string});

  return $self;
}

#----------------------------------------------------------------------

sub processData{
  my $self = shift;
  my $data = $_[0];

  return _process_data($self->{toks}, $data);
}

sub _process_data{
  my ($toref, $data) = @_;
  
  my $string = '';
  my $length = 0;
  my $empty  = 0;

  foreach my $token (@$toref){
    if (ref($token)){
      my $before = length($string);
         $empty  = 0;
    
      if ($token->[0] eq 'VAR'){
        my $value = $data->getConvKey(_process_data($token->[1], $data));
      
        if (defined($value) && length($value)){
          $string .= $value;

	}else{
	  $string .= _process_data($token->[2], $data);
	}

      }elsif($token->[0] eq 'IF'){
        if ($data->getConvKey(_process_data($token->[1], $data))){
          $string .= _process_data($token->[2], $data);

	}else{
          $string .= _process_data($token->[3], $data);
	}
     
      }elsif($token->[0] eq 'LOOP'){
        my $nodes = $data->getConvKey(_process_data($token->[1], $data));
	my @block;

        if ($nodes && (UNIVERSAL::isa($nodes, 'ARRAY'))){
	  foreach my $node (@$nodes){
            push(@block, _process_data($token->[2], $node));
	  }

	  $string .= join(_process_data($token->[3], $data), @block);
	}
      }

      $length = length($string);
      $empty  = 1 if ($before == $length);

    }else{
      if ($empty && ($string =~ m/(\n|^)$/s)){
        $empty = 0;		# Falls die letzte Zeile nur aus einem Token
        $token =~ s/^\n//s;	# ohne Inhalt bestand, wird die Zeile entfernt
      }
    
      $string .= $token;
    }
  }

  return $string;
}

#----------------------------------------------------------------------
# Den String in einen Syntaxbaum abbilden

sub _parse_token_string{
  my $self   = shift;
  my ($string, $intern) = @_;

  my (@token, $toref); 
  my $data = '';

  while ($string){
    if ($intern && $string =~ m/^(\]|\|)/){
      last;
  
    }elsif ($string =~ s/^\[//){
      my $orig = $string;
    
      ($toref, $string) = $self->_parse_token($string);

      if (@$toref){
        push (@token, $data) if $data;
	$data = '';

        push(@token, $toref) 
      }

      if ($string !~ s/^\]//){
        my $pos = $self->{lines} - _count_lines($orig) + 1;

        print STDERR "Scanner: [$pos] missing right bracket\n";
	return (\@token, $string);
      }
      
    }elsif($string =~ s/^\\n//s){
      $data .= "\n";

    }elsif($string =~ s/^\\(.)//s){
      $data .= $1;

    }elsif($intern){
      $string =~ s/^([^\]\[\|\\]+)//s;
      $data  .= $1;
    
    }else{
      $string =~ s/^([^\[\\]+)//s;
      $data  .= $1;
    } 
  }

  push (@token, $data) if length($data);
  return (\@token, $string)
}


sub _parse_token{
  my $self   = shift; 
  my $string = $_[0];

  my @token = ();
  
  if ($string =~ s/^\$//s){ 
    # Variablen - Syntax: [$key[|<else>]] 
    push (@token, 'VAR');

  }elsif ($string =~ s/^\?//s){
    # Bedingung - Syntax: [?if|<then>[|<else>]]
    push (@token, 'IF');

  }elsif ($string =~ s/^\@//s){
    # Schleifen - Syntax: [@key|<block>[|<sep>]]
    push (@token, 'LOOP');

  }elsif ($string =~ s/^#//s){
    # Kommentare - Syntax: [# ... ]
    $string = _parse_comment($string);

    return (\@token, $string);
    
  }else{
    print STDERR "unknown token in template\n";
  }

  my $toref;

  ($toref, $string) = $self->_parse_token_string($string, 1);
  push(@token, $toref);

  while ($string =~ s/^\|//){
    ($toref, $string) = $self->_parse_token_string($string, 1);
    push(@token, $toref);
  }

  return (\@token, $string);
}


sub _parse_comment{
  my $string = $_[0];
  my $count  = 1;

  while($string && $count) {
    $string =~ s/^[^\[\]\\]+//s; # alles außer Klammern und Backslash wegwerfen
    $string =~ s/^\\.//;	# alles gesperrte löschen

    $count++ if $string =~ s/^\[//;
    $count-- if $string =~ s/^\]//;
  }

  $string = ']'.$string if !$count;
  return $string;
}

#----------------------------------------------------------------------

sub parseString{
  my $self = shift;
  my $text = $_[0];  

  $self->{lines} = _count_lines($text);
  my ($toref, $rest) = $self->_parse_token_string($text);

  $self->{toks} = $toref;
}


sub _count_lines{
  return 0 unless defined($_[0]);

  my ($string, $count) = ($_[0], 1);
  $count++ while($string =~ m/\n/sg);

  return $count;
}

#----------------------------------------------------------------------
#----------------------------------------------------------------------
#----------------------------------------------------------------------

1;

=back

=head1 SYNTAX

Eine Templatedatei besteht aus zwei Teilen. Am Anfang werden die 
Formatierungen bestimmter Schluessel definiert und nach einem
Trenner folgt der eigentlich Template-Koerper, der dann von Programm
bearbeitet und ausgegeben wird.

  format-key := function1 param | function2 param

  == TEMPLATE ====================================

  Ich bin nun das eigentliche Template:

  format-key: [$format-key]

Der Trenner beginnt mit den Zeichen '== TEMPLATE' danach koennen
beliebige Zeichen folgen um die beiden Sektionen optisch voneinander 
abzugrenzen.

Wenn es keine Formatierungsanweisungen gibt, kann der Trenner auch
weggelassen werden. D.h. wenn kein Trenner gefunden wird, wird der
komplette Text als Template-Koerper betrachtet.

=head2 Template-Koerper

Im Template-Koerper werden die zu ersetzenden Token durch eckige
Klammern abgegrenzt. Sollen eckige Klammern im Text ausgegeben werden
muessen diese durch einen Backslash freigestellt werden.

  [$termersetzung] [@schleife] nur eine \[ Klammer

=over 3

=item $ - Termersetzung 

Ersetzt den Token durch den Wert des angegeben Schluessels.

  [$formatierung] [$schluessel]

Es wird zuerst nach einer Formatierung mit den entsprechenden
Bezeichner gesucht. Ist dies der Fall werden die entsprechenden
Funktionen ausgefuehrt.

Kann kein Format gefunden, wird direkt in der Datenstruktur
nach einem Schhluessel mit dem angegeben Bezeichner gesucht
und sein Wert eingesetzt.

Schlussendlich ist es noch moeglich einen default-Wert zu
definieren, der eingesetzt wird, wenn keiner der obigen Wege
erfolgreich war.

  Hallo [$name|Unbekannter]!

=item ? - bedingte Verzeigung

Ueberprueft ob der Wert des angegebenen Formats/Schluessel
boolsch WAHR ist. Dementsprechend wird der then oder else
Block eingefuegt.

  [?if|then|else] oder auch nur [?if|then]

Die then/else Bloecke werden natuerlich auch auf Tokens
geparst und diese dementsprechend ersetzt.

=item @ - Schleifen/Listen

Der nachfolgende Textblock wird fuer alle Elemente des durch
den Schluessel bezeichneten Arrays ausgefuehrt und eingefuegt.

  [@schluessel|block] oder [@schluessel|block|sep]

Als zweiter Parameter kann ein Separtor definiert werden, mit
dem sich z.B. kommaseparierte Listen erzeugen lassen, da der
Separator eben nur zwischen den Element eingefuegt wird.

Auch fuer Schleifen koennen Formatierungen genutzt werden.
Allerdings darf kein String zurueckgegeben werden, sondern
ein Array mit einer Menge von UVtemplate-Objekten.

=item # - Kommentare

Token die nach der Bearbeitungen entfernt werden.

  [# mich sieht man nicht]

=item Sonstiges

Um in Listen einen Zeilenumbruch zu erzwingen, muss 
lediglich ein '\n' eingefuegt werden, falls eine kompakte
Definition der Liste erfolgen soll.

  [@names|[name] [email]\n]

=back

=head2 Formatierungen

Eine Formatierung besteht eigentlich nur aus dem entsprechenden
Namen und einer beliebigen Anzahl von Funktionsaufrufen:

  format := funktion param1 "param 2" | funktion param

Aehnlich der Unix-Shell-Funktionalitaet, wird dabei die Ausgabe
einer Funktion an die folgende weitergeleitet. So ist es moeglich
verschiedenste simple Formatierungen zu kombinieren um nicht fuer
jeden Spezialfall eine neue Funktion schreiben zu muessen.

Die jeweilige Formatierungsfunktion erhaelt als Input die Datenstruktur,
den Output der vorherigen Funktion und die definierten Parameter in der
entsprechenden Reihenfolge.

Zahlen und einfache Bezeichner koennen direkt definiert werden. Sollen
Sonderzeichen oder Leerzeichen uebergeben werden muessen diese gequotet
werden. Dazu kann ' also auch " verwendet werden.

Die Funktionen geben im Allgemeinen einen String zurueck. Im Rahmen
von Listen können auch Arrays uebergeben werden.

Die erste Funktion duerfte ueblicherweise 'value' sein. Sie gibt den
des angegeben Schluessel zurueck, der dann von den folgenden Funktionen
definiert wird.

  name-60 := value name | fill-right 60

Das Format "name-60" definiert also den Wert des Schluessel "name" der
um Leerzeichen aufgefuellt wird, bis eine Laenge von 60 Zeichen 
erreicht wird.

  name-email := value name | justify-behind mail 72

"name-email" resultiert in einem String, der zwischen den Werten
von "name" und "email" genau so viele Leerzeichen enthaelt, damit
der gesamte String 72 Zeichen lang ist.

Wird dieses Format in einer Liste angewandt, erhaelt man eine Tabelle
in der die linke Spalte linksbuendig und die rechte Spalte entsprechend
rechtsbuendig ist.

Soweit ein kleiner Ueberblick ueber die Formatierungen. 
Ausfuehrliche Funktionsbeschreibungen und weitere Beispiele finden
sich in der Dokumentation des Moduls UVformat.

=head1 SEE ALSO

L<UVformats>

=head1 AUTHOR

Cornell Binder <cobi@dex.de>
