#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
    use_ok('JSON::Streaming::Util');
}

my %correct = (
    string => "world",
    number => 2,
    boolean => \1,
    array => [ 1, 2, 3 ],
    object => { "hello" => "world" },
    complexArray => [
        { "null" => undef },
        [ 1, 2, \0 ],
    ],
);

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

my $jsonr = JSON::Streaming::Reader->for_string(\$data);

while (my $token = $jsonr->get_token) {
    if ( $token->[0] eq JSON::Streaming::Reader->START_PROPERTY ) {
        my $name     = $token->[1];
        my $value    = JSON::Streaming::Util::slurp( $jsonr );
        my $expected = $correct{$name};
        is_deeply($value, $expected, $name);
    }
}

done_testing;

