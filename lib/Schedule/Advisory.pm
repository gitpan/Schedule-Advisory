package Schedule::Advisory;
use strict;
use Carp;
use vars qw($VERSION $FoundTimeHiRes);

$VERSION = sprintf"%d.%03d", q$Revision: 1.2 $ =~ /: (\d+)\.(\d+)/;

BEGIN {
	$FoundTimeHiRes = 0;
	eval {
		require Time::HiRes;
		import Time::HiRes 'time';
		$FoundTimeHiRes = 1;
	};
}

sub new {
	my ($class, %opt) = @_;
	
	my $self = {
		autospread => $opt{'AutoSpread'},
		jobs => {},			# hashes of job data stored against their ID
		execorder => [],	# a stack used for maintaining the ordering of certain events
	};
	return bless $self, $class;
}

sub add {
	my ($self, $id, $runperiod, $userdata) = @_;
	
	croak("You must supply an ID") unless length($id);
	croak("A job already exists with the ID '$id'") if $self->{'jobs'}{$id};
	croak("Your job must have a run period greater than 0 seconds") unless $runperiod > 0;
	croak("Your run period must just be a number") if ref($runperiod);
	
	TRACE(__PACKAGE__."::add ID '$id' Period '$runperiod'");
	$self->{'jobs'}{$id} = {
		Id => $id,
		LastRun => 0,
		NextRun => 0,
		Period => $runperiod,
		Userdata => $userdata,
	};
	push @{ $self->{'execorder'} }, $id;
	
	if ($self->{'autospread'}) {
		$self->spread;
	}
	return 1;
}

sub update_runperiod {
	my ($self, $id, $runperiod) = @_;
	
	croak("You must supply an ID") unless length($id);
	croak("There is no job with the ID '$id'") unless $self->{'jobs'}{$id};
	croak("Your job must have a run period greater than 0 seconds") unless $runperiod > 0;

	TRACE(__PACKAGE__."::update_runperiod updating job '$id', period $runperiod");

	$self->{'jobs'}{$id}{'Period'} = $runperiod;
	$self->{'jobs'}{$id}{'NextRun'} = $self->{'jobs'}{$id}{'LastRun'} + $runperiod;

	if ($self->{'autospread'}) {
		$self->spread;
	}
	return 1;
}

sub remove {
	my ($self, $id) = @_;

	croak("You must supply an ID") unless length($id);
	croak("There is no job with the ID '$id'") unless $self->{'jobs'}{$id};

	TRACE(__PACKAGE__."::remove ID '$id'");
	delete $self->{'jobs'}{$id};
	@{ $self->{'execorder'} } = grep { $_ ne $id } @{ $self->{'execorder'} };
	
	if ($self->{'autospread'}) {
		$self->spread;
	}
	return 1;
}

sub spread {
	my $self = shift;
	my $timenow = shift || time();
	
	my @jobs = sort { $a->{'Id'} cmp $b->{'Id'} } values(%{ $self->{'jobs'} });
	TRACE(__PACKAGE__."::spread finds ".@jobs." jobs overall");
	return unless @jobs > 1;

	# First, lets try to divide the set of all jobs into clusters of jobs with similar run times
	my @clusters = (\@jobs);
	eval {
		require Set::Partition::SimilarValues;
		my $parter = new Set::Partition::SimilarValues( ItemDataKey => 'Period' );
		@clusters = $parter->find_groups(@jobs);
		unless (@clusters) {
			warn "Internal error: Set::Partition::SimilarValues returned nothing - using full job list in a single cluster";
			@clusters = (\@jobs);
		}
	};
	if ($@) {
		chomp($@);	
		TRACE(__PACKAGE__."::spread problem with Set::Partition::SimilarValues: $@");
	}

	TRACE(__PACKAGE__."::spread finds ".@clusters." clusters overall");

	# For each of the clusters find the average time period...
	my $i = 0;
	foreach my $cluster (@clusters) {
		TRACE(__PACKAGE__."::spread examining cluster $i...");
		$i++;
		next unless $cluster && @$cluster;

		my @periods = map { $_->{'Period'} } sort { $a->{'Id'} cmp $b->{'Id'} } @$cluster;
		my $mean = _harmonic_mean(@periods) / @$cluster;
		TRACE(__PACKAGE__."::spread mean interval between jobs is $mean");
		# ...hence we need to space each job in the cluster by this amount
		my $offset = $mean;
		foreach my $job (@$cluster) {
			my $period = $job->{'Period'};
			# Work out the offset, or phase, at which this job will be placed
			# If the offset is greater than the period, take the modulus so it becomes smaller than the period
			# which ensures that the lastrun is always in the past, and nextrun in the future
			my $mod_offset = 0;
			if (($period > 0) && ($offset > $period)) {
				$mod_offset = ( ($offset * 100) % ($period * 100) ) / 100;
			} else {
				$mod_offset = $offset;
			}

			$job->{'LastRun'} = $timenow - $mod_offset;
			$job->{'NextRun'} = $job->{'LastRun'} + $period;

			TRACE(__PACKAGE__."::spread updated job '$job->{'Id'}': last run $job->{'LastRun'}, next run $job->{'NextRun'}, mod. offset $mod_offset");
			$offset += $mean;
		}
	}
	TRACE(__PACKAGE__."::spread done");
	return 1;
}

