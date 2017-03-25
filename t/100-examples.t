#!perl

use strict;
use warnings;

use Test::More;
use IO::File;

BEGIN {
    use_ok('JSON::Streaming::Reader');
    use_ok('JSON::Streaming::Tokens');
    use_ok('JSON::Streaming::Util');
}

my $guid     = "4763ddae-f1ec-49f9-8202-691bc124514f";
my %expected = (
    guid => $guid,
    age  => 38,
    name => "Lee Shelton",
    tags => [qw[
      ea
      pariatur
      sint
      qui
      elit
      anim
      deserunt
    ]]
);

my $yuge  = IO::File->new('benchmarks/samples/yuge.json', 'r');
my $jsonr = JSON::Streaming::Reader->for_stream( $yuge );

my $start_token = $jsonr->get_token;
die 'Expected array' unless $start_token->[0] == START_ARRAY;

my %got;

OUTER:
    while (my $token = $jsonr->get_token) {
        if ( $token->[0] == START_PROPERTY && $token->[1] eq "guid" ) {
            my $guid_token = $jsonr->get_token;
            if ( $guid_token->[0] == ADD_STRING && $guid_token->[1] eq $guid ) {
                $got{guid} = $guid_token->[1];
                INNER:
                    while (my $token = $jsonr->get_token) {

                        last OUTER if exists $got{age}
                                   && exists $got{name}
                                   && exists $got{tags};

                        if ( $token->[0] == START_PROPERTY ) {
                            if ( $token->[1] eq "age" ) {
                                my $age_token = $jsonr->get_token;
                                die 'Type error, expected number'
                                    unless $age_token->[0] == ADD_NUMBER;
                                $got{age} = $age_token->[1];
                            }
                            elsif ( $token->[1] eq "name" ) {
                                my $name_token = $jsonr->get_token;
                                die 'Type error, expected string'
                                    unless $name_token->[0] == ADD_STRING;
                                $got{name} = $name_token->[1];
                            }
                            elsif (  $token->[1] eq "tags" ) {
                                my $tags_token = $jsonr->get_token;
                                die 'Type error, expected array'
                                    unless $tags_token->[0] == START_ARRAY;
                                $got{tags} = JSON::Streaming::Util::slurp( $jsonr );
                            }
                        }
                    }
            }
            else {
                # the GUID did not match, we can discard the property
                $jsonr->skip;
                # then we can discard the rest of the object as well
                $jsonr->skip;
            }
        }
        else {
            # these are the tokens found until we get a match or not ...
            #warn JSON::Streaming::Tokens::dump_token( $token );
        }
    }

is_deeply( \%got, \%expected, '... got out value as expected' );


done_testing;
