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

plan tests;


#######################################################################
ASSERT($Schedule::Advisory::VERSION, "Loaded version $Schedule::Advisory::VERSION");
ASSERT(1, "Flag for Time::HiRes says $Schedule::Advisory::FoundTimeHiRes");


my $rv = Schedule::Advisory::_harmonic_mean();
ASSERT($rv==0, "mean OK with no args");

$rv = Schedule::Advisory::_harmonic_mean(0);
ASSERT($rv==0, "mean OK with 1 arg (a zero)");

$rv = Schedule::Advisory::_harmonic_mean(10);
ASSERT($rv==10, "mean OK with 1 arg");

$rv = Schedule::Advisory::_harmonic_mean(3,3,3);
ASSERT($rv==3, "mean OK with 3 args - got $rv");

$rv = Schedule::Advisory::_harmonic_mean(0.5,1,1);
ASSERT($rv==0.75, "mean OK with 3 args - got $rv");

$rv = Schedule::Advisory::_harmonic_mean(1,2,0,4,4);
ASSERT($rv==2, "mean OK with 5 args (one zero) - got $rv");

$rv = Schedule::Advisory::_harmonic_mean(1,2,4,4);
ASSERT($rv==2, "mean OK with 4 args - got $rv");



my $o = new Schedule::Advisory();
ASSERT($o, "object created");