sub next_job {
	my $self = shift;
	my $timenow = shift || time();
	
	my ($chosen_id, $delay) = $self->_next_job($timenow);
	
	# If the caller is calling us in a very tight loop - they may not be sleeping or
	# the "job" is a No-Op, etc. - we should give them the next job but
	# not update the state, otherwise the NextRun time can walk off into the future.
	# To do this we determine if the NextRun is >= 1 periods in the future
	if (
		($self->{'jobs'}{$chosen_id}{'NextRun'} - $timenow) >= ($self->{'jobs'}{$chosen_id}{'Period'})
	) {
		TRACE(__PACKAGE__."::next_job NOT updating info for '$chosen_id'");
	} else {
		TRACE(__PACKAGE__."::next_job updating info for '$chosen_id'");
		$self->{'jobs'}{$chosen_id}{'LastRun'} = $delay + $timenow;
		$self->{'jobs'}{$chosen_id}{'NextRun'} = $delay + $timenow + $self->{'jobs'}{$chosen_id}{'Period'};
	}

	# Maintain the execution order list by placing the chosen ID at the end
	@{ $self->{'execorder'} } = grep { $_ ne $chosen_id } @{ $self->{'execorder'} };
	push @{ $self->{'execorder'} }, $chosen_id;

	return ($chosen_id, $delay, $self->{'jobs'}{$chosen_id}{'Userdata'});
}

sub all_jobs {
	my $self = shift;
	my @rv;

	foreach my $id (@{ $self->{'execorder'} }) {
		push @rv, $id;
	}
	TRACE(__PACKAGE__."::all_jobs returning info for: ".join(', ', @rv));

	return @rv;
}

sub get_job_data {
	my ($self, $id) = @_;

	croak("You must supply an ID") unless length($id);
	croak("There is no job with the ID '$id'") unless $self->{'jobs'}{$id};

	TRACE(__PACKAGE__."::get_job_data for '$id'");
	return @{ $self->{'jobs'}{$id} }{'LastRun', 'NextRun', 'Period'};
}

sub get_userdata {
	my ($self, $id) = @_;

	croak("You must supply an ID") unless length($id);
	croak("There is no job with the ID '$id'") unless $self->{'jobs'}{$id};

	TRACE(__PACKAGE__."::get_userdata for '$id'");
	return $self->{'jobs'}{$id}{'Userdata'};
}

sub update_userdata {
	my ($self, $id, $userdata) = @_;

	croak("You must supply an ID") unless length($id);
	croak("There is no job with the ID '$id'") unless $self->{'jobs'}{$id};

	TRACE(__PACKAGE__."::update_userdata for '$id'");
	$self->{'jobs'}{$id}{'Userdata'} = $userdata;
	return 1;
}

sub delete_userdata {
	my ($self, $id) = @_;

	croak("You must supply an ID") unless length($id);
	croak("There is no job with the ID '$id'") unless $self->{'jobs'}{$id};

	TRACE(__PACKAGE__."::delete_userdata for '$id'");
	$self->{'jobs'}{$id}{'Userdata'} = undef;
	return 1;
}

#######################################################################
# Private routines

