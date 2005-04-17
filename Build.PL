#!/usr/bin/perl

use Module::Build;

Module::Build->new(
	module_name        => 'OpenGuides::Statistics',
	requires           => {
				'Chart::Strip'       => 0,
				'DBI'                => 0,
				'OpenGuides'         => 0.46, # first version with Config
				'OpenGuides::Config' => 0,
				'POSIX'              => 0,
				'Scalar::Util'       => 0,
		              },
	license            => 'perl'

)->create_build_script;
