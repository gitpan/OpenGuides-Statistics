package OpenGuides::Statistics;

use warnings;
use strict;

use vars qw($VERSION);

$VERSION = 1;

use Chart::Strip;
use DBI;
use OpenGuides::Config;
use POSIX qw(mktime);
use Scalar::Util qw(looks_like_number);

sub new
{
  my $class = shift;
  my %options = @_;
  my $self  = bless {}, $class;

  die "No wiki configuration file specified"  unless $options{wiki_conf};

  stat $options{wiki_conf} or die "Couldn't open wiki configuration file ($options{wiki_conf}): $!" if $!;

  $self->wiki_conf(OpenGuides::Config->new(file => $options{wiki_conf}));
  
  foreach (qw(graph_width graph_height))
  {
    if ($options{$_})
    {
      die "Graph height and width must be numbers" unless looks_like_number($options{$_}) == 1;
      $self->$_($options{$_});
    }
  }

  foreach (qw(total_colour rate_line_colour rate_points_colour))
  {
    if ($options{$_})
    {
      die "Graph colours must be 6-digit hex values" unless $options{$_} =~ /^[0-9a-fA-F]{6}$/;
      $self->$_($options{$_}); 
    }
  }

  if ($options{import_date})
  {
    die "Error: import date ($options{import_date}) was not in yyyy-mm-dd format" unless $options{import_date} =~ /^\d\d\d\d-\d\d-\d\d$/;
    $self->import_date($options{import_date});
  }
  
  $self;
}

sub retrieve_node_data
{
  my $self = shift;
  my $dsn;

  my $wiki_conf = $self->wiki_conf;
  my $dbtype    = $wiki_conf->dbtype;
  my $dbname    = $wiki_conf->dbname;
  my $dbhost    = $wiki_conf->dbhost || '';
  my $dbuser    = $wiki_conf->dbuser || '';
  my $dbpass    = $wiki_conf->dbpass || '';

  if    ($dbtype eq 'mysql')    { $dsn = "dbi:mysql:database=$dbname;host=$dbhost"; }
  elsif ($dbtype eq 'postgres') { $dsn = "dbi:Pg:dbname=$dbname;host=$dbhost"; }
  elsif ($dbtype eq 'sqlite')   { $dsn = "dbi:SQLite:dbname=$dbname"; }
  else                          { die "Unknown database type specified: $dbtype"; }

  my $dbh = DBI->connect($dsn, $dbuser, $dbpass) or die "Couldn't connect to database: $!";

  my $get_nodes = "SELECT name, modified FROM content WHERE version='1'";

  my $sth = $dbh->prepare($get_nodes);
  $sth->execute or die $get_nodes;

  my %nodes;

  while (my @node_data = $sth->fetchrow_array)
  {
    my $name = $node_data[0];
    my $date = substr($node_data[1], 0, 10); # strip off times

    # count occurrences of each date

    if ($nodes{$date}) { $nodes{$date}++;   }
    else               { $nodes{$date} = 1; }
  }

  return %nodes;
}

sub make_graphs
{
  my $self  = shift;
  my %nodes = $self->retrieve_node_data;

  # Our hash has keys of the form yyyy-mm-dd.
  # Chart::Strip requires time_t values, so get those and fill up a new hash.
  
  my ($total_graph_data, $rate_graph_data);
  my $count = 0;

  my $previous_day;
  
  foreach (sort keys %nodes)
  {
    my ($year, $month, $day) = split('-', $_);

    # We want to ignore days with a disproportionally high count
    # that may have been caused by vandals, spammers or plain old
    # crazy robots.
    
    # First step, remember how many pages were made in the previous
    # day of all the days this loop is examining. Initialize the
    # variable if we haven't already.
    $previous_day = $nodes{$_} unless $previous_day;

    # The threshold is 15 times more than the previous day. Of 
    # course, we have to ignore days when no nodes were created,
    # otherwise we could get lots of false positives.
    next if ($previous_day > 1) && ($nodes{$_} > ($previous_day * 15));

    # If we got here the count was valid, so remember it for the 
    # next pass through the loop.
    $previous_day = $nodes{$_};

    # Total number of nodes.
    $count += $nodes{$_};
 
    # Store total.
    $self->node_count($count);
    
    $month--;      # I hate POSIX.
    $year -= 1900; # No, really. I do.

    my $time_t = mktime( 0, 0, 0, $day, $month, $year );

    # Make the data structure Chart::Strip expects - one for 
    # total number of nodes, and the other for node creation rate.
    push @$total_graph_data, {
                               time  => $time_t,
                               value => $count,
                             };

    push @$rate_graph_data, {
                               time  => $time_t,
                               value => $nodes{$_},
                               diam  => 2
                             } unless $self->import_date && $self->import_date eq $_;
    # What that 'unless' means is that if you imported all your nodes 
    # at one point, you probably want that day to be ignored so as
    # not to have a huge spike at the beginning of your graph.
  }

  my $site_name          = $self->wiki_conf->site_name;
  my $width              = $self->graph_width        || 640;
  my $height             = $self->graph_height       || 480;
  my $total_colour       = $self->total_colour       || '000000';
  my $rate_line_colour   = $self->rate_line_colour   || '000000';
  my $rate_points_colour = $self->rate_points_colour || '000000';

  my $total_graph = Chart::Strip->new(
     title   => "Number of nodes on $site_name",
     x_label => 'Date',
     y_label => 'Total nodes',
     width   => $width,
     height  => $height
  );

  my $outdir = $self->{outdir};

  $total_graph->add_data( $total_graph_data, { 
                                   style => 'filled', 
                                   color => $total_colour 
                                 } );

  my $rate_graph = Chart::Strip->new(
     title   => "Rate of node creation on $site_name",
     x_label => 'Date',
     y_label => 'Nodes per day',
     width   => $width,
     height  => $height
  );

  $rate_graph->add_data( $rate_graph_data, { 
                                   style => 'line', 
                                   color => $rate_line_colour
                                 } );

  $rate_graph->add_data( $rate_graph_data, { 
                                   style => 'points', 
                                   color => $rate_points_colour
                                 } );

  ($total_graph, $rate_graph);
}

