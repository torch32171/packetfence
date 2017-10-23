package pf::auth_log;

use strict;
use warnings;

use constant AUTH_LOG => "auth_log";

# We will use the process name defined in the logging to insert in the table
use Log::Log4perl::MDC;
use constant process_name => Log::Log4perl::MDC->get("proc") || "N/A";

use Readonly;
Readonly our $COMPLETED => "completed";
Readonly our $FAILED => "failed";
Readonly our $INCOMPLETE => "incomplete";
Readonly our $INVALIDATED => "invalidated";

BEGIN {
    use Exporter ();
    our ( @ISA, @EXPORT );
    @ISA = qw(Exporter);
    @EXPORT = qw(
        auth_log_db_prepare
        $auth_log_db_prepared
    );
}

use pf::dal;
use pf::dal::auth_log;
use pf::constants qw($ZERO_DATE);
use pf::error qw(is_error is_success);
use pf::log;

=head2 invalidate_previous

=cut

sub invalidate_previous {
    my ($source, $mac) = @_;
    my ($status, $rows) = pf::dal::auth_log->update_items(
        -set => {
            completed_at => \'NOW()',
            status => $INVALIDATED,
        },
        -where => {
            process_name => process_name,
            source => $source,
            mac => $mac,
            status => $INCOMPLETE,
        },
    );
    return $rows;
}

sub record_oauth_attempt {
    my ($source, $mac) = @_;
    invalidate_previous($source, $mac);
    my $status = pf::dal::auth_log->create({
        process_name => process_name,
        source => $source,
        mac => $mac,
        attempted_at => '\NOW()',
        status => $INCOMPLETE,
    });
    return (is_success($status));
}

sub record_completed_oauth {
    my ($source, $mac, $pid, $auth_status) = @_;
    my ($status, $rows) = pf::dal::auth_log->update_items(
        -set => {
            completed_at => \'NOW()',
            status => $auth_status,
            pid => $pid,
        },
        -where => {
            process_name => process_name,
            source => $source,
            mac => $mac,
        },
        -limit => 1,
        -order_by => { -asc => 'attempted_at' },
    );
    return $rows;
}

sub record_guest_attempt {
    my ($source, $mac, $pid) = @_;
    invalidate_previous($source, $mac);
    my $status = pf::dal::auth_log->create({
        process_name => process_name,
        source => $source,
        mac => $mac,
        pid => ($pid // ''),
        attempted_at => '\NOW()',
        status => $INCOMPLETE,
    });
    return (is_success($status));
}

sub record_completed_guest {
    my ($source, $mac, $auth_status) = @_;
    my ($status, $rows) = pf::dal::auth_log->update_items(
        -set => {
            completed_at => \'NOW()',
            status => $auth_status,
        },
        -where => {
            process_name => process_name,
            source => $source,
            mac => $mac,
        },
        -limit => 1,
        -order_by => { -asc => 'attempted_at' },
    );
    return $rows;
}

sub record_auth {
    my ($source, $mac, $pid, $auth_status) = @_;
    my $status = pf::dal::auth_log->create({
        process_name => process_name,
        source => $source,
        mac => $mac,
        pid => ($pid // ''),
        attempted_at => \'NOW()',
        completed_at => \'NOW()',
        status => $auth_status,
    });
    return (is_success($status));
}

sub change_record_status {
    my ($source, $mac, $auth_status) = @_;
    my ($status, $rows) = pf::dal::auth_log->update_items(
        -set => {
            status => $auth_status,
        },
        -where => {
            process_name => process_name,
            source => $source,
            mac => $mac,
        },
        -limit => 1,
        -order_by => { -asc => 'attempted_at' },
    );
    return $rows;
}

=head2 cleanup

Execute a cleanup job on the table

=cut

sub cleanup {
    my $timer = pf::StatsD::Timer->new({ sample_rate => 0.2 });
    my ($expire_seconds, $batch, $time_limit) = @_;
    my $logger = get_logger();
    $logger->debug("calling cleanup with time=$expire_seconds batch=$batch timelimit=$time_limit");

    if($expire_seconds eq "0") {
        $logger->debug("Not deleting because the window is 0");
        return;
    }
    my $now = pf::dal->now();
    my ($status, $rows_deleted) = pf::dal::auth_log->batch_remove(
        {
            -where => {
                attempted_at => {
                    "<" => \[ 'DATE_SUB(?, INTERVAL ? SECOND)', $now, $expire_seconds ]
                },
            },
            -limit => $batch,
        },
        $time_limit
    );
    return ($rows_deleted);
}

1;
