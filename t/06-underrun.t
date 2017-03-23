#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
}

#compare_event_parse("[", "null,428", "]");
test_parse "... parsed correctly (no overrrun)", '[null,428]',
    [
        [ 'start_array' ],
        [ 'add_null' ],
        [ 'add_number', 428 ],
        [ 'end_array' ]
    ];

#compare_event_parse("[", "null,428", "123]");
test_parse "... parsed correctly (no overrun)", '[null,428,123]',
    [
        [ 'start_array' ],
        [ 'add_null' ],
        [ 'add_number', 428 ],
        [ 'add_number', 123 ],
        [ 'end_array' ]
    ];

#compare_event_parse("[", "null,\"foo", "bar\"]");
test_parse "... parsed correctly (no overrun)", '[null,"foo","bar"]',
    [
        [ 'start_array' ],
        [ 'add_null' ],
        [ 'add_string', 'foo' ],
        [ 'add_string', 'bar' ],
        [ 'end_array' ]
    ];

done_testing;
