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
        my $cpanm   = File::Spec->catfile( $perlbrew, 'perl-' . $perl, 'bin', 'cpanm' );
        print STDERR "install DBD::Pg, DBD::mysql and cpanm-reporter...";
        qx{ $cpanm DBD::Pg };
        qx{ $cpanm --force DBD::mysql };
        qx{ $cpanm App::cpanminus::reporter };
        print STDERR "done\n";

        VERSION:
        for my $version ( @mojolicious_versions ) {
            print STDERR "Work on $dir/$perl/$version...";

            my $path = File::Spec->catdir( $dir, $perl, $version );
            File::Path::Tiny::mk( $path ) if !-d $path;

            my $inc   = File::Spec->catdir( $path, 'lib', 'perl5' );
            my $perlx = File::Spec->catfile( $perlbrew, 'perl-' . $perl, 'bin', 'perl' );
            my $qx    = qx{ $perlx -I$inc -MMojolicious -E 'say Mojolicious->VERSION' 2>&1};

            if ( $qx !~ m{Can't locate Mojolicious.pm} ) {
                print STDERR $qx;
                next VERSION;
            }

            my ($release) = $mcpan_client->release({
                'all' => [
                    { distribution => 'Mojolicious' },
                    { version      => "$version" },
                ],
            });
            my $target = $release->next->download_url;

            my @urls = ($target);
            for my $new ( qw{http://search.cpan.org/CPAN/ http://backpan.perl.org/} ) {
                my $new_target = $target =~ s{https://cpan.metacpan.org/}{$new}r;
                push @urls, $new_target;
            }

            URL:
            while ( @urls ) {
                my $url = shift @urls;
                print STDERR "$cpanm -L $path $url...\n";
                qx{ perlbrew exec --with $perl $cpanm -L $path $url };
                last URL if !$?;
            }

            my $check = qx{ $perlx -I$inc -MMojolicious -E 'say Mojolicious->VERSION'};
            print STDERR "ok...\n" if $check =~ m{$version};
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
