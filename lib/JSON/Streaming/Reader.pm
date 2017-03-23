package JSON::Streaming::Reader;

use strict;
use warnings;

use Carp ();
use IO::Scalar;
use UNIVERSAL::Object;

our $VERSION = '0.01';

use constant ROOT_STATE => {};

# Token types ...

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

# ...

our @ISA; BEGIN { @ISA = ('UNIVERSAL::Object') }
our %HAS; BEGIN {
    %HAS = (
        stream      => sub { die 'A `stream` must be defined' },
        state       => \&ROOT_STATE,
        state_stack => sub { [] },
        used        => sub { 0 },
        peeked      => sub { undef },
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

    eval {
        my $need_comma = $self->made_value;

    MAIN_LOOP:
        while (1) {
            $self->_eat_whitespace();
            my $char = $self->_peek_char();

            unless (defined($char)) {
                # EOF
                unless ( $self->{state} == ROOT_STATE ) {
                    $token = [ ERROR, "Unexpected end of input" ];
                }
                else {
                    $token = undef;
                }
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
                        $self->_require_char(',');
                        $self->_set_done_comma();
                        next;
                    }
                }
                elsif ($self->in_property) {
                    # If we're in a property then a comma indicates
                    # the end of the property. We exit the property state
                    # but leave the comma so that the next get_token
                    # can still see it.
                    unless ( $self->made_value ) {
                        $token = [ ERROR, "Property has no value" ];
                    }
                    else {
                        $self->_pop_state();
                        $self->_set_made_value;
                        $token = [ END_PROPERTY ];
                    }
                    last MAIN_LOOP;
                }
            }

            if ($char ne '}' && $self->in_object) {
                # If we're in an object then we must start a property here.
                my $name_token = $self->_get_string_token();

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
                        $self->_eat_whitespace();
                        $self->_require_char(":");
                        my $property_name = $name_token->[1];
                        my $state = $self->_push_state();
                        $state->{in_property} = 1;
                        $token = [ START_PROPERTY, $property_name ];
                    }
                }
                last MAIN_LOOP;
            }

            if ($char eq '{') {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected start of object" ];
                }
                else {
                    $self->_require_char('{');
                    my $state = $self->_push_state();
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
                        unless ( $self->made_value ) {
                            $token = [ ERROR, "Property has no value" ];
                        }
                        else {
                            $self->_pop_state();
                            $self->_set_made_value;
                            $token = [ END_PROPERTY ];
                        }
                        last MAIN_LOOP;
                    }

                    unless ( $self->in_object ) {
                        $token = [ ERROR, "End of object without matching start" ];
                    }
                    else {
                        $self->_require_char('}');
                        $self->_pop_state();
                        $self->_set_made_value();
                        $token = [ END_OBJECT ];
                    }
                }
                last MAIN_LOOP;
            }
            elsif ($char eq '[') {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected start of array" ];
                }
                else {
                    $self->_require_char('[');
                    my $state = $self->_push_state();
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
                    if ( $self->done_comma ) {
                        $token = [ ERROR, "Expected another value" ];
                    }
                    else {
                        $self->_require_char(']');
                        $self->_pop_state();
                        $self->_set_made_value();
                        $token = [ END_ARRAY ];
                    }
                }
                last MAIN_LOOP;
            }
            elsif ($char eq '"') {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected string value" ];
                }
                else {
                    if ( $need_comma && ! $self->done_comma ) {
                        $token = [ ERROR, "Expected ," ];
                    }
                    else {
                        $token = $self->_get_string_token();
                    }
                }
                last MAIN_LOOP;
            }
            elsif ($char eq 't') {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected boolean value" ];
                }
                else {
                    if ( $need_comma && ! $self->done_comma ) {
                        $token = [ ERROR, "Expected ," ];
                    }
                    else {
                        foreach my $c (qw(t r u e)) {
                            $self->_require_char($c);
                        }
                        $self->_set_made_value();
                        $token = [ ADD_BOOLEAN, 1 ];
                    }
                }
                last MAIN_LOOP;
            }
            elsif ($char eq 'f') {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected boolean value" ];
                }
                else {
                    if ( $need_comma && ! $self->done_comma ) {
                        $token = [ ERROR, "Expected ," ];
                    }
                    else {
                        foreach my $c (qw(f a l s e)) {
                            $self->_require_char($c);
                        }
                        $self->_set_made_value();
                        $token = [ ADD_BOOLEAN, 0 ];
                    }
                }
                last MAIN_LOOP;
            }
            elsif ($char eq 'n') {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected null" ];
                }
                else {
                    if ( $need_comma && ! $self->done_comma ) {
                        $token = [ ERROR, "Expected ," ];
                    }
                    else {
                        foreach my $c (qw(n u l l)) {
                            $self->_require_char($c);
                        }
                        $self->_set_made_value();
                        $token = [ ADD_NULL ];
                    }
                }
                last MAIN_LOOP;
            }
            elsif ($char =~ /^[\d\-]/) {
                unless ( $self->can_start_value ) {
                    $token = [ ERROR, "Unexpected number value" ];
                }
                else {
                    if ( $need_comma && ! $self->done_comma ) {
                        $token = [ ERROR, "Expected ," ];
                    }
                    else {
                        $token = $self->_get_number_token();
                    }
                }
                last MAIN_LOOP;
            }

            $token = [ ERROR, "Unexpected character $char" ];
            last MAIN_LOOP;
        }
    };
    if ($@) {
        my $error = $@;
        chomp $error;
        $token = [ ERROR, $error ];
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
        my $peek = $self->_peek_char();

        die "Unexpected end of input\n" unless defined($peek);

        if ($peek eq '"') {
            # Use the normal string parser to skip over the
            # string so that strings containing our end_chars don't
            # cause us problems.
            $self->_parse_string();
            next;
        }

        if ($start_chars < 1 && grep { $_ eq $peek } @end_chars) {
            unless ($self->in_property && $peek eq '}') {
                $self->_get_char();
            }
            my $skipped_value = $self->in_object || $self->in_array;
            $self->_pop_state();
            $self->_set_made_value() if $skipped_value;
            return;
        }
        else {
            $start_chars++ if $peek eq '[' || $peek eq '{';
            $start_chars-- if $peek eq ']' || $peek eq '}';
            $self->_get_char();
        }
    }

}

