#!perl

use strict;
use warnings;

use IO::Handle;
use Proc::ProcessTable;

use JSON::XS;

my $proc_table = Proc::ProcessTable->new;
my $json       = JSON::XS->new;

$| = 1;

print(('-' x 60), "\n");
printf "START : %d\n" => (grep { $_->pid eq $$ } @{ $proc_table->table })[0]->rss;
my $output = $json->decode( join '' => <ARGV> );
printf "END   : %d\n" => (grep { $_->pid eq $$ } @{ $proc_table->table })[0]->rss;
print(('-' x 60), "\n");