### add
eval { $o->add(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->add('foo'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->add('foo', -100); };
chomp($@);
ASSERT($@, "Error trapped: $@");

my @rv = $o->all_jobs;
ASSERT(EQUAL(\@rv, []), "all_jobs OK");

$rv = $o->add('foo', 42);
ASSERT($rv, "add OK");

eval { $o->add('foo', 200); };
chomp($@);
ASSERT($@, "Error trapped: $@");

@rv = $o->get_job_data('foo');
ASSERT(EQUAL(\@rv, [0, 0, 42]), "job data OK");


### add, then remove
$rv = $o->add('temporary', 123);
ASSERT($rv, "add OK");

@rv = $o->all_jobs;
ASSERT(EQUAL(\@rv, ['foo', 'temporary']), "all_jobs OK");

eval { $o->remove(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->remove('no_such_job'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

$rv = $o->remove('temporary');
ASSERT($rv, "remove OK");

@rv = $o->all_jobs;
ASSERT(EQUAL(\@rv, ['foo']), "all_jobs OK after remove");


eval { $o->add('bar', { 'colour'=>'red' }); };
chomp($@);
ASSERT($@, "Error trapped: $@");

$o->add('bar', 100, { 'colour'=>'red' });

@rv = $o->all_jobs;
ASSERT(EQUAL(\@rv, ['foo', 'bar']), "all_jobs OK after add");


### update_runperiod
eval { $o->update_runperiod(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->update_runperiod('bibble'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->update_runperiod('foo'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->update_runperiod('foo', -20); };
chomp($@);
ASSERT($@, "Error trapped: $@");

$rv = $o->update_runperiod('foo', 100);
ASSERT($rv, "update_runperiod OK");


### job data
eval { $o->get_job_data(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->get_job_data('no_data_for_me'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

@rv = $o->get_job_data('foo');
ASSERT(EQUAL(\@rv, [0, 100, 100]), "job data OK");


### userdata
eval { $o->get_userdata(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->get_userdata('no_userdata_for_me'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

$rv = $o->get_userdata('foo');
ASSERT(!$rv, "no userdata for foo");

$rv = $o->get_userdata('bar');
ASSERT(EQUAL($rv, { 'colour'=>'red' }), "userdata OK");


eval { $o->update_userdata(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->update_userdata('still_no_userdata'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

$rv = $o->update_userdata('foo', [ 'some', 'data' ]);
ASSERT($rv, "update_userdata OK");


$rv = $o->get_userdata('foo');
ASSERT(EQUAL($rv, [ 'some', 'data' ]), "userdata OK after update_userdata");


eval { $o->delete_userdata(); };
chomp($@);
ASSERT($@, "Error trapped: $@");

eval { $o->delete_userdata('delete_no_userdata'); };
chomp($@);
ASSERT($@, "Error trapped: $@");

$rv = $o->delete_userdata('foo');
ASSERT($rv, "delete_userdata OK");


### spreading
$rv = $o->spread;
ASSERT($rv, "spread OK");

@rv = $o->get_job_data('foo');
my $rv1 = $rv[1];

@rv = $o->get_job_data('bar');
my $rv2 = $rv[1];

ASSERT(($rv2-$rv1==50), "spread OK ($rv1 and $rv2)");


$rv = $o->spread(2112);
ASSERT($rv, "spread OK with explicit time");

@rv = $o->get_job_data('foo');
ASSERT(EQUAL(\@rv, [2012, 2112, 100]), "spread OK for foo");

@rv = $o->get_job_data('bar');
ASSERT(EQUAL(\@rv, [2062, 2162, 100]), "spread OK for bar");


### scheduling
$o->add('baz', 100);
$o->add('qux', 100);
$rv = $o->spread(1000);

@rv = $o->next_job;
ASSERT(EQUAL(\@rv, ['qux',0,undef]), "next_job OK");

@rv = $o->next_job;
ASSERT(EQUAL(\@rv, ['foo',0,undef]), "next_job OK");

@rv = $o->next_job;
ASSERT(EQUAL(\@rv, ['baz',0,undef]), "next_job OK");

@rv = $o->next_job;
ASSERT(EQUAL(\@rv, ['bar',0,{colour => 'red'}]), "next_job OK");

@rv = $o->next_job;
ASSERT($rv[0] eq 'qux', "next_job OK");
ASSERT($rv[1] > 50, "next_job OK");
ASSERT(! $rv[2], "next_job OK");


# with specific times
$rv = $o->spread(1000);

@rv = $o->next_job(1000);
ASSERT(EQUAL(\@rv, ['qux',0,undef]), "next_job OK - specific time");

@rv = $o->next_job(1001);
ASSERT(EQUAL(\@rv, ['foo',24,undef]), "next_job OK - specific time");

@rv = $o->next_job(1002);
ASSERT(EQUAL(\@rv, ['baz',48,undef]), "next_job OK - specific time");

@rv = $o->next_job(1003);
ASSERT(EQUAL(\@rv, ['bar',72,{colour => 'red'}]), "next_job OK - specific time");

@rv = $o->next_job(1004);
ASSERT(EQUAL(\@rv, ['qux',96,undef]), "next_job OK - specific time");

@rv = $o->next_job(1005);
ASSERT(EQUAL(\@rv, ['foo',120,undef]), "next_job OK - specific time");

@rv = $o->next_job(1006);
ASSERT(EQUAL(\@rv, ['foo',119,undef]), "next_job OK - specific time");

@rv = $o->next_job(1017);
ASSERT(EQUAL(\@rv, ['foo',108,undef]), "next_job OK - specific time");

@rv = $o->next_job(1025);
ASSERT(EQUAL(\@rv, ['foo',100,undef]), "next_job OK - specific time");

@rv = $o->next_job(1049);
ASSERT(EQUAL(\@rv, ['foo',76,undef]), "next_job OK - specific time");

@rv = $o->next_job(1050);
ASSERT(EQUAL(\@rv, ['baz',100,undef]), "next_job OK - specific time");


@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['baz',0,undef]), "next_job OK - specific time (very overdue)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['bar',0,{colour => 'red'}]), "next_job OK - specific time (very overdue)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['qux',0,undef]), "next_job OK - specific time (very overdue)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['foo',0,undef]), "next_job OK - specific time (very overdue)");


@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['baz',100,undef]), "next_job OK - specific time (very overdue, tight loop)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['bar',100,{colour => 'red'}]), "next_job OK - specific time (very overdue, tight loop)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['qux',100,undef]), "next_job OK - specific time (very overdue, tight loop)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['foo',100,undef]), "next_job OK - specific time (very overdue, tight loop)");


@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['baz',100,undef]), "next_job OK - specific time (very overdue, tight loop)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['bar',100,{colour => 'red'}]), "next_job OK - specific time (very overdue, tight loop)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['qux',100,undef]), "next_job OK - specific time (very overdue, tight loop)");

@rv = $o->next_job(3000);
ASSERT(EQUAL(\@rv, ['foo',100,undef]), "next_job OK - specific time (very overdue, tight loop)");



#######################################################################
# subroutines

sub TRACE {}
sub DUMP {}
