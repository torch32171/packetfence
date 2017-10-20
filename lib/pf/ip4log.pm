package pf::ip4log;

=head1 NAME

pf::ip4log

=cut

=head1 DESCRIPTION

Class to manage IPv4 address <-> MAC address bindings

=cut

use strict;
use warnings;

# External libs
use Date::Parse;

# Internal libs
use pf::CHI;
use pf::config qw(
    $management_network
    %Config
);
use pf::constants;
use pf::dal;
use pf::dal::ip4log;
use pf::dal::ip4log_archive;
use pf::dal::ip4log_history;
use pf::error qw(is_error is_success);
use pf::log;
use pf::node qw(node_add_simple node_exist);
use pf::OMAPI;
use pf::util;

use constant IP4LOG                         => 'ip4log';
use constant IP4LOG_CACHE_EXPIRE            => 60;
use constant IP4LOG_DEFAULT_HISTORY_LIMIT   => '25';
use constant IP4LOG_DEFAULT_ARCHIVE_LIMIT   => '18446744073709551615'; # Yeah, that seems odd, but that's the MySQL documented way to use LIMIT with "unlimited"
use constant IP4LOG_FLOORED_LEASE_LENGTH    => '120';  # In seconds. Default to 2 minutes


=head2 ip2mac

Lookup for the MAC address of a given IP address

Returns '0' if no match

=cut

