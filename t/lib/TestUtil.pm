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
