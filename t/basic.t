use Test::More tests => 6;

#1
use_ok(OpenGuides::Statistics);

my $stats;
my $status = 'ok';

eval
{
  $stats = OpenGuides::Statistics->new(wiki_conf => 't/wiki.conf');
};

$status = $@ if $@;

#2
ok($status eq 'ok', 'load example OpenGuides config file');

eval
{
  $stats = OpenGuides::Statistics->new;
};

$status = $@ if $@;

#3
ok($status =~ /^Error: No wiki configuration file specified/, "can't start up without config file");

eval
{
  $stats = OpenGuides::Statistics->new(
                                        wiki_conf    => 't/wiki.conf',
                                        graph_width  => 640,
                                        graph_height => 'fred',
                                      );
};

$status = $@ if $@;

#4
ok($status =~ /^Error: 'graph_height' must be a number/, "can't use a malformed graph option");

eval {
  $stats = OpenGuides::Statistics->new(
                                        wiki_conf    => 't/wiki.conf',
                                        include_redirects => 2,
                                      );
};

$status = $@ if $@;

#5
ok($status =~ /^Error: 'include_redirects' must be set to '1' if you set it./, "can't use an illogical include_redirects option");

eval {
  $stats = OpenGuides::Statistics->new(
                                        wiki_conf    => 't/wiki.conf',
                                        total_colour => 'fred',
                                      );
};

$status = $@ if $@;

#6
ok($status =~ /^Error: 'total_colour' must be a 6-digit hex value/, "can't use a malformed colour value");
