#!/usr/bin/env perl

use strict;
use warnings;

use File::Path::Tiny;
use File::Spec;
use MetaCPAN::Client;
use Data::Dumper;

my $perlbrew    = File::Spec->catdir( $ENV{HOME}, qw/perl5 perlbrew perls/ );
my @perls       = _get_perl_versions( $perlbrew );
my @mojolicious = _get_and_install_mojolicious_versions( $perlbrew, \@perls );

#print Dumper [ \@perls, \@mojolicious ];

sub _get_and_install_mojolicious_versions {
    my $perlbrew = shift;
    my $perls    = shift;

    my $mcpan_client   = MetaCPAN::Client->new;
    my $latest         = $mcpan_client->release( 'Mojolicious' );
    my $latest_version = $latest->version;

    my $dir = File::Spec->catdir( $ENV{HOME}, qw/mojolib/ );
    my @mojolicious_versions;
    opendir my $mojolibh, File::Spec->catdir( $dir, $perls->[0] );
    while ( my $version = readdir $mojolibh ) {
        next if $version !~ m{\A[0-9]+\.};
        push @mojolicious_versions, $version;
    }
    closedir $mojolibh;
    push @mojolicious_versions, $latest_version;

    for my $perl ( @{ $perls } ) {

        VERSION:
        for my $version ( @mojolicious_versions ) {
            print STDERR "Work on $dir/$perl/$version...\n";
            my $path = File::Spec->catdir( $dir, $perl, $version );
            File::Path::Tiny::mk( $path ) if !-d $path;

            my $inc   = File::Spec->catdir( $path, 'lib', 'perl5' );
            my $perlx = File::Spec->catfile( $perlbrew, 'perl-' . $perl, 'bin', 'perl' );
            my $qx    = qx{ $perlx -I$inc -Mojo -e 1 2>&1};

            next VERSION if !$qx || $qx !~ m{Can't locate ojo.pm};

            my $target = 'Mojolicious';
            if ( $version ne $latest_version ) {
                my ($release) = $mcpan_client->release({
                    'all' => [
                        { distribution => 'Mojolicious' },
                        { version      => "$version" },
                    ],
                });
                my $target = $release->next->download_url;
            }

            my $cpanm   = File::Spec->catfile( $perlbrew, 'perl-' . $perl, 'bin', 'cpanm' );
            print STDERR "$cpanm -L $path $target...\n";
            qx{ $cpanm -L $path $target };
        }
    }

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
