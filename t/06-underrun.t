#!perl

use strict;
use warnings;

use Test::More;
use JSON::Streaming::Reader::TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
}

compare_event_parse("[", "null,428", "]");
compare_event_parse("[", "null,428", "123]");
compare_event_parse("[", "null,\"foo", "bar\"]");

done_testing;
