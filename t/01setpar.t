#!/usr/local/bin/perl
use strict;
use Test::Assertions qw(test);

# When run with "make test", the environment should set up correctly.
use Schedule::Advisory;

# Trivial command-line options, and we don't require that
# users have Log::Trace - it's useful for me during development though

my $trace = 0;
if (@ARGV && $ARGV[0] eq '-t') {
        eval "require Log::Trace; import Log::Trace 'print';";
} elsif (@ARGV && $ARGV[0] eq '-T') {
        eval "require Log::Trace; import Log::Trace 'print' => { Deep => 1 };";
}


#######################################################################
# This test is only applicable if Set::Partition::SimilarValues exists

my $flag = 0;
eval {
	require Set::Partition::SimilarValues;
	$flag = 1;
};

if ($flag == 0) {
	print "1..1\n";
	print "ok 1 (Skipping test - Set::Partition::SimilarValues not installed\n";
	exit(0);
}

plan tests;


my $o = new Schedule::Advisory();
ASSERT($o, "object created");

$o->add('long_1', 100, { 'colour'=>'red' });
$o->add('long_2', 100, { 'colour'=>'green' });
$o->add('long_3', 100, { 'colour'=>'blue' });
$o->add('short_1', 30, { 'colour'=>'red' });
$o->add('short_2', 30, { 'colour'=>'green' });
$o->add('short_3', 30, { 'colour'=>'blue' });

$o->spread(10000);

my @rv = $o->next_job(10000);
ASSERT(EQUAL(\@rv, ['long_3',0,{ 'colour'=>'blue' }]), "next_job OK");

@rv = $o->next_job(10001);
ASSERT(EQUAL(\@rv, ['short_3',0,{ 'colour'=>'blue' }]), "next_job OK");

@rv = $o->next_job(10002);
ASSERT(EQUAL(\@rv, ['short_2',8,{ 'colour'=>'green' }]), "next_job OK");

@rv = $o->next_job(10003);
ASSERT(EQUAL(\@rv, ['short_1',17,{ 'colour'=>'red' }]), "next_job OK");

@rv = $o->next_job(10004);
ASSERT(EQUAL(\@rv, ['short_3',27,{ 'colour'=>'blue' }]), "next_job OK");

@rv = $o->next_job(10034);
ASSERT(EQUAL(\@rv, ['long_2',0,{ 'colour'=>'green' }]), "next_job OK");

@rv = $o->next_job(10035);
ASSERT(EQUAL(\@rv, ['short_2',5,{ 'colour'=>'green' }]), "next_job OK");

@rv = $o->next_job(10036);
ASSERT(EQUAL(\@rv, ['short_1',14,{ 'colour'=>'red' }]), "next_job OK");

@rv = $o->next_job(10057);
ASSERT(EQUAL(\@rv, ['short_3',4,{ 'colour'=>'blue' }]), "next_job OK");

@rv = $o->next_job(10069);
ASSERT(EQUAL(\@rv, ['long_1',0,{ 'colour'=>'red' }]), "next_job OK");


#######################################################################
# subroutines

sub TRACE {}
sub DUMP {}
