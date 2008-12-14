use Fcntl ':flock'; # import LOCK_* constants

my $log_levels = {};
$log_levels->{'trap'} = 0;
$log_levels->{'error'} = 10;
$log_levels->{'notice'} = 20;
$log_levels->{'warn'} = 30;
$log_levels->{'debug'} = 100;

#-----------------------------------------------------------------
sub LogDebug($) {
    PrintLog(@_, 'debug');
}

#-----------------------------------------------------------------
sub LogNotice($) {
    PrintLog(@_, 'notice');
}

#-----------------------------------------------------------------
sub LogWarn($) {
    PrintLog(@_, 'warn');
}

#-----------------------------------------------------------------
sub LogError($) {
    PrintLog(@_, 'error');
}

#-----------------------------------------------------------------
sub LogTrap($) {
    PrintLog(@_, 'trap');
}

#-----------------------------------------------------------------
sub SendLogEmailNotice($$) {
    my $msg = shift;
    my $email = shift;
    
    my $now = strftime("%Y-%m-%d %H:%M:%S", localtime);
    
    my $sendmail = "/usr/sbin/sendmail -t";
    my $res = open(SENDMAIL, "|$sendmail");
    unless ($res) { 
        LogError("Error: Cannot open $sendmail: $!");
	    return 1;
    }
    print SENDMAIL "From: mmm_mon\@kovyrin.net\n";
    print SENDMAIL "Subject: [$now] MMM Notification\n";
    print SENDMAIL "To: $email\n\n";
    print SENDMAIL "$now: $msg\n";
    close(SENDMAIL);
}

#-----------------------------------------------------------------
sub PrintLog {
    my $msg = shift;
    my $log_level = shift;
    $log_level = "debug" unless ($log_level);
    
    my $now = strftime("%Y-%m-%d %H:%M:%S", localtime);

    my $logs = $config->{'log'};
    foreach my $log_name (keys(%$logs)) {
        my $log = $logs->{$log_name};
        next if ($log_levels->{$log_level} > $log_levels->{$log->{level}});
        
        open(LOG, ">>". $log->{file});
        flock(LOG, LOCK_EX);
        seek(LOG, 0, 2);    
        print(LOG "[$now]: $$: $msg\n");
        flock(LOG, LOCK_UN);
        
        if ($log->{email}) {
            SendLogEmailNotice($msg, $log->{email});
        }
    }
    
    unless ($config->{debug} =~ /^(off|no|0)$/i) {
        print("[$now]: $msg\n");
    }
}

1;