# this routine picks the next job without altering the state of the object
sub _next_job {
	my $self = shift;
	my $timenow = shift;
	TRACE(__PACKAGE__."::_next_job called - reference time $timenow");
	
	# First order the jobs by their next scheduled runtime
	my @jobs = sort { $a->{'NextRun'} <=> $b->{'NextRun'} } values(%{ $self->{'jobs'} });
	TRACE(__PACKAGE__."::_next_job found ".@jobs." jobs");
	
	croak("There are no jobs defined! Please add jobs before calling this method") unless @jobs;
	
	# See if there are any ties
	my $earliest_time = $jobs[0]{'NextRun'};
	my @tied_jobs = grep { $_->{'NextRun'} == $earliest_time } @jobs;
	my $chosen_id;
	TRACE(__PACKAGE__."::_next_job found ".@tied_jobs." jobs with a NextRun of $earliest_time");

	if (@tied_jobs == 0) {
		warn("Internal error, consider this a bug: found no jobs when we should have found at least 1 - not trying to resolve ties");
		@tied_jobs = ( $jobs[0] );
		$chosen_id = $tied_jobs[0]{'Id'}
	} elsif (@tied_jobs == 1) {
		# No ties, so we just use the single job
		$chosen_id = $tied_jobs[0]{'Id'}
	} else {
		# There are ties, so we need to resolve them using the execution order list
		# We consider that items near the front of that array are oldest,
		# so they frontmost item gets done. Read the execution list until we find one
		# of these tied jobs
		
		my %tied_ids = map { $_->{'Id'} => 1 } @tied_jobs;
		foreach my $exec_id (@{ $self->{'execorder'} }) {
			if ($tied_ids{$exec_id}) {
				TRACE(__PACKAGE__."::_next_job broke the tie by finding '$exec_id' first");
				$chosen_id = $exec_id;
				last;
			}
		}
	}
	unless (length($chosen_id)) {
		croak("Unable to choose a job! Consider this a bug");
	}
	
	# When is this job supposed to run? If it should run in the future, return the amount of time to wait
	my $delay = 0;
	if ($self->{'jobs'}{$chosen_id}{'NextRun'} > $timenow) {
		$delay = $self->{'jobs'}{$chosen_id}{'NextRun'} - $timenow;
	}
	TRACE(__PACKAGE__."::_next_job chose '$chosen_id' - delay until next execution $delay");

	return ($chosen_id, $delay);
}

# We use the harmonic mean because it seems to perform "better" when most of the value are the same,
# i.e. the mean value is not too far from the mode. No single figure will fit all cases but this
# seems as good an average as any.
sub _harmonic_mean {
	my $sum_inverse = 0;
	return 0 unless @_;
	my $n = 0;
	foreach (@_) {
		next unless $_ > 0;
		$sum_inverse += 1/$_;
		$n++;
	}

	if ($sum_inverse > 0) {
		return $n/$sum_inverse;
	} else {
		return 0;
	}
}

# Stubs for debugging
sub TRACE {}
sub DUMP {}

1;

=head1 NAME

Schedule::Advisory - An advisory job scheduler, where each job has a specific run frequency, or interval

=head1 DESCRIPTION

This module implements a scheduler for a set of jobs, where each job has a given run frequency or period - i.e. it should
run once every so-many seconds. This module can determine which job should run next, and tells the caller which job it
has chosen and how long (if at all) the caller needs to wait before starting the job. Note that this module does B<not>
C<sleep()> for you, or invoke the job itself - those tasks are left to the caller, because the caller knows how it
should best invoke a job (e.g. dispatch table, conditional branch, fork a worker process, ...), and if
there are other delays to be accounted for before starting the job. This is why it's an "advisory" scheduler - it
doesn't enforce a schedule itself.

See L</ALGORITHM> for a description of how the scheduler chooses jobs.

You may add and remove jobs at any time. Each job has a unique ID string which is used to refer to the job.
You may alter the run frequency at any time. You can also retrieve a list of all job IDs in the object, and timing
information for each.

The module also has a facility for spreading jobs out so that they don't all get scheduled at once,
which is especially relevant if you have many jobs with the same period. The module L<Set::Partition::SimilarValues>
is used, if available, to help this facility generally work better.

You may optionally store some "userdata" against each job. This userdata may be
any single value (a string, number, hash reference, array reference, etc.) and can hold any data associated with the
job. You may wish to use this facility if the caller doesn't have access to data required to complete the job.
Userdata can be fetched, updated, or deleted at any time.

=head2 High Resolution Time

Although it's not required by this module, it's recommended that you install L<Time::HiRes> on your system.
It provides sleep() and time() functions which have higher resolution and hence provide better accuracy for
scheduling, although that's especially relevant when the interval between jobs is of the order of seconds instead of hours.

The package global B<$Schedule::Advisory::FoundTimeHiRes> is set to 1 if Time::HiRes was loaded, 0 otherwise.

