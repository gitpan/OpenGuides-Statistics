#!/usr/bin/perl

use warnings;
use strict;

use OpenGuides::Statistics;

my $outdir = '/var/www/OpenGuides/';

my $graph_width  = 500;
my $graph_height = 300;

my $stats = OpenGuides::Statistics->new(
  import_date         => '2000-01-01',
  wiki_conf           => '/home/user/openguides/wiki.conf',
  graph_width         => $graph_width,
  graph_height        => $graph_height,
  total_colour        => 'ff0000',
  rate_line_colour    => 'ff0000',
  rate_points_colour  => '000000'
);

my ($total_graph, $rate_graph) = $stats->make_graphs;
my $node_count                 = $stats->node_count;
my $site_name                  = $stats->wiki_conf->site_name;

open TOTAL_GRAPH, ">$outdir/node_total.png" or die $!;
print TOTAL_GRAPH $total_graph->png;
close TOTAL_GRAPH;
                                                                                                                                              
open RATE_GRAPH, ">$outdir/node_rate.png" or die $!;
print RATE_GRAPH $rate_graph->png;
close RATE_GRAPH;
                                                                                                                                                  
# Make nice dates for humans. There's probably a module somewhere
# that does this, but I can't be bothered to find it right now.

my (undef, undef, undef, $day, $month, $year) = gmtime(time);
$year += 1900;

my %month_names = 
(
  0  => 'January',
  1  => 'February',
  2  => 'March',
  3  => 'April',
  4  => 'May',
  5  => 'June',
  6  => 'July',
  7  => 'August',
  8  => 'September',
  9  => 'October',
  10 => 'November',
  11 => 'December'
);

my $monthname = $month_names{$month};

if    ($day =~ /^1\d$/) { $day .= 'th'; }
elsif ($day =~ /1$/)    { $day .= 'st'; }
elsif ($day =~ /2$/)    { $day .= 'nd'; }
elsif ($day =~ /3$/)    { $day .= 'rd'; }
else                    { $day .= 'th'; }


open INDEX, ">$outdir/index.html" or die $!;

print INDEX <<HTMLSTOP;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
  <meta http-equiv="Content-Type: text/html; charset=utf-8">
  <title>$site_name: Statistics</title>
<style type="text/css">
body
{
  background: #fff;
  color: #000;
}
</style>
</head>
<body>
<h1>$site_name: Statistics</h1>
<p>
Total number of nodes as of $day $monthname $year: $node_count.
</p>
<p>
<img src="node_total.png" width="$graph_width" height="$graph_height" alt="Node total graph">
</p>
<p>
<img src="node_rate.png" width="$graph_width" height="$graph_height" alt="Node creation rate graph"> 
</p>
</body>
</html>
HTMLSTOP
