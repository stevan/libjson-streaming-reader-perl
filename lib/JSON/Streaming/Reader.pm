package JSON::Streaming::Reader;

use strict;
use warnings;

use IO::Scalar;
use UNIVERSAL::Object;

use JSON::Streaming::Tokens;

our $VERSION = '0.01';

use constant ROOT_STATE   => {};
use constant ESCAPE_CHARS => {
    b => "\b",
    f => "\f",
    n => "\n",
    r => "\r",
    t => "\t",
    "\\" => "\\",
    "/" => "/",
    '"' => '"',
};

our @ISA; BEGIN { @ISA = ('UNIVERSAL::Object') }
our %HAS; BEGIN {
    %HAS = (
        stream      => sub { die 'A `stream` must be defined' },
        state       => \&ROOT_STATE,
        state_stack => sub { [] },
        used        => sub { 0 },
        buffer      => sub { undef },
        errored     => sub { 0 },
    )
}

## Constructors

sub for_stream {
    my ($class, $stream) = @_;
    $class->new( stream => $stream );
}

sub for_string {
    my ($class, $value) = @_;
    return $class->new( stream => IO::Scalar->new(ref $value ? $value : \$value) );
}

## pull API

sub get_token {
    my ($self) = @_;

    return undef if $self->{errored};

    my $token;
    my $need_comma = $self->made_value;

MAIN_LOOP:
    while (1) {
        _eat_whitespace( $self );
        my $char = _peek_char( $self );

        unless (defined($char)) {
            # EOF
            $token = $self->{state} == ROOT_STATE
                ? undef
                : [ ERROR, "Unexpected end of input" ];
            last MAIN_LOOP;
        }

        # If we've found more stuff while we're in the root state and we've
        # already seen stuff then there's junk at the end of the string.
        if ( $self->{state} == ROOT_STATE && $self->{used} ) {
            $token = [ ERROR, "Unexpected junk at the end of input" ];
            last MAIN_LOOP;
        }

        if ($char eq ',' && ! $self->done_comma) {
            if ($self->in_array || $self->in_object) {
                if ($self->made_value) {
                    unless ((_peek_char( $self ) // '') eq ',') {
                        $token = [ ERROR, 'Expected , but encountered '.($self->{buffer} //= 'EOF') ];
                        last MAIN_LOOP;
                    }
                    else {
                        undef $self->{buffer};
                    }
                    _set_done_comma( $self );
                    next;
                }
            }
            elsif ($self->in_property) {
                # If we're in a property then a comma indicates
                # the end of the property. We exit the property state
                # but leave the comma so that the next get_token
                # can still see it.
                unless ($self->made_value) {
                    $token = [ ERROR, "Property has no value" ];
                }
                else {
                    _pop_state( $self );
                    _set_made_value( $self );
                    $token = [ END_PROPERTY ];
                }
                last MAIN_LOOP;
            }
        }

        if ($char ne '}' && $self->in_object) {
            # If we're in an object then we must start a property here.
            my $name_token = _get_string_token( $self );

            # if the string tokenizer returns an error ...
            if ( $name_token->[0] == ERROR ) {
                $token = $name_token;
            }
            else {
                # otherwise ...
                unless ( $name_token->[0] == ADD_STRING ) {
                    $token = [ ERROR, "Expected string" ];
                }
                else {
                    _eat_whitespace( $self );
                    unless ((_peek_char( $self ) // '') eq ':') {
                        $token = [ ERROR, 'Expected : but encountered '.($self->{buffer} //= 'EOF') ];
                        last MAIN_LOOP;
                    }
                    else {
                        undef $self->{buffer};
                    }
                    my $property_name = $name_token->[1];
                    my $state = _push_state( $self );
                    $state->{in_property} = 1;
                    $token = [ START_PROPERTY, $property_name ];
                }
            }
            last MAIN_LOOP;
        }

        if ($char eq '{') {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected start of object" ];
            }
            else {
                unless ((_peek_char( $self ) // '') eq '{') {
                    $token = [ ERROR, 'Expected { but encountered '.($self->{buffer} //= 'EOF') ];
                    last MAIN_LOOP;
                }
                else {
                    undef $self->{buffer};
                }
                my $state = _push_state( $self );
                $state->{in_object} = 1;
                $token = [ START_OBJECT ];
            }
            last MAIN_LOOP;
        }
        elsif ($char eq '}') {
            if ( $self->done_comma ) {
                $token = [ ERROR, "Expected another property" ];
            }
            else {
                # If we're in a property then this also indicates
                # the end of the property.
                # We don't actually consume the } here, so the next
                # call to get_token will see it again but it will be
                # in the is_object state rather than is_property.
                if ($self->in_property) {
                    unless ($self->made_value) {
                        $token = [ ERROR, "Property has no value" ];
                    }
                    else {
                        _pop_state( $self );
                        _set_made_value( $self );
                        $token = [ END_PROPERTY ];
                    }
                    last MAIN_LOOP;
                }

                unless ($self->in_object) {
                    $token = [ ERROR, "End of object without matching start" ];
                }
                else {
                    unless ((_peek_char( $self ) // '') eq '}') {
                        $token = [ ERROR, 'Expected } but encountered '.($self->{buffer} //= 'EOF') ];
                        last MAIN_LOOP;
                    }
                    else {
                        undef $self->{buffer};
                    }
                    _pop_state( $self );
                    _set_made_value( $self );
                    $token = [ END_OBJECT ];
                }
            }
            last MAIN_LOOP;
        }
        elsif ($char eq '[') {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected start of array" ];
            }
            else {
                unless ((_peek_char( $self ) // '') eq '[') {
                    $token = [ ERROR, 'Expected [ but encountered '.($self->{buffer} //= 'EOF') ];
                    last MAIN_LOOP;
                }
                else {
                    undef $self->{buffer};
                }
                my $state = _push_state( $self );
                $state->{in_array} = 1;
                $token = [ START_ARRAY ];
            }
            last MAIN_LOOP;
        }
        elsif ($char eq ']') {
            unless ($self->in_array) {
                $token = [ ERROR, "End of array without matching start" ];
            }
            else {
                if ($self->done_comma) {
                    $token = [ ERROR, "Expected another value" ];
                }
                else {
                    unless ((_peek_char( $self ) // '') eq ']') {
                        $token = [ ERROR, 'Expected ] but encountered '.($self->{buffer} //= 'EOF') ];
                        last MAIN_LOOP;
                    }
                    else {
                        undef $self->{buffer};
                    }
                    _pop_state( $self );
                    _set_made_value( $self );
                    $token = [ END_ARRAY ];
                }
            }
            last MAIN_LOOP;
        }
        elsif ($char eq '"') {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected string value" ];
            }
            else {
                if ($need_comma && ! $self->done_comma) {
                    $token = [ ERROR, "Expected ," ];
                }
                else {
                    $token = _get_string_token( $self );
                }
            }
            last MAIN_LOOP;
        }
        elsif ($char eq 't') {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected boolean value" ];
            }
            else {
                if ($need_comma && ! $self->done_comma) {
                    $token = [ ERROR, "Expected ," ];
                }
                else {
                    foreach my $c (qw[ t r u e ]) {
                        unless ((_peek_char( $self ) // '') eq $c) {
                            $token = [ ERROR, 'Expected '.$c.' but encountered '.($self->{buffer} //= 'EOF') ];
                            last MAIN_LOOP;
                        }
                        else {
                            undef $self->{buffer};
                        }
                    }
                    _set_made_value( $self );
                    $token = [ ADD_BOOLEAN, 1 ];
                }
            }
            last MAIN_LOOP;
        }
        elsif ($char eq 'f') {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected boolean value" ];
            }
            else {
                if ($need_comma && ! $self->done_comma) {
                    $token = [ ERROR, "Expected ," ];
                }
                else {
                    foreach my $c (qw[ f a l s e ]) {
                        unless ((_peek_char( $self ) // '') eq $c) {
                            $token = [ ERROR, 'Expected '.$c.' but encountered '.($self->{buffer} //= 'EOF') ];
                            last MAIN_LOOP;
                        }
                        else {
                            undef $self->{buffer};
                        }
                    }
                    _set_made_value( $self );
                    $token = [ ADD_BOOLEAN, 0 ];
                }
            }
            last MAIN_LOOP;
        }
        elsif ($char eq 'n') {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected null" ];
            }
            else {
                if ($need_comma && ! $self->done_comma) {
                    $token = [ ERROR, "Expected ," ];
                }
                else {
                    foreach my $c (qw[ n u l l ]) {
                        unless ((_peek_char( $self ) // '') eq $c) {
                            $token = [ ERROR, 'Expected '.$c.' but encountered '.($self->{buffer} //= 'EOF') ];
                            last MAIN_LOOP;
                        }
                        else {
                            undef $self->{buffer};
                        }
                    }
                    _set_made_value( $self );
                    $token = [ ADD_NULL ];
                }
            }
            last MAIN_LOOP;
        }
        elsif ($char =~ /^[\d\-]/) {
            unless ($self->can_start_value) {
                $token = [ ERROR, "Unexpected number value" ];
            }
            else {
                if ($need_comma && ! $self->done_comma) {
                    $token = [ ERROR, "Expected ," ];
                }
                else {
                    $token = _get_number_token( $self );
                }
            }
            last MAIN_LOOP;
        }

        $token = [ ERROR, "Unexpected character $char" ];
        last MAIN_LOOP;
    }

    if ( $token && $token->[0] == ERROR ) {
        $self->{errored} = 1;
    }

    return $token;
}

sub skip {
    my ($self) = @_;

    my @end_chars;
    @end_chars = (',', '}') if $self->in_property;
    @end_chars = ('}')      if $self->in_object;
    @end_chars = (']')      if $self->in_array;

    my $start_chars = 0;

    while (1) {
        my $peek = _peek_char( $self );

        die "Unexpected end of input\n" unless defined($peek);

        if ($peek eq '"') {
            # Use the normal string parser to skip over the
            # string so that strings containing our end_chars don't
            # cause us problems.
            _discard_string( $self );
            next;
        }

        if ($start_chars < 1 && grep { $_ eq $peek } @end_chars) {
            unless ($self->in_property && $peek eq '}') {
                _discard_char( $self );
            }
            my $skipped_value = $self->in_object || $self->in_array;
            _pop_state( $self );
            _set_made_value( $self ) if $skipped_value;
            return;
        }
        else {
            $start_chars++ if $peek eq '[' || $peek eq '{';
            $start_chars-- if $peek eq ']' || $peek eq '}';
            _discard_char( $self );
        }
    }

}

sub _discard_string {
    my $char = _get_char( $_[0] );
    die 'Expected " but encountered '.($char //= 'EOF')
        unless defined $char && $char eq '"';
    while (1) {
        my $char = _get_char( $_[0] );
        die "Unterminated string" unless defined $char;
        last if $char eq '"';
        if ($char eq "\\") {
            my $escape_char = _get_char( $_[0] );
            die "Unfinished escape sequence"
                unless defined $escape_char;
            die "\\u sequence not yet supported"
                if $escape_char eq 'u';
            die "Invalid escape sequence \\$escape_char"
                unless exists ${ ESCAPE_CHARS() }{ $escape_char };
        }
    }
    return;
}

## some predicates

sub in_object   { !! $_[0]->{state}->{in_object}   }
sub in_array    { !! $_[0]->{state}->{in_array}    }
sub in_property { !! $_[0]->{state}->{in_property} }
sub made_value  { !! $_[0]->{state}->{made_value}  }
sub done_comma  { !! $_[0]->{state}->{done_comma}  }

sub can_start_value {
    return 0 if $_[0]->in_property && $_[0]->made_value;
    return $_[0]->in_object ? 0 : 1;
}

## Internals ...

sub _discard_char {
    defined $_[0]->{buffer}
        ? undef $_[0]->{buffer}
        : $_[0]->{stream}->seek( 1, 1 );
    return;
}

sub _get_char {
    my $char = '';
    $char = $_[0]->{buffer} if defined $_[0]->{buffer};
    undef $_[0]->{buffer};
    return $char if $char;
    return undef unless $_[0]->{stream}->read( $char, 1 );
    return $char;
}

sub _peek_char {
    return $_[0]->{buffer} if defined $_[0]->{buffer};
    return undef unless $_[0]->{stream}->read( my $buf, 1 );
    return $_[0]->{buffer} = $buf;
}

sub _require_char {
    my $char = _get_char( $_[0] );
    die 'Expected '.$_[1].' but encountered '.($char //= 'EOF')."\n"
        unless defined $char && $char eq $_[1];
    return;
}

sub _eat_whitespace {
    do {
        my $char = _peek_char( $_[0] );
        return if not(defined $char) || $char !~ /^\s/;
        _discard_char( $_[0] );
    } while 1;
}

sub _accum_digits {
    my $accum = '';
    while (1) {
        my $c = _peek_char( $_[0] );
        last unless defined $c && $c =~ /\d/;
        $accum .= $_[0]->{buffer};
        undef $_[0]->{buffer};
    }
    return $accum;
}

# token producers

sub _get_number_token {
    my ($char, $digit, @acc);

    $char = _peek_char( $_[0] );
    if ( defined $char && $char eq '-' ) {
        push @acc, $char;
        undef $_[0]->{buffer};
    }

    $digit = _accum_digits( $_[0] );
    return [ ERROR, 'Expected digits but got '.($_[0]->{buffer} // 'EOF') ]
        if $digit eq '';
    push @acc, $digit;

    $char = _peek_char( $_[0] );
    if ( defined $char && $char eq '.' ) {
        push @acc, $char;
        undef $_[0]->{buffer};

        $digit = _accum_digits( $_[0] );
        return [ ERROR, 'Expected digits but got '.($_[0]->{buffer} // 'EOF') ]
            if $digit eq '';
        push @acc, $digit;
    }

    $char = _peek_char( $_[0] );
    if ( defined $char && $char =~ /e/i ) {
        push @acc, $char;
        undef $_[0]->{buffer};

        $char = _peek_char( $_[0] );
        if ( defined $char && ($char eq '+' || $char eq '-') ) {
            push @acc, $char;
            undef $_[0]->{buffer};
        }

        $digit = _accum_digits( $_[0] );
        return [ ERROR, 'Expected digits but got '.($_[0]->{buffer} // 'EOF') ]
            if $digit eq '';
        push @acc, $digit;
    }

    _set_made_value( $_[0] );

    return [ ADD_NUMBER, join('', @acc)+0 ];
}

sub _get_string_token {
    my ($self) = @_;

    my $char = _get_char( $self );
    return [ ERROR, 'Expected " but encountered '.($char //= 'EOF') ]
        unless defined $char && $char eq '"';

    my $acc = '';
    while (1) {
        $char = _get_char( $self );
        return [ ERROR, "Unterminated string" ] unless defined $char;
        last if $char eq '"';

        if ($char eq "\\") {
            my $escape_char = _get_char( $self );
            return [ ERROR, "Unfinished escape sequence" ]
                unless defined $escape_char;
            return [ ERROR, "\\u sequence not yet supported" ]
                if $escape_char eq 'u';
            return [ ERROR, "Invalid escape sequence \\$escape_char" ]
                unless exists ${ ESCAPE_CHARS() }{ $escape_char };
            $acc .= ${ ESCAPE_CHARS() }{ $escape_char };
        }
        else {
            $acc .= $char;
        }
    }

    _set_made_value( $self );

    return [ ADD_STRING, $acc ];
}

# state ...

sub _push_state {
    my ($self) = @_;

    die "Can't add anything else: JSON output is complete"
        if $self->{state} == ROOT_STATE && $self->{used};

    $self->{used} = 1;

    push @{ $self->{state_stack} } => $self->{state};

    $self->{state} = {
        in_object   => 0,
        in_array    => 0,
        in_property => 0,
        made_value  => 0,
    };

    return $self->{state};
}

sub _pop_state {
    $_[0]->{state} = pop @{ $_[0]->{state_stack} };
    return;
}

sub _set_made_value {
    $_[0]->{state}->{made_value} = 1 unless $_[0]->{state} == ROOT_STATE;
    $_[0]->{state}->{done_comma} = 0 unless $_[0]->{state} == ROOT_STATE;
    $_[0]->{used} = 1;
    return;
}

sub _set_done_comma {
    $_[0]->{state}->{done_comma} = 1 unless $_[0]->{state} == ROOT_STATE;
    return;
}

1;

__END__

=head1 NAME

JSON::Streaming::Reader - Read JSON strings in a streaming manner

=head1 DESCRIPTION

This module is effectively a tokenizer for JSON strings. With it
you can process JSON strings in customizable ways without first
creating a Perl data structure from the data. For some applications,
such as those where the expected data structure is known ahead of
time, this may be a more efficient way to process incoming data.

=head1 SYNOPSIS

    # TODO ...

=head1 CREATING A NEW INSTANCE

This module can operate on either an L<IO::Handle> instance or
a string.

=head2 JSON::Streaming::Reader->for_stream($fh)

Create a new instance that will read from the provided L<IO::Handle>
instance. If you want to operate on a raw Perl filehandle, you
currently must wrap it up in an IO::Handle instance yourself.

=head2 JSON::Streaming::Reader->for_string(\$string)

Create a new instance that will read from the provided string. Uses
L<IO::Scalar> to make a stream-like wrapper around the string, and
passes it into C<for_stream>.

=head1 PULL API

A lower-level API is provided that allows the caller to pull single
tokens from the stream as necessary. The callback API is implemented
in terms of the pull API.

=head2 $jsonr->get_token()

Get the next token from the stream and advance. If the end of the
stream is reached, this will return C<undef>. Otherwise it returns
an ARRAY ref whose first member is the token type and its subsequent
members are the token type's data items, if any.

=head2 $jsonr->skip()

Quickly skip to the end of the current container. This can be used
after a C<start_property>, C<start_array> or C<start_object> token
is retrieved to signal that the remainder of the container is not
actually required. The next call to get_token will return the token
that comes after the corresponding C<end_> token for the current
container. The corresponding C<end_> token is never returned.

This is most useful for skipping over unrecognised properties when
populating a known data structure.

It is better to use this method than to implement skipping in the
caller because skipping is done using a lightweight mechanism that
does not need to allocate additional memory for tokens encountered
during skipping. However, since this method uses a simpler state
model it may cause less-intuitive error messages to be raised if
there is a JSON syntax error within the content that is skipped.

Note that errors encountered during skip are actually raised via
C<die> rather than via the return value as with C<get_token>.

=head2 $jsonr->slurp()

Skip to the end of the current container, capturing its value.
This allows you to handle a C<start_property>, C<start_array> or
C<start_object> token as if it were an C<add_>-type token,
dealing with its entire contents in one go.

The next call to get_token will return the token
that comes after the corresponding C<end_> token for the current
container. The corresponding C<end_> token is never returned.

The return value of this method call will be a Perl data structure
representing the data that was skipped. This uses the same mappings
as other popular Perl JSON libraries: objects become hashrefs, arrays
become arrayrefs, strings and integers become scalars, boolean values
become references to either 1 or 0, and null becomes undef.

This is useful if there is a part of the tree that you would rather
handle via an in-memory data structure like you'd get from a
non-streaming JSON parser. It allows you to mix-and-match streaming
parsing and one-shot parsing within a single data stream.

Note that errors encountered during skip are actually raised via
C<die> rather than via the return value as with C<get_token>.

If you call this when in property state it will return the value of
the property and parsing will continue after the corresponding
C<end_property>. In object or array state it will return the object
or array and continue after the corresponding C<end_object> or
C<end_array>.

=head1 TOKEN TYPES

There are two major classes of token types. Bracketing tokens enclose
other tokens and come in pairs, named with C<start_> and C<end_> prefixes.
Leaf tokens stand alone and have C<add_> prefixes.

For convenience the token type names match the method names used in
the "raw" API of L<JSON::Streaming::Writer>, so it is straightforward
to implement a streaming JSON normalizer by feeding the output from
this module into the corresponding methods on that module. However,
this module does have an additional special token type 'error' which
is used to indicate tokenizing errors and does not have a corresponding
method on the writer.

=head2 start_object, end_object

These token types delimit a JSON object. In a valid JSON stream an
object will contain only properties as direct children, which will
result in start_property and end_property tokens.

=head2 start_array, end_array

These token types delimit a JSON array. In a valid JSON stream an
object will contain only values as direct children, which will result
in one of the value token types described below.

=head2 start_property($name), end_property

These token types delimit a JSON property. The name of the property
is given as an argument. In a valid JSON stream a start_property
token will always be followed by one of the value token types which
will itself be immediately followed by an end_property token.

=head2 add_string($value)

Represents a JSON string. The value of the string is passed as an
argument.

=head2 add_number($value)

Represents a JSON number. The value of the number is passed as an
argument.

=head2 add_boolean($value)

Represents a JSON boolean. If it's C<true> then 1 is passed as an
argument, or if C<false> 0 is passed.

=head2 add_null

Represents a JSON null.

=head2 error($string)

Indicates a tokenization error. A human-readable description of the
error is included in $string.

=head1 STREAM BUFFERING

This module doesn't do any buffering, and it expects the underlying
stream to do appropriate read buffering if necessary.

=head1 ACKNOWLEDGEMENTS

This code, the original design and most all the docs is originally
copyright 2009 Martin Atkins <mart@degeneration.co.uk>.

B<NOTE:> Once this work is done I will work out the proper
attribution.

=cut
