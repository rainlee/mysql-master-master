package MMM::Common::Config;

use strict;
use warnings FATAL => 'all';
use English qw( NR );
use Log::Log4perl qw(:easy);

use List::Util qw(first);

our $VERSION = '0.01';

our $RULESET = {
	'this'					=> { 'required' => ['AGENT'], 'refvalues' => 'host' },
	'debug'					=> { 'default' => 0, 'values' => ['true', 'false', 'yes', 'no', 1, 0, 'on', 'off'] },
	'active_master_role'	=> { 'required' => ['AGENT', 'MONITOR'], 'refvalues' => 'role' },
	'role'					=> { 'required' => ['AGENT', 'CONTROL', 'MONITOR'], 'multiple' => 1, 'section' => {
		'mode'					=> { 'required' => ['MONITOR'], 'values' => ['balanced', 'exclusive'] },
		'hosts'					=> { 'required' => ['MONITOR'], 'refvalues' => 'host', 'multiple' => 1 },
		'ips'					=> { 'required' => ['AGENT', 'MONITOR'], 'multiple' => 1 }
		}
	},
	'monitor'				=> { 'required' => ['MONITOR', 'CONTROL'], 'section' => {
		'ip'					=> { 'required' => ['MONITOR', 'CONTROL'] },
		'port'					=> { 'default' => '9988' },
		'pid_path'				=> { 'required' => ['MONITOR'] },
		'bin_path'				=> { 'required' => ['MONITOR'] },
		'status_path'			=> { 'required' => ['MONITOR'] },
		'ping_interval'			=> { 'default' => 1 },
		'ping_ips'				=> { 'required' => ['MONITOR'], 'multiple' => 1 }
		}
	},
	'socket'				=> { 'section' => {
		'type'					=> { 'required' => 1, 'values' => [ 'plain', 'ssl' ] },
		'cert_file'				=> { 'deprequired' => { 'type' => 'ssl' }, 'required' => [ 'AGENT', 'CONTROL', 'MONITOR'] },
		'key_file'				=> { 'deprequired' => { 'type' => 'ssl' }, 'required' => [ 'AGENT', 'CONTROL', 'MONITOR'] },
		'ca_file'				=> { 'deprequired' => { 'type' => 'ssl' }, 'required' => [ 'AGENT', 'MONITOR'] }
		}
	},
	'host'					=> { 'required' => 1, 'multiple' => 1, 'template' => 'default', 'section' => {
		'ip'					=> { 'required' => 1 },
		'mode'					=> { 'required' => ['AGENT', 'CONTROL', 'MONITOR'], 'values' => ['master', 'slave'] },
		'peer'					=> { 'deprequired' => { 'mode' => 'master' }, 'refvalues' => 'host' },
		'pid_path'				=> { 'required' => ['AGENT'] },
		'bin_path'				=> { 'required' => ['AGENT'] },
		'agent_port'			=> { 'default' => 9989 },
		'cluster_interface'		=> { 'required' => ['AGENT'] },
		'mysql_port'			=> { 'default' => 3306 },
		'lvm_user'				=> { 'required' => ['LVMTOOLS'] },
		'lvm_password'			=> { 'required' => ['LVMTOOLS'] },
		'agent_user'			=> { 'required' => ['AGENT'] },
		'agent_password'		=> { 'required' => ['AGENT'] },
		'monitor_user'			=> { 'required' => ['MONITOR'] },
		'monitor_password'		=> { 'required' => ['MONITOR'] },
		'replication_user'		=> { 'required' => ['AGENT', 'LVMTOOLS'] },
		'replication_password'	=> { 'required' => ['AGENT', 'LVMTOOLS'] }
		}
	},
	'check'					=> { 'create_if_empty' => ['MONITOR'], 'multiple' => 1, 'template' => 'default', 'values' => ['ping', 'mysql', 'rep_backlog', 'rep_threads'], 'section' => {
		'check_period'			=> { 'default' => 5 },
		'trap_period'			=> { 'default' => 10 },
		'timeout'				=> { 'default' => 2 },
		'restart_after'			=> { 'default' => 10000 },
		'max_backlog'			=> { 'default' => 60 }		# XXX ugly
		}
	}
};

#-------------------------------------------------------------------------------
sub new($) {
	my $self = shift;

	return bless { }, $self; 
}

