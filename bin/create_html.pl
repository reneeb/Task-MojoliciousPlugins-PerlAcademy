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
    my $sth = $db->prepare( 'SELECT pname, pversion, abstract, perl_version, mojo_version, result, author FROM matrix' );
    $sth->execute;

    my %results = ( 0 => 'nok', 1 => 'ok', -1 => 'requires greater version of Mojolicious' );

    my %plugins;
    while ( my @row = $sth->fetchrow_array ) {
        $plugins{$row[0]}->{$row[1]}->{abstract} = $row[2];
        $plugins{$row[0]}->{$row[1]}->{author}   = $row[6];
        $plugins{$row[0]}->{$row[1]}->{"$row[3] / $row[4]"} = $results{$row[5]};
    }

    my $html = $self->render_to_string(
        'index',
        combis  => \@combis,
        plugins => \%plugins,
        mojos   => \@mojolicious_versions,
        perls   => \@perl_versions,
    );

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
% my %map = ( ok => 'ok', nok => 'nok', 'unknown' => 'unknown');
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
    <script src="http://code.jquery.com/jquery-2.1.3.min.js"></script>
    <script type="text/javascript">
/*
 jQuery Plugin: Table Filter v0.2.3

 LICENSE: http://hail2u.mit-license.org/2009
*/
(function(a){a.fn.addTableFilter=function(d){var b=a.extend({},a.fn.addTableFilter.defaults,d),c,e;this.is("table")&&(this.attr("id")||this.attr({id:"t-"+Math.floor(99999999*Math.random())}),c=this.attr("id"),d=c+"-filtering",e=a("<label/>").attr({"for":d}).append(b.labelText),b=a('<input type="search"/>').attr({id:d,size:b.size}).on("click",function(){a(this).keyup()}),a("<p/>").addClass("formTableFilter").append(e).append(b).insertBefore(this),a("#"+d).delayBind("keyup",function(b){var d=a(this).val().toLowerCase().split(" ");
a("#"+c+" tbody tr").each(function(){var b=a(this).html().toLowerCase().replace(/<.+?>/g,"").replace(/\s+/g," "),c=0;a.each(d,function(){if(0>b.indexOf(this))return c=1,!1});c?a(this).hide():a(this).show()})},300));return this};a.fn.addTableFilter.defaults={labelText:"Keyword(s): ",size:32};a.fn.delayBind=function(d,b,c,e){a.isFunction(b)&&(e=c,c=b,b=void 0);var g=this,f=null;return this.bind(d,b,function(b){clearTimeout(f);f=setTimeout(function(){c.apply(g,[a.extend({},b)])},e)})}})(jQuery);
    </script>
  </head>
  <body>
    <div class="filter">
       Mojolicious:
% for my $index ( 0 .. $#{ $mojos } ) {
%     my $mojo       = $mojos->[$index];
%     my $latest     = $index == $#{$mojos} ? 'checked="checked"' : '';
%     (my $mojo_value = $mojo) =~ tr/./-/;
         <input type="checkbox" name="filter" value="<%= $mojo_value %>" <%== $latest %> /><%= $mojo %>
% }
       Perl:
% for my $index ( 0 .. $#{ $perls } ) {
%     my $perl       = $perls->[$index];
%     my $latest     = $index == $#{$perls} ? 'checked="checked"' : '';
%     (my $perl_value = $perl) =~ tr/./-/;
         <input type="checkbox" name="filter" value="<%= $perl_value %>" <%== $latest %> /><%= $perl %>
% }
    </div>
    <script type="text/javascript">
        $(document).ready( function() {
           $("table").addTableFilter();

           switch_on_off();
           $('input[name="filter"]').bind( 'change', function() { switch_on_off() } );
        });

        function switch_on_off () {
           $('.switch').hide();

           $('input[name="filter"]').each(function( index, elem ) {               
               var classname = $(elem).val();
               switch_cells( $(elem).is(':checked'), classname );
           });
        }

        function switch_cells ( checked, classname ) {
           if( checked ) {
               $('th.' + classname ).show();
               $('td.' + classname ).show();
           }
        }
    </script>
    <table>
      <thead>
        <tr>
          <th>Plugin name</th>
          <th>Abstract</th>
          <th>Author</th>
% for my $combi ( @{ $combis } ) {
%     (my $combi_class = $combi) =~ tr/.\//- /d;
          <th class="switch <%= $combi_class %>"><%= $combi %></th>
% }
        </tr>
      </thead>
      <tbody>
% for my $plugin ( sort keys %{ $plugins } ) {
%   my @versions = reverse sort keys %{ $plugins->{$plugin} };
%   my $latest   = $versions[0];
%   my $module   = $plugin =~ s/-/::/gr;
        <tr>
          <td><a href="https://metacpan.org/pod/<%= $module %>"><%= $plugin %> <%= $latest %></a></td>
          <td><%= $plugins->{$plugin}->{$latest}->{abstract} %></td>
          <td><%= $plugins->{$plugin}->{$latest}->{author} // '' %></td>
% for my $combi ( @{ $combis } ) {
%     my $result_class = $map{ $plugins->{$plugin}->{$latest}->{$combi} } // $map{unknown};
%     (my $combi_class = $combi) =~ tr/.\//- /d;
          <td class="switch <%= $combi_class %> <%= $result_class %>"><%= $plugins->{$plugin}->{$latest}->{$combi} %></td>
% }
        </tr>
% }
      </tbody>
    </table>
    <a href="http://perl-services.de/impressum.html">Impressum</a>
  </body>
</html>