sub ip2mac {
    my ( $ip ) = @_;
    my $logger = pf::log::get_logger;

    unless ( pf::util::valid_ip($ip) ) {
        $logger->warn("Trying to match MAC address with an invalid IP address '" . ($ip // "undef") . "'");
        return (0);
    }

    my $mac;

    # TODO: Special case that need to be documented
    if ($ip eq "127.0.0.1" || (ref($management_network) && $management_network->{'Tip'} eq $ip)) {
        return ( pf::util::clean_mac("00:11:22:33:44:55") );
    }

    # We first query OMAPI since it is the fastest way and more reliable source of info in most cases
    if ( isenabled($Config{omapi}{ip2mac_lookup}) ) {
        $logger->debug("Trying to match MAC address to IP '$ip' using OMAPI");
        $mac = _ip2mac_omapi($ip);
        $logger->debug("Matched IP '$ip' to MAC address '$mac' using OMAPI") if $mac;
    }

    # If we don't have a result from OMAPI, we use the SQL 'ip4log' table
    unless ($mac) {
        $logger->debug("Trying to match MAC address to IP '$ip' using SQL 'ip4log' table");
        $mac = _ip2mac_sql($ip);
        $logger->debug("Matched IP '$ip' to MAC address '$mac' using SQL 'ip4log' table") if $mac;
    }

    if ( !$mac ) {
        $logger->warn("Unable to match MAC address to IP '$ip'");
        return (0);
    }

    return pf::util::clean_mac($mac);
}

=head2 _ip2mac_omapi

Look for the MAC address of a given IP address in the DHCP leases using OMAPI

Not meant to be used outside of this class. Refer to L<pf::ip4log::ip2mac>

=cut

sub _ip2mac_omapi {
    my ( $ip ) = @_;
    my $data = _lookup_cached_omapi('ip-address' => $ip);
    return $data->{'obj'}{'hardware-address'} if defined $data;
}

=head2 _ip2mac_sql

Look for the MAC address of a given IP address using the SQL 'ip4log' table

Not meant to be used outside of this class. Refer to L<pf::ip4log::ip2mac>

=cut

sub _ip2mac_sql {
    my ( $ip ) = @_;
    my $ip4log = _view_by_ip($ip);
    return $ip4log->{'mac'};
}

=head2 mac2ip

Lookup for the IP address of a given MAC address

Returns '0' if no match

=cut

sub mac2ip {
    my ( $mac ) = @_;
    my $logger = pf::log::get_logger;

    unless ( pf::util::valid_mac($mac) ) {
        $logger->warn("Trying to match IP address with an invalid MAC address '" . ($mac // "undef") . "'");
        return (0);
    }

    my $ip;

    # We first query OMAPI since it is the fastest way and more reliable source of info in most cases
    if ( isenabled($Config{omapi}{mac2ip_lookup}) ) {
        $logger->debug("Trying to match IP address to MAC '$mac' using OMAPI");
        $ip = _mac2ip_omapi($mac);
        $logger->debug("Matched MAC '$mac' to IP address '$ip' using OMAPI") if $ip;
    }

    # If we don't have a result from OMAPI, we use the SQL 'ip4log' table
    unless ($ip) {
        $logger->debug("Trying to match IP address to MAC '$mac' using SQL 'ip4log' table");
        $ip = _mac2ip_sql($mac);
        $logger->debug("Matched MAC '$mac' to IP address '$ip' using SQL 'ip4log' table") if $ip;
    }

    if ( !$ip ) {
        $logger->trace("Unable to match IP address to MAC '$mac'");
        return (0);
    }

    return $ip;
}

=head2 _mac2ip_omapi

Look for the IP address of a given MAC address in the DHCP leases using OMAPI

Not meant to be used outside of this class. Refer to L<pf::ip4log::mac2ip>

=cut

sub _mac2ip_omapi {
    my ( $mac ) = @_;
    my $data = _lookup_cached_omapi('hardware-address' => $mac);
    return $data->{'obj'}{'ip-address'} if defined $data;
}

=head2 _mac2ip_sql

Look for the IP address of a given MAC address using the SQL 'ip4log' table

Not meant to be used outside of this class. Refer to L<pf::ip4log::mac2ip>

=cut

sub _mac2ip_sql {
    my ( $mac ) = @_;
    my $ip4log = _view_by_mac($mac);
    return $ip4log->{'ip'};
}

=head2 get_history

Get the full ip4log history for a given IP address or MAC address.

=cut

sub get_history {
    my ( $search_by, %params ) = @_;
    my $logger = pf::log::get_logger;

    $params{'limit'} = defined $params{'limit'} ? $params{'limit'} : IP4LOG_DEFAULT_HISTORY_LIMIT;

    return _history_by({mac => $search_by}, %params) if ( pf::util::valid_mac($search_by) );

    return _history_by({ip => $search_by}, %params) if ( pf::util::valid_ip($search_by) );
}

=head2 get_archive

Get the full ip4log archive along with the history for a given IP address or MAC address.

=cut

sub get_archive {
    my ( $search_by, %params ) = @_;
    my $logger = pf::log::get_logger;

    $params{'with_archive'} = $TRUE;
    $params{'limit'} = defined $params{'limit'} ? $params{'limit'} : IP4LOG_DEFAULT_ARCHIVE_LIMIT;

    return get_history( $search_by, %params );
}

=head2 _history_by

Get the full ip4log for a given search

Not meant to be used outside of this class. Refer to L<pf::ip4log::get_history> or L<pf::ip4log::get_archive>

=cut

sub _history_by {
    my ( $where, %params ) = @_;
    my $logger = pf::log::get_logger;
    my $start_time;
    my $end_time;
    my $limit = $params{'limit'};
    my @columns = qw(mac ip start_time end_time unix_timestamp(start_time)|start_timestamp unix_timestamp(end_time)|end_timestamp);

    my %select_args = (
            -from => 'ip4log',
            -columns => \@columns,
            -where => $where,
            -union_all => [
                -from => 'ip4log_history',
                -columns => \@columns,
                -where => $where,
            ],
            -order_by => { -desc => 'start_time' },
            -limit => $limit,
    );

    if ( defined($params{'start_time'}) && defined($params{'end_time'}) ) {
        $start_time = $params{'start_time'};
        $end_time = $params{'end_time'};
    }

    elsif ( defined($params{'date'}) ) {
        $start_time = $params{'date'};
        $end_time = $params{'date'};
    }

    if ($start_time && $end_time) {
        $where->{start_time} = {"<" => \['from_unixtime(?)', $end_time]};
        $where->{end_time} = [{">" => \['from_unixtime(?)', $start_time]}, 0];
    }
    if ( $params{'with_archive'} ) {
        push @{$select_args{-union_all}}, -union_all => [
            -from => 'ip4log_archive',
            -columns => \@columns,
            -where => $where,
        ];
    }
    return _db_list(\%select_args);
}

=head2 view

Consult the 'ip4log' SQL table for a given IP address or MAC address.

Returns a single row for the given parameter.

=cut

sub view {
    my ( $search_by ) = @_;
    my $logger = pf::log::get_logger;

    return _view_by_mac($search_by) if ( defined($search_by) && pf::util::valid_mac($search_by) );

    return _view_by_ip($search_by) if ( defined($search_by) && pf::util::valid_ip($search_by) );

    # Nothing has been returned due to invalid "search" parameter
    $logger->warn("Trying to view an 'ip4log' table entry without a valid parameter '" . ($search_by // "undef") . "'");
}

=head2 _view_by_ip

Consult the 'ip4log' SQL table for a given IP address.

Not meant to be used outside of this class. Refer to L<pf::ip4log::view>

=cut

sub _view_by_ip {
    my ( $ip ) = @_;
    my $logger = pf::log::get_logger;

    $logger->debug("Viewing an 'ip4log' table entry for the following IP address '$ip'");

    my ($status, $iter) = pf::dal::ip4log->search(
        -where => {
            ip => $ip,
            -or => [
                end_time => 0,
                \'(end_time + INTERVAL 30 SECOND) > NOW()'
            ],
        },
        -order_by => { -desc => 'start_time' },
        -limit => 1,
        -columns => [qw(mac ip start_time end_time)],
    );

    if (is_error($status)) {
        return (0);
    }
    my $ref = $iter->next(undef);

    return ($ref);
}

=head2 _view_by_mac

Consult the 'ip4log' SQL table for a given MAC address.

Not meant to be used outside of this class. Refer to L<pf::ip4log::view>

=cut

sub _view_by_mac {
    my ( $mac ) = @_;
    my $logger = pf::log::get_logger;

    $logger->debug("Viewing an 'ip4log' table entry for the following MAC address '$mac'");

    my ($status, $iter) = pf::dal::ip4log->search(
        -where => {
            mac => $mac,
            -or => [
                end_time => 0,
                \'(end_time + INTERVAL 30 SECOND) > NOW()'
            ],
        },
        -order_by => { -desc => 'start_time' },
        -limit => 1,
        -columns => [qw(mac ip start_time end_time)],
    );

    if (is_error($status)) {
        return (0);
    }
    my $ref = $iter->next(undef);

    return ($ref);
}

=head2 list_open

List all the current open 'ip4log' SQL table entries (either for a given IP address, MAC address of both)

=cut

sub list_open {
    my ( $search_by ) = @_;
    my $logger = pf::log::get_logger;

    return _list_open_by_mac($search_by) if ( defined($search_by) && pf::util::valid_mac($search_by) );

    return _list_open_by_ip($search_by) if ( defined($search_by) && pf::util::valid_ip($search_by) );

    # We are either trying to list all the currently open 'ip4log' table entries or the given parameter was not valid.
    # Either way, we return the complete list
    $logger->debug("Listing all currently open 'ip4log' table entries");
    $logger->debug("For debugging purposes, here's the given parameter if any: '" . ($search_by // "undef") . "'");
    return _db_list(
        {
            -where => {
                end_time => [0, {">" => \'NOW()'}],
            },
            -columns => [qw(mac ip type start_time end_time)],
        }
    ) if !defined($search_by);;
}

sub _db_list {
    my ($args) = @_;
    my ($status, $iter) = pf::dal::ip4log->search(%$args);

    if (is_error($status)) {
        return;
    }
    return @{$iter->all(undef) // []};
}

=head2 _list_open_by_ip

List all the current open 'ip4log' SQL table entries for a given IP address

Not meant to be used outside of this class. Refer to L<pf::ip4log::list_open>

=cut

sub _list_open_by_ip {
    my ( $ip ) = @_;
    my $logger = pf::log::get_logger;

    $logger->debug("Listing all currently open 'ip4log' table entries for the following IP address '$ip'");

    return _db_list(
        {
            -where => {
                ip => $ip,
                -or => [
                    end_time => 0,
                    \'end_time > NOW()'
                ],
            },
            -order_by => { -desc => 'start_time' },
            -columns => [qw(mac ip type start_time end_time)],
        }
    );
}

=head2 _list_open_by_mac

List all the current open 'ip4log' SQL table entries for a given MAC address

Not meant to be used outside of this class. Refer to L<pf::ip4log::list_open>

=cut

sub _list_open_by_mac {
    my ( $mac ) = @_;
    my $logger = pf::log::get_logger;

    $logger->debug("Listing all currently open 'ip4log' table entries for the following MAC address '$mac'");

    return _db_list(
        {
            -where => {
                mac => $mac,
                -or => [
                    end_time => 0,
                    \'end_time > NOW()'
                ],
            },
            -order_by => { -desc => 'start_time' },
            -columns => [qw(mac ip type start_time end_time)],
        }
    );
}

=head2 _exists

Check if there is an existing 'ip4log' table entry for the IP address.

Not meant to be used outside of this class.

=cut

sub _exists {
    my ( $ip ) = @_;
    return (is_success(pf::dal::ip4log->exists({ip => $ip})));
}

=head2 open

Handle 'ip4log' table "new" entries. Will take care of either adding or updating an entry.

=cut

sub open {
    my ( $ip, $mac, $lease_length ) = @_;
    my $logger = pf::log::get_logger;

    # TODO: Should this really belong here ? Is it part of the responsability of ip4log to check that ?
    if ( !pf::node::node_exist($mac) ) {
        pf::node::node_add_simple($mac);
    }

    # Floor lease time to a "minimum" value to avoid some devices bad behaviors with DHCP standards
    # ie. Do not set an end_time too low for an ip4log record
    if ( $lease_length && ($lease_length < IP4LOG_FLOORED_LEASE_LENGTH) ) {
        $logger->debug("Lease length '$lease_length' is below the minimal lease length '" . IP4LOG_FLOORED_LEASE_LENGTH . "'. Flooring it.");
        $lease_length = IP4LOG_FLOORED_LEASE_LENGTH;
    }

    unless ( pf::util::valid_ip($ip) ) {
        $logger->warn("Trying to open an 'ip4log' table entry with an invalid IP address '" . ($ip // "undef") . "'");
        return;
    }

    unless ( pf::util::valid_mac($mac) ) {
        $logger->warn("Trying to open an 'ip4log' table entry with an invalid MAC address '" . ($mac // "undef") . "'");
        return;
    }

    my %args = (
        mac => $mac,
        ip => $ip,
        start_time => \"NOW()",
        end_time => '0000-00-00 00:00:00',
    );

    if ($lease_length) {
        $args{end_time} = \['DATE_ADD(NOW(), INTERVAL ? SECOND)', $lease_length],
    }
    my $item = pf::dal::ip4log->new(\%args);
    #does an upsert of the ip4log
    my $status = $item->save();

    return if is_error($status);
    if ($STATUS::CREATED == $status) {
        $logger->debug("No 'ip4log' table entry found for that IP ($ip). Creating a new one");
    } else {
        $logger->debug("An 'ip4log' table entry already exists for that IP ($ip). Proceed with updating it");
    }
    return (1);
}

=head2 close

Close (update the end_time as of now) an existing 'ip4log' table entry.

=cut

sub close {
    my ( $ip ) = @_;
    my $logger = pf::log::get_logger;

    unless ( pf::util::valid_ip($ip) ) {
        $logger->warn("Trying to close an 'ip4log' table entry with an invalid IP address '" . ($ip // "undef") . "'");
        return (0);
    }

    my ($status, $rows) = pf::dal::ip4log->update_items(
        -set => {
            end_time => \'NOW()',
        },
        -where => {
            ip => $ip,
        }
    );

    return ($rows);
}

sub rotate {
    my $timer = pf::StatsD::Timer->new({sample_rate => 0.2});
    my ( $window_seconds, $batch, $time_limit ) = @_;
    my $logger = pf::log::get_logger();

    $logger->debug("Calling rotate with window='$window_seconds' seconds, batch='$batch', timelimit='$time_limit'");
    my $now = pf::dal->now();
    my $start_time = time;
    my $end_time;
    my $rows_rotated = 0;
    my $where = {
        end_time => {
            "<" => \[ 'DATE_SUB(?, INTERVAL ? SECOND)', $now, $window_seconds ]
        },
    };

    my ( $subsql, @bind ) = pf::dal::ip4log_history->select(
        -columns => [qw(mac ip type start_time end_time)],
        -where => $where,
        -limit => $batch,
    );

    my %rotate_search = (
        -where => $where,    
        -limit => $batch,
    );

    my $sql = "INSERT INTO ip4log_archive $subsql;";

    while (1) {
        my $query;
        my ( $rows_inserted, $rows_deleted );
        pf::db::db_transaction_execute( sub{
            my ($status, $sth) = pf::dal::ip4log_archive->db_execute($sql, @bind);
            $rows_inserted = $sth->rows;
            $sth->finish;
            if ($rows_inserted > 0 ) {
                my ($status, $rows) = pf::dal::ip4log_history->remove_items(%rotate_search);
                $rows_deleted = $rows // 0;
                $logger->debug("Deleted '$rows_deleted' entries from ip4log_history while rotating");
            } else {
                $rows_deleted = 0;
            }
        } );
        $end_time = time;
        $logger->info("Inserted '$rows_inserted' entries and deleted '$rows_deleted' entries while rotating ip4log_history") if $rows_inserted != $rows_deleted;
        $rows_rotated += $rows_inserted if $rows_inserted > 0;
        $logger->trace("Rotated '$rows_rotated' entries from ip4log_history to ip4log_archive (start: '$start_time', end: '$end_time')");
        last if $rows_inserted <= 0 || ( ( $end_time - $start_time ) > $time_limit );
    }

    $logger->info("Rotated '$rows_rotated' entries from ip4log_history to ip4log_archive (start: '$start_time', end: '$end_time')");
    return (0);
}


=head2 cleanup_archive

Cleanup the ip4log_archive table

=cut

sub cleanup_archive {
    my ( $window_seconds, $batch, $time_limit ) = @_;
    return _cleanup($window_seconds, $batch, $time_limit, "pf::dal::ip4log_archive");
}

=head2 cleanup_history

Cleanup the ip4log_history table

=cut

sub cleanup_history {
    my ( $window_seconds, $batch, $time_limit ) = @_;
    return _cleanup($window_seconds, $batch, $time_limit, "pf::dal::ip4log_history");
}

=head2 _cleanup

The generic cleanup for ip4log tables

=cut

sub _cleanup {
    my $timer = pf::StatsD::Timer->new({sample_rate => 0.2});
    my ( $window_seconds, $batch, $time_limit, $dal ) = @_;
    my $logger = pf::log::get_logger();
    $logger->debug("Calling cleanup with for $dal window='$window_seconds' seconds, batch='$batch', timelimit='$time_limit'");

    if ( $window_seconds eq "0" ) {
        $logger->debug("Not deleting because the window is 0");
        return;
    }

    my $now = pf::dal->now();

    my ($status, $rows) = $dal->batch_remove(
        {
            -where => {
                end_time => {
                    "<" => \[ 'DATE_SUB(?, INTERVAL ? SECOND)', $now, $window_seconds ]
                },
            },
            -limit => $batch,
        },
        $time_limit
    );
    return ($rows);
}

=head2 omapiCache

Get the OMAPI cache

=cut

sub omapiCache { pf::CHI->new(namespace => 'omapi') }

=head2 _get_omapi_client

Get the omapi client
return undef if omapi is disabled

=cut

sub _get_omapi_client {
    my ($self) = @_;
    return unless pf::config::is_omapi_lookup_enabled;

    return pf::OMAPI->get_client();
}

=head2 _lookup_cached_omapi

Will retrieve the lease from the cache or from the dhcpd server using omapi

=cut

sub _lookup_cached_omapi {
    my ($type, $id) = @_;
    my $cache = omapiCache();
    return $cache->compute(
        $id,
        {expire_if => \&_expire_lease, expires_in => IP4LOG_CACHE_EXPIRE},
        sub {
            my $data = _get_lease_from_omapi($type, $id);
            return unless $data && $data->{op} == 3;
            #Do not return if the lease is expired
            return if $data->{obj}->{ends} < time;
            return $data;
        }
    );
}

=head2 _get_lease_from_omapi

Get the lease information using omapi

=cut

sub _get_lease_from_omapi {
    my ($type,$id) = @_;
    my $omapi = _get_omapi_client();
    return unless $omapi;
    my $data;
    eval {
        $data = $omapi->lookup({type => 'lease'}, { $type => $id});
    };
    if($@) {
        get_logger->error("$@");
    }
    return $data;
}

=head2 _expire_lease

Check if the lease has expired

=cut

sub _expire_lease {
    my ($cache_object) = @_;
    my $lease = $cache_object->value;
    return 1 unless defined $lease && defined $lease->{obj}->{ends};
    return $lease->{obj}->{ends} < time;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and::or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;
