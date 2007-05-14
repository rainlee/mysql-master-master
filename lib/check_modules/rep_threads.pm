use DBI;

sub PerformCheck($$) {
    my $timeout = shift;
    my $host = shift;
    
    # get connection info
    my $peer = $config->{host}->{$host};
    if (ref($peer) ne 'HASH') {
        return "ERROR: Invalid host!";
    }

    my $host = $peer->{ip};
    my $port = $peer->{port};
    my $user = $peer->{user};
    my $pass = $peer->{password};

    eval {
        local $SIG{ALRM} = sub { die "TIMEOUT"; };
        alarm($timeout);
    
        # connect to server
        my $dsn = "DBI:mysql:host=$host;port=$port";
        my $dbh = DBI->connect($dsn, $user, $pass, { PrintError => 0 });
        return "UNKNOWN: Connect error (host = $host:$port, user = $user, pass = '$pass')! " . DBI::errstr unless ($dbh);
    
        # Check server (replication backlog)
        my $sth = $dbh->prepare("SHOW SLAVE STATUS");
        my $res = $sth->execute;

        unless($res) {
            $sth->finish;
	        $dbh->disconnect();
            $dbh = undef;
	        return "UNKNOWN: Unknown state. Execute error: " . $dbh->errstr;
        }
    
        my $status = $sth->fetchrow_hashref;

        $sth->finish;
        $dbh->disconnect();
        $dbh = undef;

    # Check peer replication state
        if ($status->{Slave_IO_Running} eq 'No' || $status->{Slave_SQL_Running} eq 'No') {
            return "ERROR: Replication is broken";
        }
    };
    
    alarm(0);
    return 'ERROR: Timeout' if ($@ =~ /^TIMEOUT/);
    return "OK";
}

1;
