package JSON::Streaming::Util;

use strict;
use warnings;

use JSON::Streaming::Tokens;

our $VERSION = '0.01';

# ...

sub slurp {
    my ($reader) = @_;

    my @items = ();

    my $start_state  = $reader->{state};
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
    if ($reader->in_array) {
        $current_item = [];
    }
    elsif ($reader->in_object) {
        $current_item = {};
    }
    elsif ($reader->in_property) {
        my $value = undef;
        $current_item = \$value;
        $need_deref = 1;
    }
    else {
        die "Can only slurp arrays, object or properties\n";
    }
    my $ret_item = $current_item;

    while (my $token = $reader->get_token()) {
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

1;

__END__

=pod

=cut

