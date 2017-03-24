#!perl

use strict;
use warnings;

use IO::Handle;
use Proc::ProcessTable;

use JSON::Streaming::Reader;

use constant VERBOSE => $ENV{VERBOSE} // 0;

my $proc_table = Proc::ProcessTable->new;
my $in_stream = IO::Handle->new_from_fd(fileno(STDIN), '<');
my $jsonr     = JSON::Streaming::Reader->for_stream($in_stream);

$| = 1;

print(('-' x 60), "\n") if VERBOSE;
printf("START : %d\n" => (grep { $_->pid eq $$ } @{ $proc_table->table })[0]->rss) if VERBOSE;
my $counter = 0;
while (my $token = $jsonr->get_token) {
    print("\rTOKENS: " . $counter++) if VERBOSE;
}
print("\n") if VERBOSE;
printf("END   : %d\n" => (grep { $_->pid eq $$ } @{ $proc_table->table })[0]->rss) if VERBOSE;
print(('-' x 60), "\n") if VERBOSE;
