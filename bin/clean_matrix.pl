#!/usr/bin/env perl

use strict;
use warnings;

use File::Path::Tiny;
use Getopt::Long;
use DBI;

my $mojolibs = File::Spec->catdir( $ENV{HOME}, qw/mojolib/ ); 
my $db       = _connect_db();
my $perlbrew = File::Spec->catdir( $ENV{HOME}, qw/perl5 perlbrew perls/ );

GetOptions(
    'perl=s' => \my @perls,
    'mojo=s' => \my @mojos,
);

my $delete_perl = 'DELETE FROM matrix WHERE perl_version = ?';
my $delete_mojo = 'DELETE FROM matrix WHERE mojo_version = ?';

for my $perl ( @perls ) {
    $db->do( $delete_perl, undef, $perl );
    File::Path::Tiny::rm( File::Spec->catdir( $mojolibs, $perl ) );
    qx{perlbrew uninstall $perl};
}

my @perl_versions = _get_perl_versions($perlbrew);

for my $mojo ( @mojos ) {
    $db->do( $delete_mojo, undef, $mojo );
    for my $perl ( @perl_versions ) {
        File::Path::Tiny::rm( File::Spec->catdir( $mojolibs, $perl, $mojo ) );
    }
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

sub _connect_db {
    my $dbfile = File::Spec->catfile( dirname( __FILE__ ), '.plugins.sqlite' );
    my $exists = -f $dbfile;

    die "Cannot find DB" if !$exists;

    my $dbh = DBI->connect( 'DBI:SQLite:' . $dbfile );
    return $dbh;
}