sub slurp {
    my ($self) = @_;

    my $start_state = $self->{state};
    my @items = ();
    my $current_item = undef;

    my $push_item = sub {
        my $item = shift;
        push @items, $current_item;
        $current_item = $item;
    };
    my $pop_item = sub {
        $current_item = pop @items;
        return $current_item;
    };
    my $handle_value = sub {
        my ($token, $target) = @_;
        my $type = $token->[0];

        if ($type == ADD_STRING || $type == ADD_NUMBER) {
            $$target = $token->[1];
        }
        elsif ($type == ADD_BOOLEAN) {
            $$target = $token->[1] ? \1 : \0;
        }
        elsif ($type == ADD_NULL) {
            $$target = undef;
        }
        elsif ($type == START_OBJECT) {
            my $new_item = {};
            $$target = $new_item;
            $push_item->($new_item);
        }
        elsif ($type == START_ARRAY) {
            my $new_item = [];
            $$target = $new_item;
            $push_item->($new_item);
        }
        else {
            # This should actually never happen, since it should be caught
            # by the underlying raw API.
            die "Expecting a value but got a $type token\n";
        }
    };

    my $need_deref = 0;
    if ($self->in_array) {
        $current_item = [];
    }
    elsif ($self->in_object) {
        $current_item = {};
    }
    elsif ($self->in_property) {
        my $value = undef;
        $current_item = \$value;
        $need_deref = 1;
    }
    else {
        die "Can only slurp arrays, object or properties\n";
    }
    my $ret_item = $current_item;

    while (my $token = $self->get_token()) {
        my $type = $token->[0];

        if ($type == ERROR) {
            die $token->[1];
        }

        my $item_type = ref($current_item);

        if ($item_type eq 'SCALAR' || $item_type eq 'REF') {
            # We're expecting a value

            if ($type == END_PROPERTY) {
                $pop_item->();
                last unless defined($current_item);
            }
            else {
                $handle_value->($token, $current_item);
            }
        }
        elsif ($item_type eq 'ARRAY') {
            if ($type == END_ARRAY) {
                $pop_item->();
                last unless defined($current_item);
            }
            else {
                # We're expecting a value here too, but
                # we're going to add it to the end of the
                # array instead.
                my $target = \$current_item->[scalar(@$current_item)];
                $handle_value->($token, $target);
            }
        }
        elsif ($item_type eq 'HASH') {
            # We're expecting a property here.

            if ($type == START_PROPERTY) {
                my $name = $token->[1];
                my $target = \$current_item->{$name};
                $push_item->($target);
            }
            elsif ($type == END_OBJECT) {
                $pop_item->();
                last unless defined($current_item);
            }
            else {
                die "Not expecting $type in object state\n";
            }
        }
        else {
            die "Don't know what to do with a $item_type value\n";
        }

    }

    # There should be nothing in $current_item by this point.
    die "Unexpected end of input" if defined($current_item);

    return $need_deref ? $$ret_item : $ret_item;
}

## some predicates

sub in_object {
    return $_[0]->{state}->{in_object} ? 1 : 0;
}

sub in_array {
    return $_[0]->{state}->{in_array} ? 1 : 0;
}

sub in_property {
    return $_[0]->{state}->{in_property} ? 1 : 0;
}

