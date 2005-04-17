use Test::More tests => 4;

#1
use_ok(OpenGuides::Statistics);

my $stats;
my $status = 'ok';

eval {
  $stats = OpenGuides::Statistics->new(wiki_conf => 't/wiki.conf');
};

$status = $@ if $@;

#2
ok($status eq 'ok', 'load example OpenGuides config file');

eval {
  $stats = OpenGuides::Statistics->new;
};

$status = $@ if $@;

#3
ok($status =~ /^No wiki configuration file specified/, "can't start up without config file");

eval {
  $stats = OpenGuides::Statistics->new(
                                       wiki_conf    => 't/wiki.conf',
                                       graph_width  => 640,
                                       graph_height => 'fred'
                                      );
};

$status = $@ if $@;

#4
ok($status =~ /^Graph height and width must be numbers/, "can't use a duff graph option");
