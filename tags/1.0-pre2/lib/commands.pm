#-----------------------------------------------------------------
sub SendMonitorCommand {
    my $cmd = shift;
    my @params = @_;
    
    my $ip = $config->{monitor_ip};
    if (!$ip) {
        LogError("Invalid configration! Can't find monitor ip!");
        exit(0);
    }
    
    LogDebug("Sending command '$cmd(" . join(', ', @params) . ")' to $ip");
    my $sock = IO::Socket::INET->new(
        PeerAddr => $ip,
        PeerPort => $config->{bind_port},
        Proto => 'tcp'
    );
    return 0 unless ($sock && $sock->connected);
    
    $sock->send("$cmd:" . join(':', @params) . "\n");
    my $res = <$sock>;
    close($sock);
    
    return $res;
}

#-----------------------------------------------------------------
sub SendAgentCommand {
    my $host = shift;
    my $cmd = shift;
    my @params = @_;
    
    my $ip = $config->{host}->{$host}->{ip};
    if (!$ip) {
        LogError("Invalid configration! Can't find agent ip!");
        exit(0);
    }
    
    LogDebug("Sending command '$cmd(" . join(', ', @params) . ")' to $ip");
    my $sock = IO::Socket::INET->new(
        PeerAddr => $ip,
        PeerPort => $config->{agent_port},
        Proto => 'tcp'
    );
    return 0 unless ($sock && $sock->connected);
    
    $sock->send("$cmd:" . join(':', @params) . "\n");
    my $res = <$sock>;
    close($sock);
    
    return $res;
}


1;
