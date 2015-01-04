#!/usr/bin/perl

# PODNAME: create_matrix

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Spec;
use IO::File;
use MetaCPAN::Client;
use Parse::CPAN::Packages;
use LWP::Simple qw(getstore);
use File::Temp ();
use JSON;
use DBI;

our $VERSION = 0.02;

my $db                   = _find_or_create_db();
my $perlbrew             = File::Spec->catdir( $ENV{HOME}, qw/perl5 perlbrew perls/ );
my @perl_versions        = _get_perl_versions( $perlbrew );
my @mojolicious_versions = _get_mojolicious_versions( \@perl_versions );

my $file = File::Temp->new( UNLINK => 1, SUFFIX => '.txt.gz' );
if ( !$ARGV[0] || !-f $ARGV[0] || $ARGV[0] !~ /02packages\.details\.txt\.gz$/ ) {
    print STDERR "Download 02packages.details.txt.gz...\n";
    my $url = 'http://www.cpan.org/modules/02packages.details.txt.gz';
    getstore $url, $file->filename;
    $ARGV[0] = $file->filename;
    print STDERR "downloaded " . (-s $file->filename) . " bytes to " . $file->filename . "\n";
}

my %modules = get_modules($ARGV[0]);
create_matrix( $db, $perlbrew, \@perl_versions, \@mojolicious_versions, \%modules );

sub create_matrix {
    my ($db, $brew, $perls, $mojos, $modules) = @_;

    my $sth  = $db->prepare( 'INSERT INTO matrix (pname, pversion, abstract, perl_version, mojo_version, result) VALUES( ?,?,?,?,?,? )' );
    my $sth_select = $db->prepare( 'SELECT pname FROM matrix WHERE pname = ? AND pversion = ? AND perl_version = ? AND mojo_version = ? LIMIT 1');

    print STDERR "Create matrix...\n";

    MODULE:
    for my $module ( sort keys %{ $modules } ) {
        my $name = $module =~ s/-/::/gr;
        my $info = $modules->{$module};

        next MODULE if $name eq 'Mojolicious';

        for my $perl ( @{ $perls } ) {

            MOJO:
            for my $mojo ( @{ $mojos } ) {
                my $dir     = File::Temp->newdir( CLEANUP => 1 );
                my $dirname = $dir->dirname;

                $sth_select->execute( $module, $info->{version}, $perl, $mojo );
                my $found_name;
                while ( my @row = $sth_select->fetchrow_array ) {
                    $found_name = shift @row;
                }

                next MOJO if $found_name;

                print STDERR "cpanm $name ($module) for Perl $perl/Mojolicious $mojo...\n";

                my $cpan  = File::Spec->catfile( $brew, 'perl-' . $perl, 'bin', 'cpanm' );
                my $perlx = File::Spec->catfile( $brew, 'perl-' . $perl, 'bin', 'perl' );
                my $inc   = File::Spec->catfile( $ENV{HOME}, 'mojolib', $perl, $mojo, "lib", "perl5" );
                #print STDERR qq{ $perlx -I$inc $cpan -L $dirname $name };
                my $cpanm_output = qx{ $perlx -I$inc $cpan -L $dirname $name };
                if (
                    $cpanm_output =~ m{Successfully installed $module-\d+} || 
                    $cpanm_output =~ m{$name is up to date} ) {
                    $sth->execute( $module, $info->{version}, $info->{abstract}, $perl, $mojo, 1 );
                    
                }
                else {
                    $sth->execute( $module, $info->{version}, $info->{abstract}, $perl, $mojo, 0 );
                }
            }
        }
    }
}

sub get_modules {
    my ($packages_file) = @_;

    print STDERR "Get modules...";

    my $parser        = Parse::CPAN::Packages->new( $packages_file );
    my @distributions = $parser->latest_distributions;
    my $mcpan         = MetaCPAN::Client->new;

    my %modules;
    for my $dist ( @distributions ) {
        my $name     = $dist->dist;

        next if $name !~ m!^Mojo (?:X|licious)!x;

        my $version  = $dist->version;

        print STDERR "found $name ($version)\n";

        my $abstract = $mcpan->release( $name )->abstract || '';

        $modules{$name} = +{ version => $version, abstract => $abstract };
    }

    print STDERR " found " . (scalar keys %modules) . "modules\n";

    return %modules;
}

sub _find_or_create_db {
    my $dbfile = File::Spec->catfile( dirname( __FILE__ ), '.plugins.sqlite' );
    my $exists = -f $dbfile;

    my $dbh = DBI->connect( 'DBI:SQLite:' . $dbfile );

    if ( !$exists ) {
        my @creates = (
            q~CREATE TABLE matrix ( pname TEXT NOT NULL, pversion TEXT NOT NULL, abstract TEXT, perl_version TEXT NOT NULL, mojo_version TEXT NOT NULL, result TEXT )~,
        );

        $dbh->do( $_ ) for @creates;
    }

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

    return @mojolicious_versions;
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

    return @versions;
}