=head1 SYNOPSIS

	use Schedule::Advisory;
		# you may also wish to use Time::HiRes; for a high-resolution sleep()
	my $sched = new Schedule::Advisory();
	$sched->add('foo', 300, { 'colour' => 'red' });
	$sched->add('bar', 320, 'some userdata');
	$sched->add('qux', 3600);
	$sched->remove('qux');
	$sched->update_runperiod('bar', 300);
	$sched->spread;
	
	my @list_of_ids = $sched->all_jobs;
	my ($lastrun, $nextrun, $period) = $sched->get_job_data('foo');
	my $rv = $sched->get_userdata('foo');
	$sched->update_userdata('foo', { 'colour' => 'blue' });
	$sched->delete_userdata('bar');
	
	while ($some_condition) {
		my ($job_id, $delay, $userdata) = $sched->next_job;
		if ($delay) { sleep($delay); }
		do_something_to_invoke_job( $job_id, $userdata );
	}

=head1 METHODS

=over 4

=item new( %options )

Class method. Creates a new object and returns it. See L</CONSTRUCTOR OPTIONS> for
options which may be supplied.

=item add( $job_id, $run_period, I<[> $userdata I<]> )

Adds a new job to the object. The Job ID may be any string, and must be different
from any job ID currently in use in the object. The run period is the desired time
interval, in seconds, between successive runs of the job. It must be a positive number.
E.g. 60 means that the job should run once a minute.

The userdata is optional, and may be any single value (e.g. a 
number, a string, a hash reference or array reference).

=item update_runperiod( $job_id, $run_period )

This method allows you to change the run period of a given job. Internally, the
job is updated so that the time of the next scheduled occurrence is simply
the time it was last run plus the new run period.
The job must already exist.

=item remove( $job_id )

Removes the given job from the object. The job must already exist.

=item spread( I<[> $time I<]> )

Attempts to spread the jobs through time so that they are not all scheduled to occur at
the same time. The module L<Set::Partition::SimilarValues> is loaded if available to
divide the set of jobs into clusters of jobs with similar run times for better spread.
If the module isn't available then all jobs are considered together in a single cluster.
The method uses the current time as the basis for its calculations B<unless> you explicitly pass in a different time.

B<Note> this method updates the internal timing information which can re-order the jobs,
so you may wish to call this method only infrequently. See also the AutoSpread constructor option.

=item next_job( I<[> $time I<]> )

Determines which job should run next.

Returns the following data in a list: the chosen job ID, the time to wait until
the next execution, and the job's userdata (if any). There must be at least one
job already in the object. The method uses the current time as the basis for its
calculations B<unless> you explicitly pass in a different time. The time is simply
the number of seconds since the epoch. You may wish to pass in the time if you're
trying to schedule a number of jobs in advance.

The time to wait is 0 if the job should have already been started (i.e. its next
occurrence was before the reference time), or a positive number of seconds if there
is time to wait before starting the job. B<Note>: as mentioned above (L</DESCRIPTION>)
this module doesn't sleep so you are expected to act on the recommended delay.

=item all_jobs()

Returns a list of all job IDs in the object.

=item get_job_data( $job_id )

Returns a list of the following information: last run time, next run time, run period.
The job must already exist.

=item get_userdata( $job_id )

Returns the userdata, if any, for the given job ID. The job must already exist.

=item update_userdata( $job_id, $userdata )

Update the userdata for the given job with the supplied value (the value
may even be undef). The job must already exist.

=item delete_userdata( $job_id )

Delete the userdata for the given job. The job must already exist.

=back

=head1 CONSTRUCTOR OPTIONS

=over 4

=item AutoSpread

If set to 1 then C<spread()> will be called automatically after C<add()>, C<remove()> and C<update_runperiod()>
so that jobs stay spread out in time.

=back

=head1 ALGORITHM

When a job is added it is given a "last run time" of 0. When C<next_job()> is called this module
orders all jobs by their next scheduled time. The job with the earliest time is chosen - i.e. the most overdue job
or the next scheduled job. If there is a tie then the job that was least recently chosen, or
least recently added to the object using the C<add()> method, is chosen this time.

If the job is due to occur in the future then the routine works out the delay required from the current time
(or if you passed in an explicit time, it uses that), otherwise a delay of zero is returned.

=head1 SEE ALSO

L<Time::HiRes>, L<Set::Partition::SimilarValues>

=head1 COPYRIGHT

Copyright 2005 P Kent

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

$Revision: 1.2 $

=cut
