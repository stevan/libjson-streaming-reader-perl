#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
}

my $data = q[
{
    "string": "world",
    "number": 2,
    "boolean": true,
    "array": [ 1, 2, 3 ],
    "object": { "hello":"world" },
    "complexArray": [
        {"null":null},
        [ 1, 2, false ]
     ]
}
];

my @tokens;

my $jsonr = JSON::Streaming::Reader->for_string(\$data);
while (my $token = $jsonr->get_token) {
    if ( $token->[0] eq JSON::Streaming::Reader->START_ARRAY ) {
        $jsonr->skip();
    }
    else {
        push @tokens => $token;
    }
}

is_deeply(
    \@tokens,
    [
        [ START_OBJECT ],
            [ START_PROPERTY, 'string' ],
                [ ADD_STRING, 'world' ],
            [ END_PROPERTY ],

            [ START_PROPERTY, 'number' ],
                [ ADD_NUMBER, 2 ],
            [ END_PROPERTY ],

            [ START_PROPERTY, 'boolean' ],
                [ ADD_BOOLEAN, 1 ],
            [ END_PROPERTY ],

            [ START_PROPERTY, 'array' ],
                # the array has been skipped
            [ END_PROPERTY ],

            [ START_PROPERTY, 'object' ],
                [ START_OBJECT ],
                    [ START_PROPERTY, 'hello' ],
                        [ ADD_STRING, 'world' ],
                    [ END_PROPERTY ],
                [ END_OBJECT ],
            [ END_PROPERTY ],

            [ START_PROPERTY, 'complexArray' ],
                # the array has been skipped
            [ END_PROPERTY ],

        [ END_OBJECT ]
    ],
    '... got the expected tokens'
);

done_testing;

