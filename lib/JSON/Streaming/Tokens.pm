package JSON::Streaming::Tokens;

use strict;
use warnings;

our $VERSION = '0.01';

use constant START_OBJECT   => 0b00000000001;
use constant END_OBJECT     => 0b00000000010;
use constant START_ARRAY    => 0b00000000100;
use constant END_ARRAY      => 0b00000001000;
use constant START_PROPERTY => 0b00000010000;
use constant END_PROPERTY   => 0b00000100000;
use constant ADD_STRING     => 0b00001000000;
use constant ADD_NUMBER     => 0b00010000000;
use constant ADD_BOOLEAN    => 0b00100000000;
use constant ADD_NULL       => 0b01000000000;
use constant ERROR          => 0b10000000000;

our @EXPORTS = qw[
    START_OBJECT
    END_OBJECT
    START_ARRAY
    END_ARRAY
    START_PROPERTY
    END_PROPERTY
    ADD_STRING
    ADD_NUMBER
    ADD_BOOLEAN
    ADD_NULL
    ERROR
];

sub import { (shift)->import_into( scalar caller, @_ ) }

sub import_into {
    my (undef, $into, @exports) = @_;
    @exports = @EXPORTS unless @exports;
    no strict 'refs';
    # it helps to have the token types in the tests ...
    *{$into.'::'.$_} = \&{$_} foreach @exports;
}

1;

__END__

=pod

=cut