#-------------------------------------------------------------------------------
sub read($$) {
	my $self = shift;
	my $file = shift;
	my $fullname = $self->_get_filename($file);
	LOGDIE "Could not find config file" unless $fullname;
	DEBUG "Loading configuration from $fullname";
	my $fd;
	open($fd, "<$fullname") || LOGDIE "Can't read config file '$fullname'";
	my $ret = $self->parse($RULESET, $fullname, $fd);
	close($fd);
	return $ret;
}

#-------------------------------------------------------------------------------
sub parse(\%\%$*); # needed because parse is a recursive function
sub parse(\%\%$*) {
	my $config	= shift;
	my $ruleset = shift;
	my $file	= shift;	# name of file
	my $fd		= shift;
	my $line;
	
	while ($line = <$fd>) {
		chomp($line);

		# comments and empty lines handling
		next if ($line =~ /^\s*#/ || $line =~ /^\s*$/);

		# end tag
		return if ($line =~ /^\s*<\/\s*(\w+)\s*>\s*$/);

		if ($line =~ /^\s*include\s+(\S+)\s*$/) {
			my $include_file = $1;
			$config->read($include_file);
			next;
		}

		# start tag - unique section
		if ($line =~/^\s*<\s*(\w+)\s*>\s*$/) {
			my $type = $1;
			if (!defined($ruleset->{$type}) || !defined($ruleset->{$type}->{section})) {
				LOGDIE "Invalid section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			if ($ruleset->{$type}->{multiple}) {
				LOGDIE "No section name specified for named section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			$config->{$type} = {} unless $config->{$type};
			parse(%{$config->{$type}}, %{$ruleset->{$type}->{section}}, $file, $fd);
			next;
		}
		# empty tag - unique section
		if ($line =~/^\s*<\s*(\w+)\s*\/>\s*$/) {
			my $type = $1;
			if (!defined($ruleset->{$type}) || !defined($ruleset->{$type}->{section})) {
				LOGDIE "Invalid section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			if ($ruleset->{$type}->{multiple}) {
				LOGDIE "No section name specified for named section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			$config->{$type} = {}			unless $config->{$type};
			next;
		}
		# start tag - named section
		if ($line =~/^\s*<\s*(\w+)\s+(\w+)\s*>\s*$/) {
			my $type = $1;
			my $name = $2;
			if (!defined($ruleset->{$type}) || !defined($ruleset->{$type}->{section})) {
				LOGDIE "Invalid section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			if (!$ruleset->{$type}->{multiple}) {
				LOGDIE "Section name specified for unique section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			$config->{$type} = {}			unless $config->{$type};
			$config->{$type}->{$name} = {}	unless $config->{$type}->{$name};
			parse(%{$config->{$type}->{$name}}, %{$ruleset->{$type}->{section}}, $file, $fd);
			next;
		}

		# empty tag - named section
		if ($line =~/^\s*<\s*(\w+)\s+(\w+)\s*\/>\s*$/) {
			my $type = $1;
			my $name = $2;
			if (!defined($ruleset->{$type}) || !defined($ruleset->{$type}->{section})) {
				LOGDIE "Invalid section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			if (!$ruleset->{$type}->{multiple}) {
				LOGDIE "Section name specified for unique section $type in '$file' on line $INPUT_LINE_NUMBER!";
			}
			$config->{$type} = {}			unless $config->{$type};
			$config->{$type}->{$name} = {}	unless $config->{$type}->{$name};
			next;
		}
		
		if ($line =~/^\s*(\S+)\s+(.*)$/) {
			my $var = $1;
			my $val = $2;
			LOGDIE "Unknown variable $var in '$file' on line $INPUT_LINE_NUMBER!" unless defined($ruleset->{$var});
			LOGDIE "'$var' should be a section instead of a variable in '$file' on line $INPUT_LINE_NUMBER!" if defined($ruleset->{$var}->{section});
			@{$config->{$var}} = split(/\s*,\s*/, $val) if ($ruleset->{$var}->{multiple});
			$config->{$var} = $val unless ($ruleset->{$var}->{multiple});
			next;
		}

		LOGDIE "Invalid config line in file '$file' on line $INPUT_LINE_NUMBER!";
	}
}

#-------------------------------------------------------------------------------
sub _get_filename($$) {
	my $self = shift;
	my $file = shift;

	$file .= '.conf' unless ($file =~ /\.conf$/);
	my @paths = qw(/etc /etc/mmm /etc/mysql-mmm);

	my $fullname;
	foreach my $path (@paths) {
		if (-r "$path/$file") {
			$fullname = "$path/$file";
			last;
		}
	}
	FATAL "No config file $file in ", join(', ', @paths) unless $fullname;
	return $fullname;
}

#-------------------------------------------------------------------------------
sub check($$) {
	my $self = shift;
	my $program = shift;
	$self->_check_ruleset('', $program, $RULESET, $self);
}

#-------------------------------------------------------------------------------
sub _check_ruleset(\%$$\%\%) {
	my $self	= shift;
	my $posstr	= shift;
	my $program	= shift;
	my $ruleset	= shift;
	my $config	= shift;

	foreach my $varname (keys(%{$ruleset})) {
		$self->_check_rule($posstr . $varname, $program, $ruleset, $config, $varname);
	}
}

#-------------------------------------------------------------------------------
sub _check_rule(\%$$\%\%$) {
	my $self	= shift;
	my $posstr	= shift;
	my $program	= shift;
	my $ruleset	= shift;
	my $config	= shift;
	my $varname	= shift;

	my $cur_rule = \%{$ruleset->{$varname}};

	# set default value if not defined
	if (!defined($config->{$varname}) && defined($cur_rule->{default})) {
		DEBUG "Undefined value for '$posstr', using default value '$cur_rule->{default}'";
		$config->{$varname} = $cur_rule->{default};
	}

	# check required
	if (defined($cur_rule->{required}) && defined($cur_rule->{deprequired})) {
		LOGDIE "Default value specified for required config entry '$posstr'" if defined($cur_rule->{default});
		LOGDIE "Invalid ruleset '$posstr' - deprequired should be a hash" if (ref($cur_rule->{deprequired}) ne "HASH");
		$cur_rule->{required} = _eval_program_condition($program, $cur_rule->{required}) if (ref($cur_rule->{required}) eq "ARRAY");
		my ($var, $val) = %{ $cur_rule->{deprequired} };
		# TODO WARN if field $var has a default value - this may not be evaluated yet.
		if (!defined($config->{$varname}) && $cur_rule->{required} == 1 && defined($config->{$var}) && $config->{$var} eq $val) {
			# TODO better error message for missing sections
			FATAL "Config entry '$posstr' is required because of '$var $val', but missing";
		}
	}
	elsif (defined($cur_rule->{required})) {
		LOGDIE "Default value specified for required config entry '$posstr'" if defined($cur_rule->{default});
		$cur_rule->{required} = _eval_program_condition($program, $cur_rule->{required}) if (ref($cur_rule->{required}) eq "ARRAY");
		if (!defined($config->{$varname}) && $cur_rule->{required} == 1) {
			# TODO better error message for sections
			LOGDIE "Required config entry '$posstr' is missing";
			return;
		}
	}
	elsif (defined($cur_rule->{deprequired})) {
		LOGDIE "Default value specified for required config entry '$posstr'" if defined($cur_rule->{default});
		LOGDIE "Invalid ruleset '$posstr' - deprequired should be a hash" if (ref($cur_rule->{deprequired}) ne "HASH");
		my ($var, $val) = %{ $cur_rule->{deprequired} };
		# TODO WARN if field $var has a default value - this may not be evaluated yet.
		if (!defined($config->{$varname}) && defined($config->{$var}) && $config->{$var} eq $val) {
			# TODO better error message for missing sections
			LOGDIE "Config entry '$posstr' is required because of '$var $val', but missing";
			return;
		}
	}

	return if (!defined($config->{$varname}) && !$cur_rule->{multiple});

	# handle sections
	if (defined($cur_rule->{section})) {

		# unique secions
		unless ($cur_rule->{multiple}) {
			# check variables of unique sections
			$self->_check_ruleset($posstr . '->', $program, $cur_rule->{section}, $config->{$varname});
			return;
		}

		# named sections ...

		# check if section name is one of the allowed
		if (defined($cur_rule->{values})) {
			my @allowed = @{$cur_rule->{values}};
			push @allowed, $cur_rule->{template} if defined($cur_rule->{template});
			foreach my $key (keys %{ $config->{$varname} }) {
				unless (defined(first { $_ eq $key; } @allowed)) {
					LOGDIE "Invalid $posstr '$key' in configuration allowed values are: '", join("', '", @allowed), "'"
				}
			}
		}

		# handle "create if empty"
		if (defined($cur_rule->{create_if_empty})) {
			$cur_rule->{create_if_empty} = _eval_program_condition($program, $cur_rule->{create_if_empty}) if (ref($cur_rule->{create_if_empty}) eq "ARRAY");
			if ($cur_rule->{create_if_empty} == 1) {
				$config->{$varname} = {} unless defined($config->{$varname});
				foreach my $value (@{$cur_rule->{values}}) {
					next if (defined($config->{$varname}->{$value}));
					$config->{$varname}->{$value} = {};
				}
			}
		}

		# handle section template
		if (defined($cur_rule->{template}) && defined($config->{$varname}->{ $cur_rule->{template} })) {
			my $template = $config->{$varname}->{ $cur_rule->{template} };	
			delete($config->{$varname}->{ $cur_rule->{template} });
			foreach my $var ( keys( %{ $template } ) ) {
				foreach my $key ( keys( %{ $config->{$varname} } ) ) {
					if (!defined($config->{$varname}->{$key}->{$var})) {
						$config->{$varname}->{$key}->{$var} = $template->{$var};
					}
				}
			}
		}

		# check variables of each named section
		foreach my $key ( keys( %{ $config->{$varname} } ) ) {
			$self->_check_ruleset($posstr . '->' . $key . '->', $program, $cur_rule->{section}, $config->{$varname}->{$key});
		}
		return;
	}

	# skip if undefined
	return if (!defined($config->{$varname}));
	
	# check if variable has one of the allowed values
	if (defined($cur_rule->{values}) || defined($cur_rule->{refvalues})) {
		my @allowed;
		if (defined($cur_rule->{values})) {
			@allowed = @{$cur_rule->{values}};
		}
		elsif (defined($cur_rule->{refvalues})) {
			if (defined($ruleset->{ $cur_rule->{refvalues} })) {
				return unless (ref($config->{ $cur_rule->{refvalues} }) eq "HASH");
				LOGDIE "Could not find any $cur_rule->{refvalues}-sections" unless (ref($config->{ $cur_rule->{refvalues} }) eq "HASH");
				# reference to section on current level
				@allowed = keys( %{ $config->{ $cur_rule->{refvalues} } } );
				# remove template section from list of valid values
				if (defined($ruleset->{ $cur_rule->{refvalues} }->{template})) {
					@allowed = grep { $_ ne $ruleset->{ $cur_rule->{refvalues} }->{template}} @allowed;
				}
			}
			elsif (defined($RULESET->{ $cur_rule->{refvalues} })) {
				return unless (ref($self->{ $cur_rule->{refvalues} }) eq "HASH");
				LOGDIE "Could not find any $cur_rule->{refvalues}-sections" unless (ref($self->{ $cur_rule->{refvalues} }) eq "HASH");
				# reference to section on current level
				@allowed = keys( %{ $self->{ $cur_rule->{refvalues} } } );
				# remove template section from list of valid values
				if (defined($RULESET->{ $cur_rule->{refvalues} }->{template})) {
					@allowed = grep { $_ ne $RULESET->{ $cur_rule->{refvalues} }->{template}} @allowed;
				}
			}
			else {
				LOGDIE "Invalid reference to non-section '$cur_rule->{refvalues}' for '$posstr'";
				return;
			}
		}
		if ($cur_rule->{multiple}) {
			for my $val ( @{ $config->{$varname} } ) {
				unless (defined(first { $_ eq $val; } @allowed)) {
					LOGDIE "Config entry '$posstr' has invalid value '$val' allowed values are: '", join("', '", @allowed), "'";
					return;
				}
			}
			return;
		}
		unless (defined(first { $_ eq $config->{$varname}; } @allowed)) {
			LOGDIE "Config entry '$posstr' has invalid value '$config->{$varname}' allowed values are: '", join("', '", @allowed), "'";
			return;
		}
	}
}

#-------------------------------------------------------------------------------
sub _eval_program_condition($$) {
	my $program = shift;
	my $value = shift;
	
	return 1 unless ($program);
	return 1 if (first { $_ eq $program; } @{ $value });
	return -1;
}

1;
