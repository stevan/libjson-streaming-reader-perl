package JSON::Streaming::Tokens;

use strict;
use warnings;

our $VERSION = '0.01';

our ( @EXPORTS, %TOKEN_MAP, %TOKEN_LKUP );

BEGIN {
    %TOKEN_MAP = (
        START_OBJECT   => 0b00000000001,
        END_OBJECT     => 0b00000000010,
        START_ARRAY    => 0b00000000100,
        END_ARRAY      => 0b00000001000,
        START_PROPERTY => 0b00000010000,
        END_PROPERTY   => 0b00000100000,
        ADD_STRING     => 0b00001000000,
        ADD_NUMBER     => 0b00010000000,
        ADD_BOOLEAN    => 0b00100000000,
        ADD_NULL       => 0b01000000000,
        ERROR          => 0b10000000000,
    );

    %TOKEN_LKUP = reverse %TOKEN_MAP;
    @EXPORTS    = keys %TOKEN_MAP;

    foreach my $name ( keys %TOKEN_MAP ) {
        no strict 'refs';
        *{$name} = sub { $TOKEN_MAP{ $name } };
    }
}

sub import { (shift)->import_into( scalar caller, @_ ) }

sub import_into {
    my (undef, $into, @exports) = @_;
    @exports = @EXPORTS unless @exports;
    no strict 'refs';
    # it helps to have the token types in the tests ...
    *{$into.'::'.$_} = \&{$_} foreach @exports;
}

sub dump_token ($) {
    my ($type, @args) = @{$_[0]};
    join ' ' => $TOKEN_LKUP{ $type }, @args
}

1;

__END__

=pod

=cut
