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


sub build_property_matcher {
    my ($jsonr, $opts, $acc) = @_;

    return sub {
        my ($property_token) = @_;
        #use Data::Dumper;
        #warn Dumper $property_token;
        if ( $property_token->[1] eq $opts->{name} ) {
            my $value_token = $jsonr->get_token;
            die 'Type error' unless $value_token->[0] == $opts->{type};
            $acc->{ $opts->{name} } = $opts->{slurp}
                ? JSON::Streaming::Util::slurp( $jsonr )
                : $value_token->[1];
        }
        else {
            ($opts->{next} // return)->( $property_token );
        }
        return;
    }
}

sub match_and_accumulate {
    my ($jsonr, $specs, $acc) = @_;

    my @names;
    my $matcher;
    foreach my $spec ( reverse @$specs ) {
        push @names => $spec->{name};
        $matcher = build_property_matcher(
            $jsonr,
            { %$spec, $matcher ? (next => $matcher) : () },
            $acc
        );
    }

    while (my $token = $jsonr->get_token) {
        last if scalar @names == scalar grep { exists $acc->{ $_ } } @names;

        $matcher->( $token )
            if $token->[0] == START_PROPERTY;
    }

    return 1;
}

my %got;

# inflate based on this ...
my $schema = {
    type       => 'object',
    required   => [ 'guid' ],
    properties => {
        guid => { type => 'string'  },
        name => { type => 'string'  },
        age  => { type => 'integer' },
        tags => { type => 'array', items => { type => 'string' } },
    }
};

# query based on this (JSON-Pointer, value matcher)
my $query = { '/guid' => sub { $_ eq $guid } };

OUTER:
    while (my $token = $jsonr->get_token) {
        if ( $token->[0] == START_PROPERTY && $token->[1] eq "guid" ) {
            my $guid_token = $jsonr->get_token;
            if ( $guid_token->[0] == ADD_STRING && $guid_token->[1] eq $guid ) {
                $got{guid} = $guid_token->[1];
                match_and_accumulate(
                    $jsonr,
                    [
                        { name => 'age',  type => ADD_NUMBER },
                        { name => 'name', type => ADD_STRING },
                        { name => 'tags', type => START_ARRAY, slurp => 1 },
                    ],
                    \%got
                );
            }
            else {
                # the GUID did not match, we can discard the property
                # then we can discard the rest of the object as well
                $jsonr->skip->skip;
            }
        }
        else {
            # these are the tokens found until we get a match or not ...
            #warn JSON::Streaming::Tokens::dump_token( $token );
        }
    }

use Data::Dumper;
warn Dumper \%got;

is_deeply( \%got, \%expected, '... got out value as expected' );


done_testing;
