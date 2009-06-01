
=head1 NAME

JSON::Streaming::Reader - Read JSON strings in a streaming manner

=cut

package JSON::Streaming::Reader;

use strict;
use warnings;
use Carp;

our $VERSION = '0.01';

use constant ROOT_STATE => {};

# Make some constants for the token types
BEGIN {
    foreach my $token_type (qw(start_object end_object start_array end_array start_property end_property add_string add_number add_boolean add_null error)) {
        no strict 'refs';

        my $full_name = __PACKAGE__."::".uc($token_type);

        *{$full_name} = sub { $token_type };
    }
};

sub for_stream {
    my ($class, $stream) = @_;

    my $self = bless {}, $class;
    $self->{stream} = $stream;
    $self->{state} = ROOT_STATE;
    $self->{state_stack} = [];
    $self->{used} = 0;
    return $self;
}

sub get_token {
    my ($self) = @_;

    return undef if $self->{errored};

    my $tok = eval {
        my $done_comma;
        my $need_comma = $self->made_value;
        while (1) { # Until we find a character that's interesting
            $self->_eat_whitespace();
            my $char = $self->_peek_char();

            unless (defined($char)) {
                # EOF
                die("Unexpected end of input\n") unless $self->_state == ROOT_STATE;
                return undef;
            }

            # If we've found more stuff while we're in the root state and we've
            # already seen stuff then there's junk at the end of the string.
            die("Unexpected junk at the end of input") if $self->_state == ROOT_STATE && $self->{used};

            if ($char eq ',' && ! $done_comma) {
                print STDERR "It's a comma!\n";
                if ($self->in_array || $self->in_object) {
                    if ($self->made_value) {
                        $self->_require_char(',');

                        $done_comma = 1;
                        next;
                    }
                }
                elsif ($self->in_property) {
                    # If we're in a property then a comma indicates
                    # the end of the property. We exit the property state
                    # but leave the comma so that the next get_token
                    # can still see it.
                    $self->_pop_state();
                    $self->_set_made_value;
                    return [ END_PROPERTY ];
                }
            }

            if ($char ne '}' && $self->in_object) {
                # If we're in an object then we must start a property here.
                my $name_token = $self->_get_string_token();
                die "Expected string\n" unless $name_token->[0] eq ADD_STRING;
                my $property_name = $name_token->[1];
                my $state = $self->_push_state();
                $state->{in_property} = 1;
                $self->_eat_whitespace();
                $self->_require_char(":");
                return [ START_PROPERTY, $property_name ];
            }

            if ($char eq '{') {
                die("Unexpected start of object\n") unless $self->can_start_value;
                $self->_require_char('{');
                my $state = $self->_push_state();
                $state->{in_object} = 1;
                return [ START_OBJECT ];
            }
            elsif ($char eq '}') {
                die("Expected another property\n") if $done_comma;

                # If we're in a property then this also indicates
                # the end of the property.
                # We don't actually consume the } here, so the next
                # call to get_token will see it again but it will be
                # in the is_object state rather than is_property.
                if ($self->in_property) {
                    $self->_pop_state();
                    $self->_set_made_value;
                    return [ END_PROPERTY ];
                }

                die("End of object without matching start\n") unless $self->in_object;
                $self->_require_char('}');
                $self->_pop_state();
                $self->_set_made_value();
                return [ END_OBJECT ];
            }
            elsif ($char eq '[') {
                die("Unexpected start of array\n") unless $self->can_start_value;
                $self->_require_char('[');
                my $state = $self->_push_state();
                $state->{in_array} = 1;
                return [ START_ARRAY ];
            }
            elsif ($char eq ']') {
                die("End of array without matching start\n") unless $self->in_array;
                die("Expected another value\n") if $done_comma;
                $self->_require_char(']');
                $self->_pop_state();
                $self->_set_made_value();
                return [ END_ARRAY ];
            }
            elsif ($char eq '"') {
                die("Unexpected string value\n") unless $self->can_start_value;
                die("Expected ,\n") if $need_comma && ! $done_comma;
                return $self->_get_string_token();
            }
            elsif ($char eq 't') {
                die("Unexpected boolean value\n") unless $self->can_start_value;
                die("Expected ,\n") if $need_comma && ! $done_comma;
                foreach my $c (qw(t r u e)) {
                    $self->_require_char($c);
                }
                $self->_set_made_value();
                return [ ADD_BOOLEAN, 1 ];
            }
            elsif ($char eq 'f') {
                die("Unexpected boolean value\n") unless $self->can_start_value;
                die("Expected ,\n") if $need_comma && ! $done_comma;
                foreach my $c (qw(f a l s e)) {
                    $self->_require_char($c);
                }
                $self->_set_made_value();
                return [ ADD_BOOLEAN, 0 ];
            }
            elsif ($char eq 'n') {
                die("Unexpected null\n") unless $self->can_start_value;
                die("Expected ,\n") if $need_comma && ! $done_comma;
                foreach my $c (qw(n u l l)) {
                    $self->_require_char($c);
                }
                $self->_set_made_value();
                return [ ADD_NULL ];
            }
            elsif ($char =~ /^[\d\-]/) {
                die("Unexpected number value\n") unless $self->can_start_value;
                die("Expected ,\n") if $need_comma && ! $done_comma;
                return $self->_get_number_token();
            }

            die "Unexpected character $char\n";
            last;
        }
    };
    if ($@) {
        $self->{errored} = 1;
        my $error = $@;
        chomp $error;
        return [ ERROR, $error ];
    }

    return $tok;

}

