package JSON::Streaming::Tokens;

use strict;
use warnings;

use Scalar::Util;

our $VERSION = '0.01';

our ( @EXPORTS, %TOKEN_MAP );
BEGIN {
    %TOKEN_MAP = (
        START_OBJECT   => Scalar::Util::dualvar( 0b00000000001, 'START_OBJECT'   ),
        END_OBJECT     => Scalar::Util::dualvar( 0b00000000010, 'END_OBJECT'     ),
        START_ARRAY    => Scalar::Util::dualvar( 0b00000000100, 'START_ARRAY'    ),
        END_ARRAY      => Scalar::Util::dualvar( 0b00000001000, 'END_ARRAY'      ),
        START_PROPERTY => Scalar::Util::dualvar( 0b00000010000, 'START_PROPERTY' ),
        END_PROPERTY   => Scalar::Util::dualvar( 0b00000100000, 'END_PROPERTY'   ),
        ADD_STRING     => Scalar::Util::dualvar( 0b00001000000, 'ADD_STRING'     ),
        ADD_NUMBER     => Scalar::Util::dualvar( 0b00010000000, 'ADD_NUMBER'     ),
        ADD_BOOLEAN    => Scalar::Util::dualvar( 0b00100000000, 'ADD_BOOLEAN'    ),
        ADD_NULL       => Scalar::Util::dualvar( 0b01000000000, 'ADD_NULL'       ),
        ERROR          => Scalar::Util::dualvar( 0b10000000000, 'ERROR'          ),
    );

    @EXPORTS = keys %TOKEN_MAP;

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
    *{$into.'::'.$_} = \&{$_} foreach @exports;
}

1;

__END__

=pod

=cut
