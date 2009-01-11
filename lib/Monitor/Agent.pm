package MMM::Monitor::Agent;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use MMM::Common::Socket;
use MMM::Monitor::ChecksStatus;

our $VERSION = '0.01';

use Class::Struct;
no warnings qw(Class::Struct);


struct 'MMM::Monitor::Agent' => {
	host		=> '$',
	mode		=> '$',
	ip			=> '$',
	port		=> '$',

	state		=> '$',
	roles		=> '@',
	uptime		=> '$',
	last_uptime	=> '$',

	flapping	=> '$',
	flapstart	=> '$',
	flapcount	=> '$'
};

sub state {
	my $self = shift;
	if (@_) {
		my $new_state = shift;
		my $old_state = $self->{'MMM::Monitor::Agent::state'};

		if ($old_state ne $new_state && $main::config->{monitor}->{flap_count}) {
			if ($old_state eq 'ONLINE' and $new_state ne 'ADMIN_OFFLINE') {
				if (!$self->flapstart || $self->flapstart < time() - $main::config->{monitor}->{flap_duration}) {
					$self->flapstart(time());
					$self->flapcount(1);
				}
				else {
					$self->{'MMM::Monitor::Agent::flapcount'}++;
					if ($self->flapcount > $main::config->{monitor}->{flap_count}) {
						$self->flapping(1);
						$self->flapstart(0);
						FATAL sprintf('Host %s is flapping!', $self->host);
					}
				}
			}
		}
		$self->{'MMM::Monitor::Agent::state'} = $new_state;
		warn 'Too many args to state' if @_;
	}
	return $self->{'MMM::Monitor::Agent::state'};
}


sub _send_command {
	my $self	= shift;
	my $cmd		= shift;
	my @params	= @_;


	my $checks_status = MMM::Monitor::ChecksStatus->instance();
	unless ($checks_status->ping($self->host) && $checks_status->mysql($self->host)) {
		return 0;
	}

	DEBUG sprintf("Sending command '%s(%s)' to %s (%s:%s)", $cmd, join(', ', @params), $self->host, $self->ip, $self->port);

	my $socket;
CONNECT: {
	$socket = MMM::Common::Socket::create_sender($self->ip, $self->port, 10);
	unless ($socket && $socket->connected) {
		redo CONNECT if ($!{EINTR});
		return 0;
	}
}


	print $socket join('|', $cmd, main::MMM_PROTOCOL_VERSION, $self->host, @params), "\n";

	my $res;
READ: {
	$res = <$socket>;
	redo READ if !$res && $!{EINTR};
}
	close($socket);

	unless (defined($res)) {
		WARN sprintf('Received undefined answer from host %s. $!: %s', $self->host, $!);
		return 0;
	}

	DEBUG "Received Answer: $res";

	if ($res =~ /(.*)\|UP:(.*)/) {
		$res = $1;
		my $uptime = $2;
		$self->uptime($uptime);
		$self->last_uptime($uptime) if ($self->state eq 'ONLINE');
	}
	else {
		WARN sprintf('Received bad answer \'%s\' from host %s. $!: %s', $res, $self->host, $!);
	}
	
	return $res;
}

sub cmd_ping($) {
	my $self	= shift;
	return $self->_send_command('PING');
}

sub cmd_set_status($$) {
	my $self	= shift;
	my $master	= shift;

	return $self->_send_command('SET_STATUS', $self->state, join(',', sort(@{$self->roles})), $master);
}

sub cmd_get_agent_status($) {
	my $self	= shift;
	return $self->_send_command('GET_AGENT_STATUS');
}

sub cmd_get_system_status($) {
	my $self	= shift;
	return $self->_send_command('GET_SYSTEM_STATUS');
}

sub cmd_clear_bad_roles($) {
	my $self	= shift;
	return $self->_send_command('CLEAR_BAD_ROLES');
}

1;