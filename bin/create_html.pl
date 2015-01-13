#!/usr/bin/perl

use strict;
use warnings;

use Mojolicious::Lite;
use Test::More;
use Test::Mojo;
use File::Spec;
use File::Basename;
use Mojo::Util qw(url_escape);
use DBI;

get '/' => sub {
    my $self = shift;

    my $perlbrew             = File::Spec->catdir( $ENV{HOME}, qw/perl5 perlbrew perls/ );
    my @perl_versions        = _get_perl_versions( $perlbrew );
    my @mojolicious_versions = _get_mojolicious_versions( \@perl_versions );

    my @combis = map{ my $perl = $_; map{ "$perl / $_" }@mojolicious_versions }@perl_versions;

    my $db  = _connect_db();
    my $sth = $db->prepare( 'SELECT pname, pversion, abstract, perl_version, mojo_version, result FROM matrix' );
    $sth->execute;

    my %results = ( 0 => 'nok', 1 => 'ok', -1 => 'requires greater version of Mojolicious' );

    my %plugins;
    while ( my @row = $sth->fetchrow_array ) {
        $plugins{$row[0]}->{$row[1]}->{abstract} = $row[2];
        $plugins{$row[0]}->{$row[1]}->{"$row[3] / $row[4]"} = $results{$row[5]};
    }

    my $html = $self->render_to_string( 'index', combis => \@combis, plugins => \%plugins );
    my $path = $self->param('path') || File::Spec->catfile( dirname( __FILE__ ), 'matrix.html' );
    if ( open my $fh, '>', $path ) {
        print $fh $html;
    }

    $self->render( text => $self->b( $html ) );
};

my $path = '';
if ( $ARGV[0] ) {
    $path = '?path=' . url_escape( $ARGV[0] );
}

my $t = Test::Mojo->new;

$t->get_ok('/' . $path );
print $t->tx->res->body;

done_testing();

sub _connect_db {
    my $dbfile = File::Spec->catfile( dirname( __FILE__ ), '.plugins.sqlite' );
    my $exists = -f $dbfile;

    my $dbh = DBI->connect( 'DBI:SQLite:' . $dbfile );

    return $dbh;
}

sub _get_mojolicious_versions {
    my $perls = shift;

    my $dir = File::Spec->catdir( $ENV{HOME}, qw/mojolib/ );
    my @mojolicious_versions;
    opendir my $mojolibh, File::Spec->catdir( $dir, $perls->[0] );
    while ( my $version = readdir $mojolibh ) {
        next if $version !~ m{\A[0-9]+\.};
        push @mojolicious_versions, $version;
    }
    closedir $mojolibh;

    return sort @mojolicious_versions;
}

sub _get_perl_versions {
    my @versions;
    opendir my $dirh, shift;
    while ( my $version = readdir $dirh ) {
        next if $version =~ m{\A\.\.?\z};
        $version =~ s/perl-//;
        push @versions, $version;
    }
    closedir $dirh;

    return sort @versions;
}


__DATA__
@@ index.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>Mojolicious-Plugins : Installable</title>
<meta name="revisit-after" content="30 days">
<meta name="robots" content="index, follow">
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <style type="text/css">
      .ok {
        background-color: green;
        color: white;
      }
      .nok {
        background-color: red;
        color: white;
      }
    </style>
  </head>
  <body>
    <table>
      <thead>
        <tr>
          <th>Plugin name</th>
          <th>Abstract</th>
% for my $combi ( @{ $combis } ) {
          <th><%= $combi %></th>
% }
        </tr>
      </thead>
      <tbody>
% for my $plugin ( sort keys %{ $plugins } ) {
%   my @versions = reverse sort keys %{ $plugins->{$plugin} };
%   my $latest   = $versions[0];
        <tr>
          <td><%= $plugin %> <%= $latest %></td>
          <td><%= $plugins->{$plugin}->{$latest}->{abstract} %></td>
% for my $combi ( @{ $combis } ) {
          <td class="<%= $plugins->{$plugin}->{$latest}->{$combi} %>"><%= $plugins->{$plugin}->{$latest}->{$combi} %></td>
% }
        </tr>
% }
      </tbody>
    </table>
    <a href="http://perl-services.de/impressum.html">Impressum</a>
  </body>
</html>