# FIXME: This doesn't currently work. Blows up if there's a string in the stuff to skip,
# which more often than not there is.
sub skip {
    my ($self) = @_;

    my @end_chars;

    @end_chars = qw(, }) if $self->in_property;
    @end_chars = qw(}) if $self->in_object;
    @end_chars = qw(]) if $self->in_array;

    while (1) {
        my $peek = $self->_peek_char();

        die "Unexpected end of input\n" unless defined($peek);

        if ($peek eq '"') {
            # Use the normal string parser to skip over the
            # string so that strings containing our end_chars don't
            # cause us problems.
            $self->_parse_string();
        }

        if (grep { $_ eq $peek } @end_chars) {
            unless ($self->in_property && $peek eq '}') {
                $self->_get_char();
            }
            $self->_pop_state();
            return;
        }
        else {
            $self->_get_char();
        }
    }

}

sub _get_char {
    my ($self) = @_;

    my $ret = $self->_peek_char();
    $self->{peeked} = undef;
    return $ret;
}

sub _require_char {
    my ($self, $required) = @_;

    my $char = $self->_get_char();
    if ($char ne $required) {
        die "Expected $required but encountered ".(defined($char) ? $char : 'EOF');
    }
    return $char;
}

sub _peek_char {
    my ($self) = @_;

    return $self->{peeked} if defined($self->{peeked});

    my $buf = "";
    my $success = read($self->{stream}, $buf, 1);

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

    while ($self->_peek_char() =~ /\d/) {
        $accum .= $self->_get_char();
    }

    # We should have got at least one digit
    die "Expected digits but got ".$self->_peek_char() if $accum eq '';

    return $accum;
}

