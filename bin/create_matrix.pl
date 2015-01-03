#!/usr/bin/perl

# PODNAME: create_task

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

our $VERSION = 0.01;

my $file = File::Temp->new( UNLINK => 1, SUFFIX => '.txt.gz' );
if ( !$ARGV[0] || !-f $ARGV[0] || $ARGV[0] !~ /02packages\.details\.txt\.gz$/ ) {
    print STDERR "Download 02packages.details.txt.gz...\n";
    my $url = 'http://www.cpan.org/modules/02packages.details.txt.gz';
    getstore $url, $file->filename;
    $ARGV[0] = $file->filename;
    print "downloaded " . (-s $file->filename) . " bytes to " . $file->filename . "\n";
}

my %modules = get_modules($ARGV[0]);
create_matrix( \%modules );
print JSON->new->encode( { perl => { path => $^X, version => $] }, results => \%modules } );

sub create_matrix {
    my ($modules) = @_;

    my $dir     = File::Temp->newdir( CLEANUP => 0 );
    my $dirname = $dir->dirname;

    print STDERR "Create matrix...\n";
    for my $module ( sort keys %{ $modules } ) {
        my $name = $module =~ s/-/::/gr;

        print STDERR "cpanm $name ($module)...\n";

        my $cpanm_output = qx{ cpanm -L $dirname $name };
        if (
            $cpanm_output =~ m{Successfully installed $module-\d+} || 
            $cpanm_output =~ m{$name is up to date} ) {
            $modules->{$module}->{installed} = 1;
        }
        else {
            $modules->{$module}->{installed} = 0;
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

