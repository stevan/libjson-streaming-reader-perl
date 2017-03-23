package # hide from PAUSE ...
    TestUtil;

use strict;
use warnings;

use Test::More ();
use JSON::Streaming::Reader;

sub import {
    my $into = caller;
    no strict 'refs';
    *{$into.'::test_parse'} = \&test_parse;

    # it helps to have the token types in the tests ...
    *{$into.'::START_OBJECT'}   = \&JSON::Streaming::Reader::START_OBJECT;
    *{$into.'::END_OBJECT'}     = \&JSON::Streaming::Reader::END_OBJECT;
    *{$into.'::START_ARRAY'}    = \&JSON::Streaming::Reader::START_ARRAY;
    *{$into.'::END_ARRAY'}      = \&JSON::Streaming::Reader::END_ARRAY;
    *{$into.'::START_PROPERTY'} = \&JSON::Streaming::Reader::START_PROPERTY;
    *{$into.'::END_PROPERTY'}   = \&JSON::Streaming::Reader::END_PROPERTY;
    *{$into.'::ADD_STRING'}     = \&JSON::Streaming::Reader::ADD_STRING;
    *{$into.'::ADD_NUMBER'}     = \&JSON::Streaming::Reader::ADD_NUMBER;
    *{$into.'::ADD_BOOLEAN'}    = \&JSON::Streaming::Reader::ADD_BOOLEAN;
    *{$into.'::ADD_NULL'}       = \&JSON::Streaming::Reader::ADD_NULL;
    *{$into.'::ERROR'}          = \&JSON::Streaming::Reader::ERROR;
}

sub test_parse {
    my ($name, $input, $expected_tokens) = @_;

    my $jsonw = JSON::Streaming::Reader->for_string($input);
    my @tokens = ();

    while (my $token = $jsonw->get_token()) {
        push @tokens, $token;
    }

    Test::More::is_deeply(\@tokens, $expected_tokens, $name);
}

1;