sub _get_number_token {
    my ($self) = @_;

    my @accum = ();

    if ($self->_peek_char() eq '-') {
        push @accum, $self->_get_char();
    }

    push @accum, $self->_get_digits;

    if ($self->_peek_char() eq '.') {
        push @accum, $self->_get_char();

        push @accum, $self->_get_digits;

    }

    if ($self->_peek_char() =~ /e/i) {
        push @accum, $self->_get_char();

        my $peek = $self->_peek_char();

        if ($peek eq '+' || $peek eq '-') {
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

        die "Unterminated string\n" unless defined($char);
        if ($char eq '"') {
            last;
        }

        if ($char eq "\\") {
            my $escape_char = $self->_get_char();

            die "Unfinished escape sequence\n" unless defined($escape_char);

            if (my $replacement = $escape_chars{$escape_char}) {
                $accum .= $replacement;
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

    Carp::croak("Can't add anything else: JSON output is complete") if $self->_state == ROOT_STATE && $self->{used};

    $self->{used} = 1;

    push @{$self->{state_stack}}, $self->{state};

    $self->{state} = {
        in_object => 0,
        in_array => 0,
        in_property => 0,
        made_value => 0,
    };

    return $self->{state};
}

sub _pop_state {
    my ($self) = @_;

    my $state = pop @{$self->{state_stack}};
    return $self->{state} = $state;
}

sub _state {
    my ($self) = @_;

    return $self->{state};
}

sub in_object {
    return $_[0]->_state->{in_object} ? 1 : 0;
}

sub in_array {
    return $_[0]->_state->{in_array} ? 1 : 0;
}

sub in_property {
    return $_[0]->_state->{in_property} ? 1 : 0;
}

sub made_value {
    return $_[0]->_state->{made_value} ? 1 : 0;
}

sub _set_made_value {
    $_[0]->_state->{made_value} = 1 unless $_[0]->_state == ROOT_STATE;
}

sub can_start_value {

    return 0 if $_[0]->in_property && $_[0]->made_value;

    return $_[0]->in_object ? 0 : 1;
}

sub _expecting_property {
    return $_[0]->in_object ? 1 : 0;
}

1;

=head1 DESCRIPTION

This module is effectively a tokenizer for JSON strings. With it you can process
JSON strings in customizable ways without first creating a Perl data structure
from the data. For some applications, such as those where the expected data
structure is known ahead of time, this may be a more efficient way to process
incoming data.

=head1 SYNOPSIS

    my $jsonr = JSON::Streaming::Reader->for_stream($fh);
    $jsonr->process_tokens(
        start_object => sub {
            ...
        },
        end_object => sub {

        },
        start_property => sub {
            my ($name) = @_;
        },
        # ...
    );

=head1 CALLBACK API

The recommended way to use this library is via the callback-based API. In this
API you make a single method call on the reader object and pass it a CODE ref
for each token type. The reader object will then consume the entire stream
and call the callback responding to the type of each token it encounters.

An error token will be raised on tokenizing errors. However, since this tokenizer
doesn't maintain extensive state only token-level errors will be detected. It
is up to the caller to catch invalid token combinations.

For tokens that themselves have data, the data items will be passed in as arguments
to the callback.

=head2 $jsonr->process_tokens(%callbacks)

Read the whole stream and call a callback corresponding to each token encountered.

=head1 PULL API

A lower-level API is provided that allows the caller to pull single tokens
from the stream as necessary. The callback API is implemented in terms of the
pull API.

=head2 $jsonr->get_token()

Get the next token from the stream and advance. If the end of the stream is reached, this
will return C<undef>. Otherwise it returns an ARRAY ref whose first member is the
token type and its subsequent members are the token type's data items, if any.

=head1 TOKEN TYPES

There are two major classes of token types. Bracketing tokens enclose other tokens
and come in pairs, named with C<start_> and C<end_> prefixes. Leaf tokens stand alone
and have C<add_> prefixes.

For convenience the token type names match the method names used in the "raw" API
of L<JSON::Streaming::Writer>, so it is straightforward to implement a streaming JSON
normalizer by feeding the output from this module into the corresponding methods on that module.
However, this module does have an additional special token type 'error' which is used
to indicate tokenizing errors and does not have a corresponding method on the writer.

=head2 start_object, end_object

These token types delimit a JSON object. In a valid JSON stream an object will contain
only properties as direct children, which will result in start_property and end_property tokens.

=head2 start_array, end_array

These token types delimit a JSON array. In a valid JSON stream an object will contain
only values as direct children, which will result in one of the value token types described
below.

=head2 start_property($name), end_property

These token types delimit a JSON property. The name of the property is given as an argument.
In a valid JSON stream a start_property token will always be followed by one of the value
token types which will itself be immediately followed by an end_property token.

=head2 add_string($value)

Represents a JSON string. The value of the string is passed as an argument.

=head2 add_number($value)

Represents a JSON number. The value of the number is passed as an argument.

=head2 add_boolean($value)

Represents a JSON boolean. If it's C<true> then 1 is passed as an argument, or if C<false> 0 is passed.

=head2 add_null

Represents a JSON null.

=head2 error($string)

Indicates a tokenization error. A human-readable description of the error is included in $string.

=head1 STREAM BUFFERING

This module doesn't do any buffering. It expects the underlying stream to
do appropriate read buffering if necessary.

=head1 LIMITATIONS

=head2 No Non-blocking API

Currently there is no way to make this module do non-blocking reads. In future
an event-based version of the callback-based API could be added that can be
used in applications that must not block while the whole object is processed, such
as those using L<POE> or L<Danga::Socket>.

This module expects to be able to do blocking reads on the provided stream. It will
not behave well if a read fails with C<EWOULDBLOCK>, so passing non-blocking
L<IO::Socket> objects is not recommended.

