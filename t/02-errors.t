#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use TestUtil;

BEGIN {
    use_ok('JSON::Streaming::Reader');
}

test_parse "Unclosed object", "{", [
    [ START_OBJECT ],
    [ ERROR, 'Unexpected end of input' ],
];

test_parse "Unclosed array", "[", [
    [ START_ARRAY ],
    [ ERROR, 'Unexpected end of input' ],
];

test_parse "Mismatched brackets starting with array", "[}", [
    [ START_ARRAY ],
    [ ERROR, 'End of object without matching start' ],
];

test_parse "Mismatched brackets starting with object", "{]", [
    [ START_OBJECT ],
    [ ERROR, 'Expected " but encountered ]' ],
];

test_parse "Junk at the end of the root value", "{}{}", [
    [ START_OBJECT ],
    [ END_OBJECT ],
    [ ERROR, 'Unexpected junk at the end of input' ],
];

test_parse "Unterminated string", '"hello', [
    [ ERROR, 'Unterminated string' ],
];

test_parse "Unknown escape sequence", '"hell\\o', [
    [ ERROR, 'Invalid escape sequence \o' ],
];

test_parse "Unterminated true", 'tru', [
    [ ERROR, 'Expected e but encountered EOF' ],
];

test_parse "Unterminated false", 'fals', [
    [ ERROR, 'Expected e but encountered EOF' ],
];

test_parse "Mis-spelled false", 'flase', [
    [ ERROR, 'Expected a but encountered l' ],
];

test_parse "Unterminated null", 'nul', [
    [ ERROR, 'Expected l but encountered EOF' ],
];

test_parse "Unknown keyword", 'cheese', [
    [ ERROR, 'Unexpected character c' ],
];

test_parse "Unterminated number", '1.', [
    [ ERROR, 'Expected digits but got EOF' ],
];

test_parse "Number with only fraction", '.5', [
    [ ERROR, 'Unexpected character .' ],
];

test_parse "Negative number with only fraction", '-.5', [
    [ ERROR, 'Expected digits but got .' ],
];

test_parse "Number with two decimal points", '1.2.2', [
    [ ADD_NUMBER, 1.2 ],
    [ ERROR, 'Unexpected junk at the end of input' ],
];

test_parse "Number with spaces in it", '1 2', [
    [ ADD_NUMBER, 1 ],
    [ ERROR, 'Unexpected junk at the end of input' ],
];

test_parse "Number with spaces in it after decimal point", '1. 2', [
    [ ERROR, 'Expected digits but got  ' ],
];

test_parse "Number with two signs", '--5', [
    [ ERROR, 'Expected digits but got -' ],
];

test_parse "Number with positive sign", '+5', [
    [ ERROR, 'Unexpected character +' ],
];

test_parse "Number with empty exponent", '5e', [
    [ ERROR, 'Expected digits but got EOF' ],
];

test_parse "Number with exponent with sign but no digits", '5e-', [
    [ ERROR, 'Expected digits but got EOF' ],
];

test_parse "Number with multiple exponents", '5e5e5', [
    [ ADD_NUMBER, 500000 ],
    [ ERROR, 'Unexpected junk at the end of input' ],
];

test_parse "Property with no value and end of object", '{"property":}', [
    [ START_OBJECT ],
    [ START_PROPERTY, 'property' ],
    [ ERROR, 'Property has no value' ],
];

test_parse "Property with no value with subsequent property", '{"property":,"another":true}', [
    [ START_OBJECT ],
    [ START_PROPERTY, 'property' ],
    [ ERROR, 'Property has no value' ],
];

test_parse "Property with no value or colon and end of object", '{"property"}', [
    [ START_OBJECT ],
    [ ERROR, 'Expected : but encountered }' ],
];

test_parse "Property with no value or colon with subsequent property", '{"property","another":true}', [
    [ START_OBJECT ],
    [ ERROR, 'Expected : but encountered ,' ],
];

test_parse "Unterminated property name", '{"proper', [
    [ START_OBJECT ],
    [ ERROR, 'Unterminated string' ],
];

test_parse "Unquoted property name", '{property:true}', [
    [ START_OBJECT ],
    [ ERROR, 'Expected " but encountered p' ],
];

test_parse "Array containing a property", '["property":true]', [
    [ START_ARRAY ],
    [ ADD_STRING, 'property' ],
    [ ERROR, 'Unexpected character :' ],
];

test_parse "Array with two values missing comma", '[true false]', [
    [ START_ARRAY ],
    [ ADD_BOOLEAN, 1 ],
    [ ERROR, 'Expected ,' ],
];

test_parse "Object with two properties missing comma", '{"property1":true "property2":false}', [
    [ START_OBJECT ],
    [ START_PROPERTY, 'property1' ],
    [ ADD_BOOLEAN, 1 ],
    [ ERROR, 'Unexpected string value' ],
];

done_testing;
