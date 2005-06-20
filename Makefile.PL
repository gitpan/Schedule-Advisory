use ExtUtils::MakeMaker;

# $Id: Makefile.PL,v 1.1 2005/06/20 16:54:13 pkent Exp $

WriteMakefile(
	AUTHOR		=> 'P Kent (pause@selsyn.co.uk)',
	ABSTRACT	=> 'An advisory job scheduler, where each job has a specific run frequency, or interval',
	NAME		=> 'Schedule::Advisory',
	DISTNAME	=> 'Schedule-Advisory',
	dist		=> {
		COMPRESS	=> 'gzip',
		SUFFIX		=> '.gz',
	},
	VERSION_FROM	=> 'lib/Schedule/Advisory.pm',
	PREREQ_PM	=> {
		Test::Assertions => 0,
	},
);
