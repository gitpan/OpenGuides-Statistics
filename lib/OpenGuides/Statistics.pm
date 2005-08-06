package OpenGuides::Statistics;

use warnings;
use strict;

use vars qw($VERSION);

$VERSION = 1.2;

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

  die "Error: No wiki configuration file specified"  unless $options{wiki_conf};

  stat $options{wiki_conf} or die "Couldn't open wiki configuration file ($options{wiki_conf}): $!" if $!;

  $self->wiki_conf(OpenGuides::Config->new(file => $options{wiki_conf}));
  
  foreach (qw(graph_width graph_height))
  {
    if ($options{$_})
    {
      die "Error: '$_' must be a numbers; you specified '$_'." unless looks_like_number($options{$_});
      $self->$_($options{$_});
    }
  }

  foreach (qw(total_colour rate_line_colour rate_points_colour))
  {
    if ($options{$_})
    {
      die "Error: '$_' must be a 6-digit hex value; you specified '$options{$_}'." unless $options{$_} =~ /^[0-9a-fA-F]{6}$/;
      $self->$_($options{$_}); 
    }
  }

  if ($options{import_date})
  {
    die "Error: 'import_date' must be in yyyy-mm-dd format; you specified '$options{import_date}'." unless $options{import_date} =~ /^\d\d\d\d-\d\d-\d\d$/;
    $self->import_date($options{import_date});
  }
  
  if ($options{include_redirects})
  {
    die "Error: 'include_redirects' must be set to '1' if you set it." unless $options{include_redirects} eq "1";
    $self->include_redirects($options{include_redirects});
  }
  
  $self;
}

sub dbh
{
  my $self = shift;

  unless ($self->{dbh})
  {
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

    $self->{dbh} = DBI->connect($dsn, $dbuser, $dbpass) or die "Couldn't connect to database: $!";
  }
  
  $self->{dbh};
}

sub retrieve_node_data
{
  my $self = shift;

  my $dbh = $self->dbh;

  my $get_node_names = "SELECT DISTINCT name FROM node";

  my $sth = $dbh->prepare($get_node_names);
  $sth->execute or die $get_node_names;
  
  my (@list_of_nodes, %nodes);
  
  while (my @node_names = $sth->fetchrow_array)
  {
    push @list_of_nodes, $node_names[0];
  }  

  my $node_count = 0;

  foreach (@list_of_nodes)
  {
    # Get the date the node was created.
    my $get_original_date = "SELECT modified FROM content WHERE name=? AND version='1'";
    $sth = $dbh->prepare($get_original_date);
    $sth->execute($_);

    my @node_data = $sth->fetchrow_array;
    my $date = substr($node_data[0], 0, 10); # strip off times
    
    # Check the current content of the node - is it a redirect?
    if ($self->is_redirect($_))
    {
      # If yes, include in stats if user wants redirects
      if ($self->include_redirects)
      {
        if ($nodes{$date}) { $nodes{$date}++;   }
        else               { $nodes{$date} = 1; }
        
        $node_count++;
      }
      else
      {
        # User doesn't want redirects, decrement count for day this
        # now-redirecting node was created.
        $nodes{$date}-- if $nodes{$date};
      }
    }
    else
    {
      # Not a redirect, add it to the stats.
      if ($nodes{$date}) { $nodes{$date}++;   }
      else               { $nodes{$date} = 1; }
      
      $node_count++;
    }
  }  

  $self->node_count($node_count);

  \%nodes;
}

sub is_redirect
{
  my ($self, $node) = @_;
  my $dbh = $self->dbh;
  
  my $check_content = "SELECT text FROM content WHERE name=? AND version=?";
  my $sth = $dbh->prepare($check_content);

  my $version = $self->get_latest_version($node);
  
  $sth->execute($node, $version) or die $check_content;
      
  my @node_content = $sth->fetchrow_array;

  return 1 if $node_content[0] =~ /^\#REDIRECT/;
}

sub make_graphs
{
  my $self  = shift;
  my %nodes = %{$self->retrieve_node_data};

  # Our hash has keys of the form yyyy-mm-dd.
  # Chart::Strip requires time_t values, so get those and fill up a new hash.
  
  my ($total_graph_data, $rate_graph_data);
  my $count = 0;

  my $previous_day;
  
  foreach (sort keys %nodes)
  {
    my ($year, $month, $day) = split('-', $_);

    # Total number of nodes.
    $count += $nodes{$_};
     
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
    # at one point, you probably want that day to be included so as
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

# Find out the most recent version number of a given node name.
sub get_latest_version
{ 
  my $self = shift;
  my $name = shift;
  my $dbh  = $self->dbh;
  
  my $get_versions = "SELECT version FROM content WHERE name=?";
           
  my $sth = $dbh->prepare($get_versions);
                  
  $sth->execute($name) or die $get_versions;
                     
  my $latest_version;
                               
  while (my @row = $sth->fetchrow_array)
  {
    $latest_version = $row[0];
  }  
                                              
  $latest_version;
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

=item * C<include_redirects> Show nodes that are only redirects to other nodes. Defaults to undef.

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