# Generate the get/set methods for object internal data.
sub AUTOLOAD {
  my ($self, $data) = @_;

  use vars qw($AUTOLOAD);
  my $data_member = $AUTOLOAD;
  $data_member =~ s/.*:://;

  $data_member = '_' . $data_member;
  
  if ($data) { $self->{$data_member} = $data; }
  else       { $self->{$data_member}; }  
} 

1;

__END__

=head1 NAME

OpenGuides::Statistics - generate graphs of the number of nodes on an OpenGuides site

=head1 SYNOPSIS

    use OpenGuides::Statistics;

    my $stats = 
      OpenGuides::Statistics->new( wiki_conf   => '/path/to/your/openguides/wiki.conf',
                                   import_date => '2000-01-01' );
      
    my ($total_graph, $rate_graph) = $stats->make_graphs;
    my $node_count                 = $stats->node_count;
      
=head1 DESCRIPTION

This module will read your L<OpenGuides> database and produce L<Chart::Strip> graphs of 
the data therein to show you how fast you've accumulated nodes.

=head1 METHODS

=head2 C<new()>

    my $stats =
      OpenGuides::Statistics->new( wiki_conf   => '/path/to/your/openguides/wiki.conf',
                                   import_date => '2000-01-01' );

There's only one required argument, C<wiki_conf>. This is a path to the configuration file
of your OpenGuides installation, which this module will load to know how to access your
wiki's database. Optional arguments:

=over 4

=item * C<import_date>  Use this to ignore a certain date when reading the node creation dates 
from your database. This is useful if your database was created by importing an existing 
database, which would otherwise cause a large spike at the beginning of your graph. Takes a 
date string in the format yyyy-mm-dd.

=item * C<graph_width> Width in pixels of your graphs. Defaults to 640.

=item * C<graph_height> Height in pixels of your graphs. Defaults to 480.

=item * C<total_colour> The colour of the filled area in the "total nodes" graph. Must be a 
six-digit hex colour, e.g. 6699CC. Defaults to 000000.

=item * C<rate_line_colour> The colour of the line in the rate graph. Defaults to 000000.

=item * C<rate_points_colour> The colour of the points in the rate graph. Defaults to 000000.

=back

=head2 C<make_graphs()>

    my ($total_graph, $rate_graph) = $stats->make_graphs;

This method will return two L<Chart::Strip> objects, which have three possible output 
methods: C<png()> (returns a PNG image), C<jpeg()> (returns a JPEG image) and C<gd()> 
(returns an underlying L<GD> object). An example of how to use the objects is included
in the 'examples' directory of this distribution.

=head2 C<node_count()>

    my $node_count = $stats->node_count;

This method will return a scalar value of how many nodes there are in your database.

=head1 AUTHOR

Earle Martin <EMARTIN@cpan.org>

=over 4 

=item L<http://purl.oclc.org/net/earlemartin/>

=back

=head1 LEGAL

Copyright 2005 Earle Martin. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

=over 4

=item L<OpenGuides>

=item L<http://openguides.org/>

=back

=cut