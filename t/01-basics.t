#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
}

test_parse "Empty string", "", [];

test_parse "Empty object", "{}", [ [ START_OBJECT ], [ END_OBJECT ] ];
test_parse "Empty array", "[]", [ [ START_ARRAY ], [ END_ARRAY ] ];

test_parse "Empty string", '""', [ [ ADD_STRING, '' ] ];
test_parse "Non-empty string", '"hello"', [ [ ADD_STRING, 'hello' ] ];

test_parse "String with escapes", "\"hello\\nworld\"", [ [ ADD_STRING, "hello\nworld" ] ];
test_parse "String with literal quotes and backslahes", "\"hello\\\\\\\"world\\\"\"", [ [ ADD_STRING, "hello\\\"world\"" ] ];

test_parse "Zero", '0', [ [ ADD_NUMBER, 0 ] ];
test_parse "One", '1', [ [ ADD_NUMBER, 1 ] ];
test_parse "One point 5", '1.5', [ [ ADD_NUMBER, 1.5 ] ];
test_parse "One thousand using uppercase exponent", '1E3', [ [ ADD_NUMBER, 1000 ] ];
test_parse "One thousand using lowercase exponent", '1e3', [ [ ADD_NUMBER, 1000 ] ];
test_parse "One thousand using lowercase exponent with plus", '1e+3', [ [ ADD_NUMBER, 1000 ] ];
test_parse "Nought point 1 using exponent", '1e-1', [ [ ADD_NUMBER, 0.1 ] ];
test_parse "one using exponent", '1e0', [ [ ADD_NUMBER, 1 ] ];
test_parse "Negative one", '-1', [ [ ADD_NUMBER, -1 ] ];
test_parse "Negative one point 5", '-1.5', [ [ ADD_NUMBER, -1.5 ] ];
test_parse "Negative 1000 using exponent", '-1e3', [ [ ADD_NUMBER, -1000 ] ];
test_parse "Negative nought point 1 using exponent", '-1e-1', [ [ ADD_NUMBER, -0.1 ] ];

test_parse "True", "true", [ [ ADD_BOOLEAN, 1 ] ];
test_parse "False", "false", [ [ ADD_BOOLEAN, 0 ] ];
test_parse "Null", "null", [ [ ADD_NULL ] ];

test_parse "Array containing number", "[1]", [ [ START_ARRAY ], [ ADD_NUMBER, 1 ], [ END_ARRAY ] ];
test_parse "Array containing two numbers", "[1,4]", [ [ START_ARRAY ], [ ADD_NUMBER, 1 ], [ ADD_NUMBER, 4 ], [ END_ARRAY ] ];
test_parse "Array containing null", "[null]", [ [ START_ARRAY ], [ ADD_NULL ], [ END_ARRAY ] ];
test_parse "Array containing an empty array", "[[]]", [ [ START_ARRAY ], [ START_ARRAY ], [ END_ARRAY ], [ END_ARRAY ] ];
test_parse "Array containing an empty object", "[{}]", [ [ START_ARRAY ], [ START_OBJECT ], [ END_OBJECT ], [ END_ARRAY ] ];
test_parse "Object containing a string property", '{"hello":"world"}', [
    [ START_OBJECT ],
    [ START_PROPERTY, 'hello' ],
    [ ADD_STRING, 'world' ],
    [ END_PROPERTY ],
    [ END_OBJECT ],
];
test_parse "Object containing a property whose value is an empty object", '{"hello":{}}', [
    [ START_OBJECT ],
    [ START_PROPERTY, 'hello' ],
    [ START_OBJECT ],
    [ END_OBJECT ],
    [ END_PROPERTY ],
    [ END_OBJECT ],
];

done_testing;
