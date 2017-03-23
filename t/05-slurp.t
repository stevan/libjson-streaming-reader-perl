#!perl

use strict;
use warnings;

use Test::More;
use JSON::Streaming::Reader::TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
}

use IO::Handle;
use Data::Dumper;

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

my $data = join('', <DATA>);
my $jsonr = JSON::Streaming::Reader->for_string(\$data);

$jsonr->process_tokens(
    start_object => sub {
    },
    end_object => sub {
    },
    start_property => sub {
        my $name = shift;

        my $value = $jsonr->slurp();
        my $expected = $correct{$name};

        is_deeply($value, $expected, $name);
    },
);

done_testing;

__END__

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

