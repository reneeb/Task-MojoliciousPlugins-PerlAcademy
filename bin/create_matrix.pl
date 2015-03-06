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
use List::Util qw(first);
use HTTP::Tiny;

our $VERSION = 0.03;

my $db                   = _find_or_create_db();
my $perlbrew             = File::Spec->catdir( $ENV{HOME}, qw/perl5 perlbrew perls/ );
my @perl_versions        = _get_perl_versions( $perlbrew );
my @mojolicious_versions = _get_mojolicious_versions( \@perl_versions );

my $file = File::Temp->new( UNLINK => 1, SUFFIX => '.txt.gz' );
print STDERR "Download 02packages.details.txt.gz...\n";
my $url = 'http://www.cpan.org/modules/02packages.details.txt.gz';
getstore $url, $file->filename;
print STDERR "downloaded " . (-s $file->filename) . " bytes to " . $file->filename . "\n";

my %modules = get_modules( $file->filename, \@ARGV );
create_matrix( $db, $perlbrew, \@perl_versions, \@mojolicious_versions, \%modules, \@ARGV );

sub create_matrix {
    my ($db, $brew, $perls, $mojos, $modules, $requested) = @_;

    my $sth  = $db->prepare( 'INSERT INTO matrix (pname, pversion, abstract, perl_version, mojo_version, result, author, error_log) VALUES( ?,?,?,?,?,?,?,? )' );
    my $sth_select = $db->prepare( 'SELECT pname FROM matrix WHERE pname = ? AND pversion = ? AND perl_version = ? AND mojo_version = ? LIMIT 1');

    print STDERR "Create matrix...\n";

    my $blacklist = File::Spec->catfile( dirname( __FILE__ ), 'blacklist' );
    my %blacklisted_modules;
    if ( -f $blacklist ) {
        print STDERR "read blacklist...";
        if ( open my $fh, '<', $blacklist ) {
            while ( my $line = <$fh> ) {
                chomp $line;
                next if !$line;
                print STDERR "$line\n";
                $blacklisted_modules{$line}++;
            }
            print STDERR "done\n";
        }
        else {
            print STDERR "error ($!)\n";
        }
    }

    my $report = '';

    MODULE:
    for my $module ( sort keys %{ $modules } ) {
        my $name = $module =~ s/-/::/gr;
        my $info = $modules->{$module};

        if ( $requested && @{ $requested } && !first{ $module eq $_ }@{ $requested } ) {
            next MODULE;
        }

        next MODULE if $name eq 'Mojolicious';
        if ( $blacklisted_modules{$module} ) {
            print STDERR "Skipped $module as it is blacklisted!\n";
            next MODULE;
        }

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

                if ( $mojo < $info->{dependency} ) {
                    print STDERR "$module requires Mojolicious " . $info->{dependency} . "\n";
                    $sth->execute( $module, $info->{version}, $info->{abstract}, $perl, $mojo, "-1", $info->{author}, '' );
                    next MOJO;
                }

                print STDERR "cpanm $name ($module) for Perl $perl/Mojolicious $mojo...\n";
                my $cpan  = File::Spec->catfile( $brew, 'perl-' . $perl, 'bin', 'cpanm' );
                my $perlx = File::Spec->catfile( $brew, 'perl-' . $perl, 'bin', 'perl' );
                my $inc   = File::Spec->catfile( $ENV{HOME}, 'mojolib', $perl, $mojo, "lib", "perl5" );
                my $cpanm_output = qx{ PERL5LIB=$inc perlbrew exec --with perl-$perl $cpan --print-dir --local-lib $dirname $name };
                my $error        = $? ? 1 : 0;
                my $pversion = $info->{version};

                my ($work_directory) = $cpanm_output =~ m{Work directory is (.*)\r?\n};

                if ( $cpanm_output =~ m{Successfully installed Mojolicious-\d+} ) {
                    $sth->execute( $module, $info->{version}, $info->{abstract}, $perl, $mojo, "-1", $info->{author}, '' );
                    my $cpanm_reporter = File::Spec->catfile( $brew, 'perl-' . $perl, 'bin', 'cpanm-reporter' );
                    qx{ $cpanm_reporter --build_dir $work_directory };
                }
                elsif ( !$error ) {
                    $sth->execute( $module, $info->{version}, $info->{abstract}, $perl, $mojo, 1, $info->{author}, '' );
                    my $cpanm_reporter = File::Spec->catfile( $brew, 'perl-' . $perl, 'bin', 'cpanm-reporter' );
                    qx{ $cpanm_reporter --build_dir $work_directory };
                }
                else {
                    my $fh  = IO::File->new( File::Spec->catfile( $work_directory, 'build.log' ), 'r' );
                    my $log = '';
                    {
                        local $/;
                        $log = <$fh>;
                    }
                    $fh->close;

                    $sth->execute( $module, $info->{version}, $info->{abstract}, $perl, $mojo, 0, $info->{author}, $log // '' );
                    $report .= sprintf "%s %s (%s/%s)\n", $module, $info->{version}, $perl, $mojo;
                }
            }
        }
    }

    print STDERR $report,"\n";
}

sub get_modules {
    my ($packages_file, $preselected) = @_;

    my $whitelist = File::Spec->catfile( dirname( __FILE__ ), 'whitelist' );
    my %whitelisted_modules;
    if ( -f $whitelist ) {
        print STDERR "read whitelist...";
        if ( open my $fh, '<', $whitelist ) {
            while ( my $line = <$fh> ) {
                chomp $line;
                next if !$line;
                print STDERR "$line\n";
                $whitelisted_modules{$line}++;
            }
            print STDERR "done\n";
        }
        else {
            print STDERR "error ($!)\n";
        }
    }

    print STDERR "Get modules...";

    my $parser        = Parse::CPAN::Packages->new( $packages_file );
    my $mcpan         = MetaCPAN::Client->new(
        ua => HTTP::Tiny->new( agent => 'Mojolicious Plugin Matrix (mojo.perl-services.de) / ' . $VERSION ),
    );

    my @distributions;
    if ( $preselected && @{ $preselected } ) {
        for my $package ( @{ $preselected } ) {
            my $name = $package =~ s/-/::/gr;
            my $module = $parser->package( $name );
            push @distributions, $module->distribution;
        }
    }
    else {
        @distributions = $parser->latest_distributions;
    }

    my %modules;
    for my $dist ( @distributions ) {
        my $name = $dist->dist;

        next if $name !~ m!^Mojo (?:X|licious)?-!x && !$whitelisted_modules{$name};

        my $version  = $dist->version;

        my $releases = $mcpan->release({ all => [ { distribution => $name }, { version => $version } ] })->next;
        my $release  = $releases ? $releases : $mcpan->release( $name );
        my $abstract = $release->abstract || '';

        print STDERR "found $name ($version)\n";

        my ($depends) =
            map{$_->{version_numified}}
            grep{
                $_->{module} =~ m{\AMojo(?:licious)?\z}
            }@{ $release->dependency || [{module => 1}] };

        $modules{$name} = +{
            version    => $version,
            abstract   => $abstract,
            dependency => ( $depends || 0 ),
            author     => $release->author,
        };
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
            q~CREATE TABLE matrix ( pname TEXT NOT NULL, pversion TEXT NOT NULL, abstract TEXT, perl_version TEXT NOT NULL, mojo_version TEXT NOT NULL, result TEXT, author TEXT, error_log TEXT )~,
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
