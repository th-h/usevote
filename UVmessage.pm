# UVmessages: parses resource strings and substitutes variables
# Used by all components

package UVmessage;

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(get);

# Module version
$VERSION = "0.1";

sub get {
  my ($key, %param) = @_;
 
  my $string = $UVconfig::messages{$key} || return '';
 
  while ($string =~ m/\$\{([A-Za-z0-9_-]+)\}/) {
    my $skey = $1;
    my $sval = $param{$skey};
    $sval = '' unless defined($sval);
 
    $string =~ s/\$\{$skey\}/$sval/g;
  }
 
  return $string;
}
 
1;
