#!perl

use strict;
use warnings;

use Test::More;

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
        [ 'start_object' ],
            [ 'start_property', 'string' ],
                [ 'add_string', 'world' ],
            [ 'end_property' ],

            [ 'start_property', 'number' ],
                [ 'add_number', 2 ],
            [ 'end_property' ],

            [ 'start_property', 'boolean' ],
                [ 'add_boolean', 1 ],
            [ 'end_property' ],

            [ 'start_property', 'array' ],
                # the array has been skipped
            [ 'end_property' ],

            [ 'start_property', 'object' ],
                [ 'start_object' ],
                    [ 'start_property', 'hello' ],
                        [ 'add_string', 'world' ],
                    [ 'end_property' ],
                [ 'end_object' ],
            [ 'end_property' ],

            [ 'start_property', 'complexArray' ],
                # the array has been skipped
            [ 'end_property' ],

        [ 'end_object' ]
    ],
    '... got the expected tokens'
);

done_testing;

