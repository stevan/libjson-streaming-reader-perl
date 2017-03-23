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
        [ START_ARRAY ],
        [ ADD_NULL ],
        [ ADD_NUMBER, 428 ],
        [ END_ARRAY ]
    ];

#compare_event_parse("[", "null,428", "123]");
test_parse "... parsed correctly (no overrun)", '[null,428,123]',
    [
        [ START_ARRAY ],
        [ ADD_NULL ],
        [ ADD_NUMBER, 428 ],
        [ ADD_NUMBER, 123 ],
        [ END_ARRAY ]
    ];

#compare_event_parse("[", "null,\"foo", "bar\"]");
test_parse "... parsed correctly (no overrun)", '[null,"foo","bar"]',
    [
        [ START_ARRAY ],
        [ ADD_NULL ],
        [ ADD_STRING, 'foo' ],
        [ ADD_STRING, 'bar' ],
        [ END_ARRAY ]
    ];

done_testing;
