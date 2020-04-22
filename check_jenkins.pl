#!/usr/bin/perl
#
# This Nagios plugin count the number of jobs of a Jenkins instance.
# It can check that the total number of jobs will not exeed the WARNING and CRITICAL thresholds.
# It also count the number of disabled, passed, running and failed jobs and can check that the ratio
# of failed jobs against active jobs is over a WARNING and CRITICAL thresholds.
# Performance data are:
# jobs=<count>;<warn>;<crit> passed=<count> failed=<count>;<warn>;<crit> disabled=<count> running=<count>
#
# Author: Eric Blanchard
# Modified: Ramón Román Castro
#
use strict;
use LWP::UserAgent;
use JSON;
use Getopt::Long
  qw(GetOptions HelpMessage VersionMessage :config no_ignore_case bundling);
use Pod::Usage qw(pod2usage);

# Nagios return values
use constant {
    OK       => 0,
    WARNING  => 1,
    CRITICAL => 2,
    UNKNOWN  => 3,
};
use constant API_SUFFIX => "/api/json";
our $VERSION = '1.7.1';
my %args;
my $ciMasterUrl;
my $debug       = 0;
my $status_line = '';
my $exit_code   = UNKNOWN;
my $timeout     = 10;
my $username    = '';
my $password    = '';
my $insecure    = 0;

# Functions prototypes
sub trace(@);

# Main
GetOptions(
    \%args,
    'version|v' => sub { VersionMessage( { '-exitval' => UNKNOWN } ) },
    'help|h'    => sub { HelpMessage(    { '-exitval' => UNKNOWN } ) },
    'man' => sub { pod2usage( { '-verbose' => 2, '-exitval' => UNKNOWN } ) },
    'debug|d'     => \$debug,
    'timeout|t=i' => \$timeout,
    'proxy=s',
    'noproxy',
    'noperfdata',
	'insecure',
    'username|u=s' => \$username,
    'password|p=s' => \$password
  )
  or pod2usage( { '-exitval' => UNKNOWN } );
HelpMessage(
    { '-msg' => 'UNKNOWN: Missing Jenkins url parameter', '-exitval' => UNKNOWN } )
  if scalar(@ARGV) != 1;
$ciMasterUrl = $ARGV[0];
$ciMasterUrl =~ s/\/$//;

# Master API request
my $ua = LWP::UserAgent->new();
$ua->timeout($timeout);

if ( defined( $args{insecure} ) ) {
    $ua->ssl_opts('verify_hostname' => 0);
}
if ( defined( $args{proxy} ) ) {
    $ua->proxy( 'http', $args{proxy} );
}
else {
    if ( !defined( $args{noproxy} ) ) {

        # Use HTTP_PROXY environment variable
        $ua->env_proxy;
    }
}
my $url = $ciMasterUrl . API_SUFFIX . '?tree=jobs[color,name]';
my $req = HTTP::Request->new( GET => $url );
if ($username && $password){
    trace("Attempting HTTP basic auth as user: $username\n");
    $req->authorization_basic($username,$password);
}
trace("GET $url ...\n");
my $res = $ua->request($req);
if ( !$res->is_success ) {
    print "UNKNOWN: Failed retrieving $url ($res->{status_line})";
    exit UNKNOWN;
}
my $json       = new JSON;
my $obj        = $json->decode( $res->content );
my $jobs       = $obj->{'jobs'};                   # ref to array
my $jobs_count = scalar(@$jobs);
trace( "Found " . $jobs_count . " jobs\n" );
my $disabled_jobs = 0;
my $unstable_jobs = 0;
my $failed_jobs   = 0;
my $passed_jobs   = 0;
my $running_jobs  = 0;

foreach my $job (@$jobs) {
    trace( 'job: ', $job->{'name'}, ' color=', $job->{'color'}, "\n" );
    $disabled_jobs++ if $job->{'color'} eq 'disabled';
    $passed_jobs++   if $job->{'color'} eq 'blue';
    $failed_jobs++   if $job->{'color'} eq 'red';
	$unstable_jobs++ if $job->{'color'} eq 'yellow';
}

my $active_jobs = $jobs_count - $disabled_jobs;
my $perfdata     = '';

if ( !defined( $args{noperfdata} ) ) {
    $perfdata = 'jobs=' . $jobs_count;
    $perfdata .= ' passed=' . $passed_jobs;
	$perfdata .= ' unstable=' . $unstable_jobs;
    $perfdata .= ' failed=' . $failed_jobs;
    $perfdata .= ' disabled=' . $disabled_jobs;
    $perfdata .= ' running=' . ( $active_jobs - $passed_jobs - $failed_jobs - $unstable_jobs );
}

if ( $failed_jobs > 0 ) {
    print "CRITICAL: ", $unstable_jobs, " jobs have a error status\n";
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit CRITICAL;
}

if ( $unstable_jobs > 0 ) {
    print "WARNING: ", $unstable_jobs, " jobs have a unstable status\n";
    if ( !defined( $args{noperfdata} ) ) {
        print( '|', $perfdata, "\n" );
    }
    exit WARNING;
}

print( 'OK: All jobs are ok' );
if ( !defined( $args{noperfdata} ) ) {
    print( '|', $perfdata, "\n" );
}
exit OK;

sub trace(@) {
    if ($debug) {
        print @_;
    }
}
__END__

=head1 NAME

check_jenkins - A Nagios plugin that count the number of jobs of a Jenkins instance (throuh HTTP request)

=head1 SYNOPSIS


check_jenkins.pl --version

check_jenkins.pl --help

check_jenkins.pl --man

check_jenkins.pl [options] <jenkins-url>

    Options:
      -d --debug               turns on debug traces
      -t --timeout=<timeout>   the timeout in seconds to wait for the
                               request (default 30)
      --proxy=<url>            the http proxy url (default from
                               HTTP_PROXY env)
      --noproxy                do not use HTTP_PROXY env
      --noperfdata             do not output perdata
      -w --warning=<count>     the maximum total jobs count for WARNING threshold
      -c --critical=<count>    the maximum total jobs count for CRITICAL threshold
      --failedwarn=<%>         the maximum ratio of failed jobs per enabled
                               jobs for WARNING threshold
      --failedcrit=<%>         the maximum ratio of failed jobs per enabled
                               jobs for CRITICAL threshold
      --username=<usename>     the username for authentication
      --password=<password>    the password for authentication
      --insecure               allow HTTPS insecure connection (self
                               signed, expired, ...)

=head1 OPTIONS

=over 8

=item B<--help>

    Print a brief help message and exits.
    
=item B<--version>

    Prints the version of this tool and exits.
    
=item B<--man>

    Prints manual and exits.

=item B<-d> B<--debug>

    Turns on debug traces

=item B<-t> B<--timeout=>timeout

    The timeout in seconds to wait for the request (default 30)
    
=item B<--proxy=>url

    The http proxy url (default from HTTP_PROXY env)

=item B<--noproxy>

    Do not use HTTP_PROXY env

=item B<--noperfdata>

    Do not output perdata

=item B<-c> B<--username=>username

    The username for authentication

=item B<-c> B<--password=>password

    The password for authentication
	
=item B<--insecure>

    Allow HTTPS insecure connection (self signed, expired, ...)
    
=back

=head1 DESCRIPTION

B<check_jenkins.pl> is a Nagios plugin that count the number of jobs of a Jenkins instance.
It can check that the total number of jobs will not exeed the WARNING and CRITICAL thresholds. It also count the number of disabled, passed, running and failed jobs and can check that the ratio of failed jobs against active jobs is over a WARNING and CRITICAL thresholds.
    
    
=cut