sub made_value {
    return $_[0]->{state}->{made_value} ? 1 : 0;
}

sub done_comma {
    return $_[0]->{state}->{done_comma} ? 1 : 0;
}

sub can_start_value {
    return 0 if $_[0]->in_property && $_[0]->made_value;
    return $_[0]->in_object ? 0 : 1;
}

## Internals ...

sub _get_char {
    my ($self) = @_;

    my $ret = $self->_peek_char();
    $self->{peeked} = undef;
    return $ret;
}

sub _require_char {
    my ($self, $required) = @_;

    my $char = $self->_get_char();
    unless (defined($char) && $char eq $required) {
        die "Expected $required but encountered ".(defined($char) ? $char : 'EOF')."\n";
    }
    return $char;
}

sub _peek_char {
    my ($self) = @_;

    return $self->{peeked} if defined($self->{peeked});

    my $buf = "";
    my $success = $self->{stream}->read($buf, 1);

    unless ($success) {
        # Assume EOF
        return undef;
    }

    return $self->{peeked} = $buf;
}

sub _eat_whitespace {
    my ($self) = @_;

    while (1) {
        my $char = $self->_peek_char();

        return if ! defined($char);
        return if $char !~ /^\s/;
        $self->_get_char();
    }
}

sub _get_digits {
    my ($self) = @_;

    my $accum = "";

    while (defined($self->_peek_char()) && $self->_peek_char() =~ /\d/) {
        $accum .= $self->_get_char();
    }

    # We should have got at least one digit
    die "Expected digits but got ".(defined $self->_peek_char() ? $self->_peek_char() : 'EOF')."\n" unless defined($accum) && $accum ne '';

    return $accum;
}

sub _get_number_token {
    my ($self) = @_;

    my @accum = ();

    if ($self->_peek_char() eq '-') {
        push @accum, $self->_get_char();
    }

    push @accum, $self->_get_digits;

    if (defined($self->_peek_char()) && $self->_peek_char() eq '.') {
        push @accum, $self->_get_char();

        push @accum, $self->_get_digits;

    }

    if (defined($self->_peek_char()) && $self->_peek_char() =~ /e/i) {
        push @accum, $self->_get_char();

        my $peek = $self->_peek_char();

        if (defined($peek) && ($peek eq '+' || $peek eq '-')) {
            push @accum, $self->_get_char();
        }

        push @accum, $self->_get_digits;
    }

    $self->_set_made_value();

    # Join and convert to number
    # Perl's numberification conveniently does what we need here.
    return [ ADD_NUMBER, join('', @accum)+0 ];
}

my %escape_chars = (
    b => "\b",
    f => "\f",
    n => "\n",
    r => "\r",
    t => "\t",
    "\\" => "\\",
    "/" => "/",
    '"' => '"',
);

sub _get_string_token {
    my ($self) = @_;

    $self->_require_char('"');

    my $accum = "";

    while (1) {
        my $char = $self->_get_char();

        return [ ERROR, "Unterminated string" ] unless defined($char);
        if ($char eq '"') {
            last;
        }

        if ($char eq "\\") {
            my $escape_char = $self->_get_char();

            return [ ERROR, "Unfinished escape sequence" ] unless defined($escape_char);

            if (my $replacement = $escape_chars{$escape_char}) {
                $accum .= $replacement;
            }
            elsif ($escape_char eq 'u') {
                # TODO: Support this
                return [ ERROR, "\\u sequence not yet supported" ];
            }
            else {
                return [ ERROR, "Invalid escape sequence \\$escape_char" ];
            }
        }
        else {
            $accum .= $char;
        }
    }

    $self->_set_made_value();

    return [ ADD_STRING, $accum ];
}

sub _parse_string {
    my ($self) = @_;

    $self->_require_char('"');

    my $accum = "";

    # Don't bother building the result buffer if we're called in void context
    my $want_result = defined(wantarray());

    while (1) {
        my $char = $self->_get_char();

        die "Unterminated string\n" unless defined($char);
        if ($char eq '"') {
            last;
        }

        if ($char eq "\\") {
            my $escape_char = $self->_get_char();

            die "Unfinished escape sequence\n" unless defined($escape_char);

            if (my $replacement = $escape_chars{$escape_char}) {
                $accum .= $replacement if $want_result;
            }
            elsif ($escape_char eq 'u') {
                # TODO: Support this
                die "\\u sequence not yet supported\n";
            }
            else {
                die "Invalid escape sequence \\$escape_char";
            }
        }
        else {
            $accum .= $char if $want_result;
        }
    }

    return $accum;
}

sub _push_state {
    my ($self) = @_;

    Carp::croak("Can't add anything else: JSON output is complete")
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
    return $_[0]->{state} = pop @{ $_[0]->{state_stack} };
}

sub _expecting_property {
    return $_[0]->in_object ? 1 : 0;
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
