package pf::node;

=head1 NAME

pf::node - module for node management.

=cut

=head1 DESCRIPTION

pf::node contains the functions necessary to manage node: creation,
deletion, registration, expiration, read info, ...

=head1 CONFIGURATION AND ENVIRONMENT

Read the F<pf.conf> configuration file.

=cut

use strict;
use warnings;
use pf::log;
use Readonly;
use pf::StatsD::Timer;
use pf::util::statsd qw(called);
use pf::error qw(is_success);
use pf::constants::parking qw($PARKING_VID);
use CHI::Memoize qw(memoized);
use pf::dal::node;
use pf::constants::node qw(
    $STATUS_REGISTERED
    $STATUS_UNREGISTERED
    $STATUS_PENDING
    %ALLOW_STATUS
    $NODE_DISCOVERED_TRIGGER_DELAY
);
use pf::config qw(
    %Config
);

use constant NODE => 'node';

# Delay in millisecond to wait for triggering internal::node_discovered after discovering a node 
BEGIN {
    use Exporter ();
    our ( @ISA, @EXPORT );
    @ISA = qw(Exporter);
    @EXPORT = qw(
        node_db_prepare
        $node_db_prepared

        node_exist
        node_pid
        node_delete
        node_add
        node_add_simple
        node_attributes
        node_attributes_with_fingerprint
        node_view
        node_count_all
        node_view_all
        node_view_with_fingerprint
        node_view_reg_pid
        node_modify
        node_register
        node_deregister
        node_is_unregistered
        nodes_maintenance
        nodes_unregistered
        nodes_registered
        nodes_registered_not_violators
        nodes_active_unregistered
        node_expire_lastarp
        node_cleanup
        node_update_lastarp
        node_custom_search
        is_node_voip
        is_node_registered
        is_max_reg_nodes_reached
        node_search
        $STATUS_REGISTERED
        node_last_reg
        node_defaults
        node_update_last_seen
        node_last_reg_non_inline_on_category
    );
}

use pf::constants;
use pf::config::violation;
use pf::config qw(
    %connection_type_to_str
    $INLINE
    $VOIP
    $NO_VOIP
);
use pf::db;
use pf::nodecategory;
use pf::constants::scan qw($SCAN_VID $POST_SCAN_VID);
use pf::util;
use pf::Connection::ProfileFactory;
use pf::ipset;

# The next two variables and the _prepare sub are required for database handling magic (see pf::db)
our $node_db_prepared = 0;
# in this hash reference we hold the database statements. We pass it to the query handler and he will repopulate
# the hash if required
our $node_statements = {};

=head1 SUBROUTINES

TODO: This list is incomlete

=over

=cut

sub node_db_prepare {
    my $logger = get_logger();
    $logger->debug("Preparing pf::node database queries");

    $node_statements->{'node_exist_sql'} = get_db_handle()->prepare(qq[ select mac from node where mac=? ]);

    $node_statements->{'node_pid_sql'} = get_db_handle()->prepare( qq[
        SELECT count(*)
        FROM node
        WHERE status = 'reg' AND pid = ? AND category_id = ?
    ]);

    $node_statements->{'node_add_sql'} = get_db_handle()->prepare(
        qq[
        INSERT INTO node (
            mac, pid, category_id, status, voip, bypass_vlan, bypass_role_id,
            detect_date, regdate, unregdate, lastskip,
            user_agent, computername, dhcp_fingerprint,
            last_arp, last_dhcp,
            notes, autoreg, sessionid, last_seen
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW()
        )
    ]
    );

    $node_statements->{'node_delete_sql'} = get_db_handle()->prepare(qq[ delete from node where mac=? ]);

    $node_statements->{'node_modify_sql'} = get_db_handle()->prepare(
        qq[
        UPDATE node SET
            mac=?, pid=?, category_id=?, status=?, voip=?, bypass_vlan=?, bypass_role_id=?,
            detect_date=?, regdate=?, unregdate=?, lastskip=?, time_balance=?, bandwidth_balance=?,
            user_agent=?, computername=?, dhcp_fingerprint=?, dhcp_vendor=?, dhcp6_fingerprint=?, dhcp6_enterprise=?, device_type=?, device_class=?, device_version=?, device_score=?,
            last_arp=?, last_dhcp=?,
            notes=?, autoreg=?, sessionid=?, machine_account=?
        WHERE mac=?
    ]
    );

    $node_statements->{'node_attributes_sql'} = get_db_handle()->prepare(
        qq[
        SELECT mac, pid, voip, status, bypass_vlan ,
            IF(ISNULL(nc.name), '', nc.name) as category,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role,
            detect_date, regdate, unregdate, lastskip, time_balance, bandwidth_balance,
            user_agent, computername, dhcp_fingerprint, dhcp_vendor, dhcp6_fingerprint, dhcp6_enterprise, device_type, device_class, device_version, device_score,
            last_arp, last_dhcp, last_seen,
            node.notes, autoreg, sessionid, machine_account
        FROM node
            LEFT JOIN node_category as nr on node.bypass_role_id = nr.category_id
            LEFT JOIN node_category as nc on node.category_id = nc.category_id
        WHERE mac = ?
    ]
    );

    $node_statements->{'node_attributes_with_fingerprint_sql'} = get_db_handle()->prepare(
        qq[
        SELECT mac, pid, voip, status, bypass_vlan,
            IF(ISNULL(nc.name), '', nc.name) as category,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            detect_date, regdate, unregdate, lastskip,
            user_agent, computername, device_class AS dhcp_fingerprint,
            last_arp, last_dhcp, last_seen,
            node.notes, autoreg, sessionid, machine_account
        FROM node
            LEFT JOIN node_category as nr on node.bypass_role_id = nr.category_id
            LEFT JOIN node_category as nc on node.category_id = nc.category_id
        WHERE mac = ?
    ]
    );

    # DEPRECATED see _node_view_old()
    $node_statements->{'node_view_old_sql'} = get_db_handle()->prepare(
        qq[
        SELECT node.mac, node.pid, node.voip, node.bypass_vlan, node.status,
            IF(ISNULL(nc.name), '', nc.name) as category,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            node.detect_date, node.regdate, node.unregdate, node.lastskip,
            node.user_agent, node.computername, node.dhcp_fingerprint,
            node.last_arp, node.last_dhcp,
            locationlog.switch as last_switch, locationlog.port as last_port, locationlog.vlan as last_vlan,
            IF(ISNULL(locationlog.connection_type), '', locationlog.connection_type) as last_connection_type,
            locationlog.dot1x_username as last_dot1x_username, locationlog.ssid as last_ssid,
            locationlog.stripped_user_name as stripped_user_name, locationlog.realm as realm,
            locationlog.role as last_role,
            COUNT(DISTINCT violation.id) as nbopenviolations,
            node.notes
        FROM node
            LEFT JOIN node_category as nr on node.bypass_role_id = nr.category_id
            LEFT JOIN node_category as nc on node.category_id = nc.category_id
            LEFT JOIN violation ON node.mac=violation.mac AND violation.status = 'open'
            LEFT JOIN locationlog ON node.mac=locationlog.mac AND end_time = 0
        GROUP BY node.mac
        HAVING node.mac= ?
    ]
    );

    $node_statements->{'node_view_sql'} = get_db_handle()->prepare(<<'    SQL');
        SELECT node.mac, node.pid, node.voip, node.bypass_vlan, node.status, node.category_id, node.bypass_role_id,
            IF(ISNULL(nc.name), '', nc.name) as category,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            node.detect_date, node.regdate, node.unregdate, node.lastskip, node.time_balance, node.bandwidth_balance,
            node.user_agent, node.computername, node.dhcp_fingerprint, node.dhcp_vendor, node.dhcp6_fingerprint, node.dhcp6_enterprise, node.device_type, node.device_class, node.device_version, node.device_score,
            node.last_arp, node.last_dhcp, node.last_seen,
            node.notes, node.autoreg, node.sessionid, node.machine_account,
            UNIX_TIMESTAMP(node.regdate) AS regdate_timestamp,
            UNIX_TIMESTAMP(node.unregdate) AS unregdate_timestamp
        FROM node
            LEFT JOIN node_category as nr on node.bypass_role_id = nr.category_id
            LEFT JOIN node_category as nc on node.category_id = nc.category_id
        WHERE node.mac=?
    SQL

    $node_statements->{'node_view_reg_pid_sql'} = get_db_handle()->prepare(<<"    SQL");
        SELECT node.mac
        FROM node
        WHERE node.pid=? AND node.status="$STATUS_REGISTERED";
    SQL

    $node_statements->{'node_last_locationlog_sql'} = get_db_handle()->prepare(<<'    SQL');
       SELECT
           locationlog.switch as last_switch, locationlog.port as last_port, locationlog.vlan as last_vlan,
           IF(ISNULL(locationlog.connection_type), '', locationlog.connection_type) as last_connection_type,
           IF(ISNULL(locationlog.connection_sub_type), '', locationlog.connection_sub_type) as last_connection_sub_type,
           locationlog.dot1x_username as last_dot1x_username, locationlog.ssid as last_ssid,
           locationlog.stripped_user_name as stripped_user_name, locationlog.realm as realm,
           locationlog.switch_mac as last_switch_mac,
           locationlog.start_time as last_start_time, locationlog.role as last_role,
           UNIX_TIMESTAMP(locationlog.start_time) as last_start_timestamp,
           locationlog.ifDesc as last_ifDesc
       FROM locationlog
       WHERE mac = ? AND end_time = 0
    SQL

    # DEPRECATED see node_view_with_fingerprint()'s POD
    $node_statements->{'node_view_with_fingerprint_sql'} = get_db_handle()->prepare(
        qq[
        SELECT node.mac, node.pid, node.voip, node.bypass_vlan, node.status,
            IF(ISNULL(nc.name), '', nc.name) as category,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            node.detect_date, node.regdate, node.unregdate, node.lastskip,
            node.user_agent, node.computername, device_class AS dhcp_fingerprint,
            node.last_arp, node.last_dhcp,
            locationlog.switch as last_switch, locationlog.port as last_port, locationlog.vlan as last_vlan,
            IF(ISNULL(locationlog.connection_type), '', locationlog.connection_type) as last_connection_type,
            locationlog.dot1x_username as last_dot1x_username, locationlog.ssid as last_ssid,
            locationlog.stripped_user_name as stripped_user_name, locationlog.realm as realm,
            locationlog.role as last_role,
            COUNT(DISTINCT violation.id) as nbopenviolations,
            node.notes
        FROM node
            LEFT JOIN node_category as nr on node.bypass_role_id = nr.category_id
            LEFT JOIN node_category as nc on node.category_id = nc.category_id
            LEFT JOIN violation ON node.mac=violation.mac AND violation.status = 'open'
            LEFT JOIN locationlog ON node.mac=locationlog.mac AND end_time = 0
        GROUP BY node.mac
        HAVING node.mac=?
    ]
    );

    # This guy here is not in a prepared statement yet, have a look in node_view_all to see why
    $node_statements->{'node_view_all_sql'} = qq[
       SELECT node.mac, node.pid, node.voip, node.bypass_vlan, node.status,
            IF(ISNULL(nc.name), '', nc.name) as category,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            IF(node.detect_date = '0000-00-00 00:00:00', '', node.detect_date) as detect_date,
            IF(node.regdate = '0000-00-00 00:00:00', '', node.regdate) as regdate,
            IF(node.unregdate = '0000-00-00 00:00:00', '', node.unregdate) as unregdate,
            IF(node.lastskip = '0000-00-00 00:00:00', '', node.lastskip) as lastskip,
            node.user_agent, node.computername, device_class AS dhcp_fingerprint,
            node.last_arp, node.last_dhcp, node.last_seen,
            locationlog.switch as last_switch, locationlog.port as last_port, locationlog.vlan as last_vlan,
            IF(ISNULL(locationlog.connection_type), '', locationlog.connection_type) as last_connection_type,
            locationlog.dot1x_username as last_dot1x_username, locationlog.ssid as last_ssid,
            locationlog.stripped_user_name as stripped_user_name, locationlog.realm as realm,
            locationlog.switch_mac as last_switch_mac,
            ip4log.ip as last_ip,
            COUNT(DISTINCT violation.id) as nbopenviolations,
            node.notes
        FROM node
            LEFT JOIN node_category as nr on node.bypass_role_id = nr.category_id
            LEFT JOIN node_category as nc on node.category_id = nc.category_id
            LEFT JOIN violation ON node.mac=violation.mac AND violation.status = 'open'
            LEFT JOIN locationlog ON node.mac=locationlog.mac AND end_time = 0
            LEFT JOIN ip4log ON node.mac=ip4log.mac AND (ip4log.end_time = '0000-00-00 00:00:00' OR ip4log.end_time > NOW())
        GROUP BY node.mac
    ];

    # This guy here is special, have a look in node_count_all to see why
    $node_statements->{'node_count_all_sql'} = qq[
        SELECT count(*) as nb
        FROM node
    ];

    $node_statements->{'node_expire_unreg_field_sql'} = get_db_handle()->prepare(
        qq [ select mac from node where
                ( status="reg" and unregdate != 0 and unregdate < now() ) or
                ( status="pending" and unregdate != 0 and unregdate < now() ) ]);

    $node_statements->{'node_expire_lastarp_sql'} = get_db_handle()->prepare(
        qq [ select mac from node where unix_timestamp(last_arp) < (unix_timestamp(now()) - ?) and last_arp!=0 ]);

    $node_statements->{'node_expire_lastseen_sql'} = get_db_handle()->prepare(
        qq [ select mac from node where unix_timestamp(last_seen) < (unix_timestamp(now()) - ?) and last_seen!="0000-00-00 00:00:00" and status="$STATUS_UNREGISTERED" ]);

    $node_statements->{'node_unreg_lastseen_sql'} = get_db_handle()->prepare(
        qq [ select mac from node where unix_timestamp(last_seen) < (unix_timestamp(now()) - ?) and last_seen!="0000-00-00 00:00:00" and status="$STATUS_REGISTERED" ]);

    $node_statements->{'node_is_unregistered_sql'} = get_db_handle()->prepare(
        qq[
        SELECT mac, pid, voip, bypass_vlan, status,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            detect_date, regdate, unregdate, lastskip,
            user_agent, computername, dhcp_fingerprint,
            last_arp, last_dhcp,
            node.notes
        FROM node
            LEFT JOIN node_category as nr on node.category_id = nr.category_id
        WHERE status = "$STATUS_UNREGISTERED" AND mac = ?
    ]
    );

    $node_statements->{'nodes_unregistered_sql'} = get_db_handle()->prepare(qq[
        SELECT mac, pid, voip, bypass_vlan, status,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            detect_date, regdate, unregdate, lastskip,
            user_agent, computername, dhcp_fingerprint,
            last_arp, last_dhcp,
            node.notes
        FROM node
            LEFT JOIN node_category as nr on node.category_id = nr.category_id
        WHERE status = "$STATUS_UNREGISTERED"
    ]);

    $node_statements->{'nodes_registered_sql'} = get_db_handle()->prepare(
        qq[
        SELECT mac, pid, voip, bypass_vlan, status,
            IF(ISNULL(nr.name), '', nr.name) as bypass_role ,
            detect_date, regdate, unregdate, lastskip,
            user_agent, computername, dhcp_fingerprint,
            last_arp, last_dhcp,
            node.notes
        FROM node
            LEFT JOIN node_category as nr on node.category_id = nr.category_id
        WHERE status = "$STATUS_REGISTERED"
    ]
    );

    $node_statements->{'nodes_registered_not_violators_sql'} = get_db_handle()->prepare(qq[
        SELECT node.mac, node.category_id FROM node
            LEFT JOIN violation ON node.mac=violation.mac AND violation.status='open'
        WHERE node.status='reg' GROUP BY node.mac HAVING count(violation.mac)=0
    ]);

    $node_statements->{'nodes_active_unregistered_sql'} = get_db_handle()->prepare(qq [
        SELECT n.mac, n.pid, n.detect_date, n.regdate, n.unregdate, n.lastskip,
            n.status, n.user_agent, n.computername, n.notes,
            i.ip, i.start_time, i.end_time, n.last_arp
        FROM node n LEFT JOIN ip4log i ON n.mac=i.mac
        WHERE n.status = "unreg" AND (i.end_time = 0 OR i.end_time > now())
    ]);

    $node_statements->{'nodes_active_sql'} = get_db_handle()->prepare(qq [
        SELECT n.mac, n.pid, n.detect_date, n.regdate, n.unregdate, n.lastskip,
            n.status, n.user_agent, n.computername, n.notes, n.dhcp_fingerprint,
            i.ip, i.start_time, i.end_time, n.last_arp
        FROM node n, ip4log i
        WHERE n.mac = i.mac AND (i.end_time = 0 OR i.end_time > now())
    ]);

    $node_statements->{'node_update_lastarp_sql'} = get_db_handle()->prepare(qq [ update node set last_arp=now() where mac=? ]);

    $node_statements->{'node_search_sql'} = get_db_handle()->prepare(qq [ select mac from node where mac LIKE CONCAT(?,'%') ]);

    $node_statements->{'node_last_reg_sql'} = get_db_handle()->prepare(qq [ select mac from node order by regdate DESC LIMIT 1,1 ]);

    $node_statements->{'node_update_bandwidth_sql'} = get_db_handle()->prepare(qq[
        UPDATE node SET bandwidth_balance = COALESCE(bandwidth_balance, 0) + ?
        WHERE mac = ?
    ]);

    $node_statements->{'node_update_last_seen_sql'} = get_db_handle()->prepare(qq[
        UPDATE node SET last_seen = NOW()
        WHERE mac = ?
    ]);

    $node_statements->{'node_last_reg_non_inline_on_category_sql'} = get_db_handle()->prepare(qq [
        SELECT node.mac FROM node
            RIGHT JOIN locationlog on node.mac=locationlog.mac
            RIGHT JOIN node_category USING (category_id)
        WHERE node.mac != ? AND node.status="reg" AND node_category.name = ?  AND locationlog.connection_type != "Inline" and locationlog.end_time is NULL order by node.regdate DESC LIMIT 1 ]);

    $node_db_prepared = 1;
    return 1;
}

=item _node_exist

The real implemntation of _node_exist

=cut

sub _node_exist {
    my ($mac) = @_;
    my $query = db_query_execute(NODE, $node_statements, 'node_exist_sql', $mac) || return (0);
    my ($val) = $query->fetchrow_array();
    $query->finish();
    return ($val);
}

#
# return mac if the node exists
#
sub node_exist {
    my ($mac) = @_;
    $mac = clean_mac($mac);
    if ($mac) {
        return pf::node::_node_exist($mac);
    }
    return (0);
}

#
# return number of nodes for the specified pid and role id
#
sub node_pid {
    my ($pid, $category_id) = @_;
    my $query = db_query_execute(NODE, $node_statements, 'node_pid_sql', $pid, $category_id) || return (0);
    my ($count) = $query->fetchrow_array();
    $query->finish();
    return ($count);
}

#
# return mac for specified register pid
#
sub node_view_reg_pid {
    my ($pid) = @_;
    return (db_data(NODE, $node_statements, 'node_view_reg_pid_sql', $pid));
}

#
# delete and return 1
#
sub node_delete {
    my $timer = pf::StatsD::Timer->new({level => 6});
    my ($mac) = @_;
    my $logger = get_logger();

    $mac = clean_mac($mac);

    if ( !node_exist($mac) ) {
        $logger->error("delete of non-existent node '$mac' failed");
        return 0;
    }

    require pf::locationlog;
    # TODO that limitation is arbitrary at best, we need to resolve that.
    if ( defined( pf::locationlog::locationlog_view_open_mac($mac) ) ) {
        $logger->warn("$mac has an open locationlog entry. Node deletion prohibited");
        return 0;
    }

    db_query_execute(NODE, $node_statements, 'node_delete_sql', $mac) || return (0);
    $logger->info("node $mac deleted");
    return (1);
}

our %DEFAULT_NODE_VALUES = (
    'autoreg'          => 'no',
    'bypass_vlan'      => '',
    'computername'     => '',
    'detect_date'      => '0000-00-00 00:00:00',
    'dhcp_fingerprint' => '',
    'last_arp'         => '0000-00-00 00:00:00',
    'last_dhcp'        => '0000-00-00 00:00:00',
    'lastskip'         => '0000-00-00 00:00:00',
    'notes'            => '',
    'pid'              => $default_pid,
    'regdate'          => '0000-00-00 00:00:00',
    'sessionid'        => '',
    'status'           => $STATUS_UNREGISTERED,
    'unregdate'        => '0000-00-00 00:00:00',
    'user_agent'       => '',
    'voip'             => 'no',
);

#
# clean input parameters and add to node table
#
sub node_add {
    my $timer = pf::StatsD::Timer->new({level => 6});
    my ( $mac, %data ) = @_;
    my $logger = get_logger();
    $logger->trace("node add called");

    $mac = clean_mac($mac);
    if ( !valid_mac($mac) ) {
        return (0);
    }

    if ( node_exist($mac) ) {
        $logger->warn("attempt to add existing node $mac");
        return (2);
    }

    foreach my $field (keys %DEFAULT_NODE_VALUES)
    {
        $data{$field} = $DEFAULT_NODE_VALUES{$field} if ( !defined $data{$field} );
    }

    _cleanup_attributes(\%data);

    if ( ( $data{status} eq $STATUS_REGISTERED ) && ( $data{regdate} eq '' ) ) {
        $data{regdate} = mysql_date();
    }

    # category handling
    $data{'category_id'} = _node_category_handling(%data);
    if ( defined( $data{'category_id'} ) && $data{'category_id'} == 0 ) {
        $logger->error("Unable to insert node because specified category doesn't exist");
        return (0);
    }

    my $statement = db_query_execute( NODE, $node_statements, 'node_add_sql', $mac,
        $data{pid},              $data{category_id}, $data{status},      $data{voip},
        $data{bypass_vlan},      $data{bypass_role_id}, $data{detect_date}, $data{regdate},
        $data{unregdate},        $data{lastskip},    $data{user_agent},  $data{computername},
        $data{dhcp_fingerprint}, $data{last_arp},    $data{last_dhcp},   $data{notes},
        $data{autoreg},          $data{sessionid}
    );

    my $apiclient = pf::api::queue->new(queue => 'general');
    $apiclient->notify_delayed($NODE_DISCOVERED_TRIGGER_DELAY, "trigger_violation", mac => $mac, type => "internal", tid => "node_discovered");

    if ($statement) {
        return ($statement->rows == 1 ? 1 : 0);
    }
    else {
        return (0);
    }
}

#
# simple wrapper for pfmon/pfdhcplistener-detected and auto-generated nodes
#
sub node_add_simple {
    my ($mac) = @_;
    my $date  = mysql_date();
    my %tmp   = (
        'pid'         => 'default',
        'detect_date' => $date,
        'status'      => 'unreg',
        'voip'        => 'no',
    );
    if ( !node_add( $mac, %tmp ) ) {
        return (0);
    } else {
        return (1);
    }
}

=item _cleanup_status_value

Cleans the status value to make sure that a valid status is being set

=cut

sub _cleanup_status_value {
    my ($status) = @_;
    unless ( defined $status && exists $ALLOW_STATUS{$status} ) {
        my $logger = get_logger();
        $logger->warn("The status was set to " . (defined $status ? $status : "'undef'") . " changing it $STATUS_UNREGISTERED" );
        $pf::StatsD::statsd->increment(called() . ".warn.count" );
        $status = $STATUS_UNREGISTERED;
    }
    return $status;
}

=item node_attributes

Returns information about a given MAC address (node)

It's a simpler and faster version of node_view with fewer fields returned.

=cut

sub node_attributes {
    my ($mac) = @_;
    $mac = clean_mac($mac);
    my $query = db_query_execute(NODE, $node_statements, 'node_attributes_sql', $mac) || return (0);
    my $ref = $query->fetchrow_hashref();

    # just get one row and finish
    $query->finish();
    return ($ref);
}

=item node_attributes_with_fingerprint

Returns information about a given MAC address (node) with the DHCP
fingerprint class as a string.

It's a simpler and faster version of node_view_with_fingerprint with
fewer fields returned.

=cut

sub node_attributes_with_fingerprint {
    my ($mac) = @_;

    my $query = db_query_execute(NODE, $node_statements, 'node_attributes_with_fingerprint_sql', $mac) || return (0);
    my $ref = $query->fetchrow_hashref();

    # just get one row and finish
    $query->finish();
    return ($ref);
}

=item _node_view_old

Returning lots of information about a given MAC address (node)

DEPRECATED: This has been kept in case of regressions in the new node_view code.
This code will disappear in 2013.

=cut

sub _node_view_old {
    my ($mac) = @_;
    $mac = clean_mac($mac);

    # Uncomment to log callers
    #my $logger = get_logger();
    #my $caller = ( caller(1) )[3] || basename($0);
    #$logger->trace("node_view called from $caller");

    my $query = db_query_execute(NODE, $node_statements, 'node_view_old_sql', $mac) || return (0);
    my $ref = $query->fetchrow_hashref();

    # just get one row and finish
    $query->finish();
    return ($ref);
}

=item _node_view

The real implementation of node_view

=cut

sub _node_view {
    my ($mac) = @_;
    pf::log::logstacktrace("pf::node::node_view getting '$mac'");
    # Uncomment to log callers
    #my $logger = get_logger();
    #my $caller = ( caller(1) )[3] || basename($0);
    #$logger->trace("node_view called from $caller");

    my $query = db_query_execute(NODE, $node_statements, 'node_view_sql', $mac) || return (0);
    my $node_info_ref = $query->fetchrow_hashref();
    $query->finish();

    # if no node info returned we exit
    if (!defined($node_info_ref)) {
        return undef;
    }

    $query = db_query_execute(NODE, $node_statements, 'node_last_locationlog_sql', $mac) || return (0);
    my $locationlog_info_ref = $query->fetchrow_hashref();
    $query->finish();

    # merge hash references
    # set locationlog info to empty hashref in case result from query was nothing
    $locationlog_info_ref = {} if (!defined($locationlog_info_ref));
    $node_info_ref = {
        %$node_info_ref,
        %$locationlog_info_ref,
    };

    return ($node_info_ref);
}

=item node_view

Returning lots of information about a given MAC address (node).

New implementation in 3.2.0.

=cut

sub node_view {
    my $timer = pf::StatsD::Timer->new({level => 6});
    my ($mac) = @_;
    $mac = clean_mac($mac);
    if ($mac) {
        return _node_view($mac);
    }
    return undef;
}

sub node_count_all {
    my $timer = pf::StatsD::Timer->new({level => 6});
    my ( $id, %params ) = @_;
    my $logger = get_logger();

    # Hack! we prepare the statement here so that $node_count_all_sql is pre-filled
    node_db_prepare() if (!$node_db_prepared);
    my $node_count_all_sql = $node_statements->{'node_count_all_sql'};

    if ( defined( $params{'where'} ) ) {
        my @where = ();
        if ( $params{'where'}{'type'} ) {
            if ( $params{'where'}{'type'} eq 'pid' ) {
                push(@where, "node.pid = " . get_db_handle()->quote($params{'where'}{'value'}));
            }
            elsif ( $params{'where'}{'type'} eq 'category' ) {
                my $cat_id = nodecategory_lookup($params{'where'}{'value'});
                if (!defined($cat_id)) {
                    # lets be nice and issue a warning if the category doesn't exist
                    $logger->warn("there was a problem looking up category ".$params{'where'}{'value'});
                    # put cat_id to 0 so it'll return 0 results (achieving the count ok)
                    $cat_id = 0;
                }
                push(@where, "category_id = " . $cat_id);
            }
            elsif ( $params{'where'}{'type'} eq 'status') {
                push(@where, "node.status = " . get_db_handle()->quote($params{'where'}{'value'}));
            }
            elsif ( $params{'where'}{'type'} eq 'any' ) {
                if (exists($params{'where'}{'like'})) {
                    my $like = get_db_handle->quote('%' . $params{'where'}{'like'} . '%');
                    my $where_any .= "(mac LIKE $like"
                                   . " OR computername LIKE $like"
                                   . " OR pid LIKE $like)";
                    push(@where, $where_any);
                }
            }
        }
        if ( ref($params{'where'}{'between'}) ) {
            push(@where, sprintf '%s BETWEEN %s AND %s',
                 $params{'where'}{'between'}->[0],
                 get_db_handle()->quote($params{'where'}{'between'}->[1]),
                 get_db_handle()->quote($params{'where'}{'between'}->[2]));
        }
        if (@where) {
            $node_count_all_sql .= ' WHERE ' . join(' AND ', @where);
        }
    }

    # Hack! Because of the nature of the query built here (we cannot prepare it), we construct it as a string
    # and pf::db will recognize it and prepare it as such
    $node_statements->{'node_count_all_sql_custom'} = $node_count_all_sql;
    #$logger->debug($node_count_all_sql);

    my @data =  db_data(NODE, $node_statements, 'node_count_all_sql_custom');
    return @data;
}

sub node_custom_search {
    my ($sql) = @_;
    my $logger = get_logger();
    $logger->debug($sql);
    $node_statements->{'node_custom_search_sql_customer'} = $sql;
    return db_data(NODE, $node_statements, 'node_custom_search_sql_customer');
}

=item * node_view_all - view all nodes based on several criteria

Warning: The connection_type field is translated into its human form before return.

=cut

sub node_view_all {
    my $timer = pf::StatsD::Timer->new({level => 6});
    my ( $id, %params ) = @_;
    my $logger = get_logger();

    # Hack! we prepare the statement here so that $node_view_all_sql is pre-filled
    node_db_prepare() if (!$node_db_prepared);
    my $node_view_all_sql = $node_statements->{'node_view_all_sql'};

    if ( defined( $params{'where'} ) ) {
        if ( $params{'where'}{'type'} eq 'pid' ) {
            $node_view_all_sql
                .= " HAVING node.pid='" . $params{'where'}{'value'} . "'";
        }
        elsif ( $params{'where'}{'type'} eq 'category' ) {

            if (!nodecategory_lookup($params{'where'}{'value'})) {
                # lets be nice and issue a warning if the category doesn't exist
                $logger->warn("there was a problem looking up category ".$params{'where'}{'value'});
            }
            $node_view_all_sql .= " HAVING category='" . $params{'where'}{'value'} . "'";
        }
        elsif ( $params{'where'}{'type'} eq 'any' ) {
            my $like = $params{'where'}{'like'};
            $like =~ s/^ *//;
            $like =~ s/ *$//;
            if (valid_mac($like) && !valid_ip($like)) {
                my $mac = get_db_handle->quote(clean_mac($like));
                $node_view_all_sql .= " HAVING node.mac = $mac";
            }
            else {
                $like = get_db_handle->quote('%' . $params{'where'}{'like'} . '%');
                $node_view_all_sql .= " HAVING node.mac LIKE $like"
                  . " OR node.computername LIKE $like"
                  . " OR node.pid LIKE $like"
                  . " OR ip4log.ip LIKE $like";
            }
        }
    }
    if ( defined( $params{'orderby'} ) ) {
        $node_view_all_sql .= " " . $params{'orderby'};
    }
    if ( defined( $params{'limit'} ) ) {
        $node_view_all_sql .= " " . $params{'limit'};
    }

    # Hack! Because of the nature of the query built here (we cannot prepare it), we construct it as a string
    # and pf::db will recognize it and prepare it as such
    $node_statements->{'node_view_all_sql_custom'} = $node_view_all_sql;

    require pf::pfcmd::report;
    import pf::pfcmd::report;
    my @data = translate_connection_type(db_data(NODE, $node_statements, 'node_view_all_sql_custom'));
    return @data;
}

=item node_view_with_fingerprint

DEPRECATED: This has been kept in case of regressions in the new
node_attributes_with_fingerprint code.  This code will disappear in 2013.

=cut

sub node_view_with_fingerprint {
    my $timer = pf::StatsD::Timer->new({level => 6});
    my ($mac) = @_;
    my $logger = get_logger();

    $logger->warn("DEPRECATED! You should migrate the caller to the faster node_attributes_with_fingerprint");
    my $query = db_query_execute(NODE, $node_statements, 'node_view_with_fingerprint_sql', $mac) || return (0);
    my $ref = $query->fetchrow_hashref();

    # just get one row and finish
    $query->finish();
    return ($ref);
}

sub node_modify {
    my $timer = pf::StatsD::Timer->new;
    my ( $mac, %data ) = @_;
    my $logger = get_logger();


    # validation
    $mac = clean_mac($mac);
    if ( !valid_mac($mac) ) {
        return (0);
    }

    if ( !node_exist($mac) ) {
        if ( node_add_simple($mac) ) {
            $logger->info(
                "modify of non-existent node $mac attempted - node added");
        } else {
            $logger->error(
                "modify of non-existent node $mac attempted - node add failed"
            );
            return (0);
        }
    }

    my $existing = node_attributes($mac);
    # keep track of status
    my $old_status = $existing->{status};
    # special handling for category to category_id conversion
    $existing->{'category_id'} = nodecategory_lookup($existing->{'category'});
    $existing->{'bypass_role_id'} = nodecategory_lookup($existing->{'bypass_role'});
    my $old_role_id = $existing->{'category_id'};
    foreach my $item ( keys(%data) ) {
        $existing->{$item} = $data{$item};
    }

    # category handling
    # if category was updated, resolve it correctly
    my $new_role_id = $old_role_id;
    if (defined($data{'category'}) || defined($data{'category_id'})) {
        $existing->{'category_id'} = _node_category_handling(%data);
        if (defined($existing->{'category_id'}) && $existing->{'category_id'} == 0) {
            $logger->error("Unable to modify node because specified category doesn't exist");
        }
        if ( defined($data{'category'}) && $data{'category'} ne '' ) {
            $new_role_id = nodecategory_lookup($data{'category'});
        } elsif (defined($data{'category_id'})) {
            $new_role_id = $data{'category_id'};
        }

       # once the category conversion is complete, I delete the category entry to avoid complicating things
       delete $existing->{'category'} if defined($existing->{'category'});
    }

    # Autoregistration handling
    if (defined($data{'autoreg'})) {  $existing->{autoreg} = $data{'autoreg'}; }

    _cleanup_attributes($existing);

    my $new_mac    = clean_mac(lc( $existing->{'mac'} ));
    my $new_status = $existing->{'status'};

    if ( $mac ne $new_mac && node_exist($new_mac) ) {
        $logger->error(
            "modify of node $mac to $new_mac conflicts with existing node");
        return (0);
    }

    if (( $existing->{status} eq 'reg' )
        && (   $existing->{regdate} eq '0000-00-00 00:00:00'
            || $existing->{regdate} eq '' )
        )
    {
        $existing->{regdate} = mysql_date();
    }

    my $sth = db_query_execute( NODE, $node_statements,
        'node_modify_sql',              $new_mac,
        $existing->{pid},               $existing->{category_id},
        $existing->{status},            $existing->{voip},
        $existing->{bypass_vlan},       $existing->{bypass_role_id},
        $existing->{detect_date},       $existing->{regdate},
        $existing->{unregdate},         $existing->{lastskip},
        $existing->{time_balance},      $existing->{bandwidth_balance},
        $existing->{user_agent},        $existing->{computername},
        $existing->{dhcp_fingerprint},  $existing->{dhcp_vendor},
        $existing->{dhcp6_fingerprint}, $existing->{dhcp6_enterprise},
        $existing->{device_type},       $existing->{device_class},
        $existing->{device_version},    $existing->{device_score},  
        $existing->{last_arp},          $existing->{last_dhcp},
        $existing->{notes},             $existing->{autoreg},
        $existing->{sessionid},         $existing->{machine_account},
        $mac
    );
    if($sth) {
        return ( $sth->rows );
    }
    $logger->error("Unable to modify node '" . $mac // 'undef' . "'");
    return undef;
}

sub node_register {
    my $timer = pf::StatsD::Timer->new();
    my ( $mac, $pid, %info ) = @_;
    my $logger = get_logger();
    $mac = lc($mac);
    my $auto_registered = 0;

    my $status_msg = "";

    # hack to support an additional autoreg param to the sub without changing the hash to a reference everywhere
    if (defined($info{'auto_registered'})) {
        $auto_registered = 1;
    }

    require pf::person;
    require pf::lookup::person;
    # create a person entry for pid if it doesn't exist
    if ( !pf::person::person_exist($pid) ) {
        $logger->info("creating person $pid because it doesn't exist");
        pf::person::person_add($pid);
        pf::lookup::person::async_lookup_person($pid,$info{'source'});

    } else {
        $logger->debug("person $pid already exists");
    }
    pf::person::person_modify($pid,
                    'source'  => $info{'source'},
                    'portal'  => $info{'portal'},
    );
    delete $info{'source'};
    delete $info{'portal'};

    # if it's for auto-registration and mac is already registered, we are done
    if ($auto_registered) {
       my $node_info = node_view($mac);
       if (defined($node_info) && (ref($node_info) eq 'HASH') && $node_info->{'status'} eq 'reg') {
        $info{'pid'} = $pid;
        if ( !node_modify( $mac, %info ) ) {
            $logger->error("modify of node $mac failed");
            return (0);
        }
           $logger->info("autoregister a node that is already registered, do nothing.");
           return 1;
       }
    }
    else {
    # do not check for max_node if it's for auto-register
        if ( is_max_reg_nodes_reached($mac, $pid, $info{'category'}, $info{'category_id'}) ) {
            $status_msg = "max nodes per pid met or exceeded";
            $logger->error( "$status_msg - registration of $mac to $pid failed" );
            return ($FALSE, $status_msg);
        }
    }

    $info{'pid'}     = $pid;
    $info{'status'}  = 'reg';
    $info{'regdate'} = mysql_date();

    if ( !node_modify( $mac, %info ) ) {
        $logger->error("modify of node $mac failed");
        return (0);
    }
    $pf::StatsD::statsd->increment( called() . ".called" );

    # Closing any parking violations
    # loading pf::violation here to prevent circular dependency
    require pf::violation;
    pf::violation::violation_force_close($mac, $PARKING_VID);

    my $profile = pf::Connection::ProfileFactory->instantiate($mac);
    my $scan = $profile->findScan($mac);
    if (defined($scan)) {
        # triggering a violation used to communicate the scan to the user
        if ( isenabled($scan->{'registration'})) {
            $logger->debug("Triggering on registration scan");
            pf::violation::violation_add( $mac, $SCAN_VID );
        }
        if (isenabled($scan->{'post_registration'})) {
            $logger->debug("Triggering post-registration scan");
            pf::violation::violation_add( $mac, $POST_SCAN_VID );
        }
    }

    return (1);
}

sub node_deregister {
    my $timer = pf::StatsD::Timer->new;
    my ($mac, %info) = @_;
    my $logger = get_logger();
    $pf::StatsD::statsd->increment( called() . ".called" );

    $info{'status'}    = 'unreg';
    $info{'regdate'}   = 0;
    $info{'unregdate'} = 0;
    $info{'lastskip'}  = 0;
    $info{'autoreg'}   = 'no';

    my $profile = pf::Connection::ProfileFactory->instantiate($mac);
    if(my $provisioner = $profile->findProvisioner($mac)){
        if(my $pki_provider = $provisioner->getPkiProvider() ){
            if(isenabled($pki_provider->revoke_on_unregistration)){
                my $node_info = node_view($mac);
                my $cn = $pki_provider->user_cn($node_info);
                $pki_provider->revoke($cn);
            }
        }
    }

    if ( !node_modify( $mac, %info ) ) {
        $logger->error("unable to de-register node $mac");
        return (0);
    }

    return (1);
}

=item * nodes_maintenance - handling deregistration on node expiration and node grace

called by pfmon daemon every 10 maintenance interval (usually each 10 minutes)

=cut

sub nodes_maintenance {
    my $timer = pf::StatsD::Timer->new;
    my $logger = get_logger();

    $logger->debug("nodes_maintenance called");

    my $expire_unreg_query = db_query_execute(NODE, $node_statements, 'node_expire_unreg_field_sql') ;
    unless ($expire_unreg_query ) {
        return (0);
    }

    while (my $row = $expire_unreg_query->fetchrow_hashref()) {
        my $currentMac = $row->{mac};
        node_deregister($currentMac);
        require pf::enforcement;
        pf::enforcement::reevaluate_access( $currentMac, 'manage_deregister' );

        $logger->info("modified $currentMac from status 'reg' to 'unreg' based on unregdate colum" );
    }

    return (1);
}

# check to see is $mac is registered
#
sub node_is_unregistered {
    my ($mac) = @_;

    my $query = db_query_execute(NODE, $node_statements, 'node_is_unregistered_sql', $mac) || return (0);
    my $ref = $query->fetchrow_hashref();
    $query->finish();
    return ($ref);
}

sub nodes_unregistered {
    return db_data(NODE, $node_statements, 'nodes_unregistered_sql');
}

sub nodes_registered {
    return db_data(NODE, $node_statements, 'nodes_registered_sql');
}

=item nodes_registered_not_violators

Returns a list of MACs which are registered and don't have any open violation.
Since trap violations stay open, this has the intended effect of getting all MACs which should be allowed through.

=cut

sub nodes_registered_not_violators {
    return db_data(NODE, $node_statements, 'nodes_registered_not_violators_sql');
}

sub nodes_active_unregistered {
    return db_data(NODE, $node_statements, 'nodes_active_unregistered_sql');
}

sub node_expire_lastarp {
    my ($time) = @_;
    return db_data(NODE, $node_statements, 'node_expire_lastarp_sql', $time);
}

=item node_expire_lastseen

Get the nodes that should be deleted based on the last_seen column 

=cut

sub node_expire_lastseen {
    my ($time) = @_;
    return db_data(NODE, $node_statements, 'node_expire_lastseen_sql', $time);
}

=item node_unreg_lastseen

Get the nodes that should be unregistered based on the last_seen column 

=cut

sub node_unreg_lastseen {
    my ($time) = @_;
    return db_data(NODE, $node_statements, 'node_unreg_lastseen_sql', $time);
}

=item node_cleanup

Cleanup nodes that should be deleted or unregistered based on the maintenance parameters

=cut

sub node_cleanup {
    my $timer = pf::StatsD::Timer->new;
    my ($delete_time, $unreg_time) = @_;
    my $logger = get_logger();
    $logger->debug("calling node_cleanup with delete_time=$delete_time unreg_time=$unreg_time");
    
    if($delete_time ne "0") {
        foreach my $row ( node_expire_lastseen($delete_time) ) {
            my $mac = $row->{'mac'};
            require pf::locationlog;
            if (pf::locationlog::locationlog_update_end_mac($mac)) {
                $logger->info("mac $mac not seen for $delete_time seconds, deleting");
               node_delete($mac);
            }
        }
    }
    else {
        $logger->debug("Not deleting because the window is 0");
    }

    if($unreg_time ne "0") {
        foreach my $row ( node_unreg_lastseen($unreg_time) ) {
            my $mac = $row->{'mac'};
            $logger->info("mac $mac not seen for $unreg_time seconds, unregistering");
            node_deregister($mac);
            # not reevaluating access since the node is be inactive
        }
    }
    else {
        $logger->debug("Not unregistering because the window is 0");
    }

    return (0);
}

sub node_update_lastarp {
    my ($mac) = @_;
    db_query_execute(NODE, $node_statements, 'node_update_lastarp_sql', $mac) || return (0);
    return (1);
}

=item * node_update_bandwidth - update the bandwidth balance of a node

Updates the bandwidth balance of a node and close the violations that use the bandwidth trigger.

=cut

sub node_update_bandwidth {
    my $timer = pf::StatsD::Timer->new;
    my ($mac, $bytes) = @_;
    my $logger = get_logger();

    # Validate arguments
    $mac = clean_mac($mac);
    $logger->logdie("Invalid MAC address") unless (valid_mac($mac));
    $logger->logdie("Invalid number of bytes") unless ($bytes =~ m/^\d+$/);

    # Upate node table
    my $sth = db_query_execute(NODE, $node_statements, 'node_update_bandwidth_sql', $bytes, $mac);
    unless ($sth) {
        $logger->logdie(get_db_handle()->errstr);
    }
    elsif ($sth->rows == 1) {
        # Close any existing violation related to bandwidth
        foreach my $vid (@BANDWIDTH_EXPIRED_VIOLATIONS){
            pf::violation::violation_force_close($mac, $vid);
        }
    }
    return ($sth->rows);
}

sub node_search {
    my ($mac) = @_;
    my $query =  db_query_execute(NODE, $node_statements, 'node_search_sql', $mac) || return (0);
    my ($val) = $query->fetchrow_array();
    $query->finish();
    return ($val);

}

=item * is_node_voip

Is given MAC a VoIP Device or not?

in: mac address

=cut

sub is_node_voip {
    my ($mac) = @_;
    my $logger = get_logger();

    $logger->trace("Asked whether node $mac is a VoIP Device or not");
    my $node_info = node_attributes($mac);

    if ($node_info->{'voip'} eq $VOIP) {
        return $TRUE;
    } else {
        return $FALSE;
    }
}

=item * is_node_registered

Is given MAC registered or not?

in: mac address

=cut

sub is_node_registered {
    my ($mac) = @_;
    my $logger = get_logger();

    $logger->trace("Asked whether node $mac is registered or not");
    my $node_info = node_attributes($mac);

    if ($node_info->{'status'} eq $STATUS_REGISTERED) {
        return $TRUE;
    } else {
        return $FALSE;
    }
}

=item * node_category_handling - assigns category_id based on provided data

expects category_id or category name in the form of category => 'name' or category_id => id

returns category_id, undef if no category was required or 0 if no category is found (which is a problem)

=cut

sub _node_category_handling {
    my $timer = pf::StatsD::Timer->new({level => 7});
    my (%data) = @_;
    my $logger = get_logger();

    if (defined($data{'category_id'})) {
        # category_id has priority over category
        if (!nodecategory_exist($data{'category_id'})) {
            $logger->debug("Unable to insert node because specified category doesn't exist: ".$data{'category_id'});
            return 0;
        }

    # web node add will always push category="" so we need to explicitly ignore it
    } elsif (defined($data{'category'}) && $data{'category'} ne '')  {

        # category name into id conversion
        $data{'category_id'} = nodecategory_lookup($data{'category'});
        if (!defined($data{'category_id'}))  {
            $logger->debug("Unable to insert node because specified category doesn't exist: ".$data{'category'});
            return 0;
        }

    } else {
        # if no category is specified then we set to undef so that DBI will insert a NULL
        $data{'category_id'} = undef;
    }

    return $data{'category_id'};
}

=item is_max_reg_nodes_reached

Performs the enforcement of the maximum number of registered nodes allowed per user for a specific role.

The MAC address is currently not used.

=cut

sub is_max_reg_nodes_reached {
    my $timer = pf::StatsD::Timer->new({ level => 6 });
    my ($mac, $pid, $category, $category_id) = @_;
    my $logger = get_logger();

    # default_pid is a special case: no limit for this user
    if ($pid eq $default_pid || $pid eq $admin_pid) {
        return $FALSE;
    }
    # per-category max node per pid limit
    if ( $category || $category_id ) {
        my $category_info;
        my $nb_nodes;
        my $max_for_category;
        if ($category) {
            $category_info = nodecategory_view_by_name($category);
        } else {
            $category_info = nodecategory_view($category_id);
        }

        if ( defined($category_info->{'max_nodes_per_pid'}) ) {
            $nb_nodes = node_pid($pid, $category_info->{'category_id'});
            $max_for_category = $category_info->{'max_nodes_per_pid'};
            if ( $max_for_category == 0 || $nb_nodes < $max_for_category ) {
                return $FALSE;
            }
            $logger->info("per-role max nodes per-user limit reached: $nb_nodes are already registered to pid $pid for role "
                          . $category_info->{'name'});
        }
        else {
            $logger->warn("Specified role ".($category?$category:$category_id)." doesn't exist for pid $pid (MAC $mac); assume maximum number of registered nodes is reached");
        }
    }
    else {
        $logger->warn("No role specified or found for pid $pid (MAC $mac); assume maximum number of registered nodes is reached");
    }

    # fallback to maximum reached
    return $TRUE;
}

=item node_last_reg

Return the last mac that has been registered.
May sometimes be useful for customization.

=cut

sub node_last_reg {
    my $query =  db_query_execute(NODE, $node_statements, 'node_last_reg_sql') || return (0);
    my ($val) = $query->fetchrow_array();
    $query->finish();
    return ($val);
}

=item _cleanup_attributes

Cleans up any inconsistency in the info attributes

=cut

sub _cleanup_attributes {
    my ($info) = @_;
    my $voip = $info->{voip};
    $info->{voip} = $NO_VOIP if !defined ($voip) || $voip ne $VOIP;
    $info->{'status'} = _cleanup_status_value($info->{'status'});
}

=item fingerbank_info

Get a hash containing the fingerbank related informations for a node

=cut

sub fingerbank_info {
    my ($mac, $node_info) = @_;
    $node_info ||= pf::node::node_view($mac);

    my $info = {};

    my $cache = pf::fingerbank::cache();

    unless(defined($node_info->{device_type})){
        my $info = {};
        $info->{device_hierarchy_names} = [];
        $info->{device_hierarchy_ids} = [];
        return $info;
    }

    my $device_info = {};
    my $cache_key = 'fingerbank_info::DeviceHierarchy-'.$node_info->{device_type};
    eval {
        $device_info = $cache->compute_with_undef($cache_key, sub {
            my $info = {};

            my $device_id = pf::fingerbank::device_name_to_device_id($node_info->{device_type});
            if(defined($device_id)) {
                my $device = fingerbank::Model::Device->read($device_id, $TRUE);
                $info->{device_hierarchy_names} = [$device->{name}, map {$_->{name}} @{$device->{parents}}];
                $info->{device_hierarchy_ids} = [$device->{id}, map {$_->{id}} @{$device->{parents}}];
                $info->{device_fq} = join('/',reverse(@{$info->{device_hierarchy_names}}));
                $info->{mobile} = $device->{mobile};
            }
            return $info;
        });
        $info->{score} = $node_info->{device_score};
        $info->{version} = $node_info->{device_version};

        $info ={ (%$info, %$device_info) };
    };
    if($@) {
        get_logger->error("Unable to compute Fingerbank device information for $mac. Device profiling rules relying on it will not work. ($@)");
        $cache->remove($cache_key);
    }

    return $info;
}

=item node_defaults

create the node defaults

=cut

sub node_defaults {
    my ($mac) = @_;
    my $node_info = pf::dal::node->_defaults;
    $node_info->{mac} = $mac;
    return $node_info;
}

=item node_update_last_seen 

Update the last_seen attribute of a node to now

=cut

sub node_update_last_seen {
    my ($mac) = @_;
    $mac = clean_mac($mac);
    if($mac) {
        get_logger->debug("Updating last_seen for $mac");
        db_query_execute(NODE, $node_statements, 'node_update_last_seen_sql', $mac);
    }
}


=item check_multihost

Verify, based on open location log for a MAC, if there's more than one endpoint on a switchport.

location_info is an optionnal hashref containing switch ID, switch port and connection type. If provided, there is no need to look them up.

=cut

sub check_multihost {
    my ( $mac, $location_info ) = @_;
    my $logger = get_logger();

    return unless isenabled($Config{'advanced'}{'multihost'});

    $mac = clean_mac($mac);
    unless ( defined $location_info && ($location_info->{'switch_id'} ne "") && ($location_info->{'switch_port'} ne "") && ($location_info->{'connection_type'} ne "") ) {
        my $query = db_query_execute(NODE, $node_statements, 'node_last_locationlog_sql', $mac) || return (0);
        my $locationlog_info_ref = $query->fetchrow_hashref();
        $query->finish();
        $location_info->{'switch_id'} = $locationlog_info_ref->{'last_switch'};
        $location_info->{'switch_port'} = $locationlog_info_ref->{'last_port'};
        $location_info->{'connection_type'} = $locationlog_info_ref->{'last_connection_type'};
    }

    # There is no "multihost" capabilities for wireless or inline connections
    if ( ($location_info->{'connection_type'} =~ /^Wireless/)  || ($location_info->{'connection_type'} =~ /^Inline/) ) {
        $logger->debug("Not looking up multihost presence with MAC '$mac' since it is a '$location_info->{'connection_type'}' connection");
        return;
    }

    $logger->debug("Looking up multihost presence on switch ID '$location_info->{'switch_id'}', switch port '$location_info->{'switch_port'}' (with MAC '$mac')");

    my @locationlog = pf::locationlog::locationlog_view_open_switchport_no_VoIP($location_info->{'switch_id'}, $location_info->{'switch_port'});

    return unless scalar @locationlog > 1;

    my @mac;
    $logger->info("Found '" . scalar @locationlog . "' active devices on switch ID '$location_info->{'switch_id'}', switch port '$location_info->{'switch_port'}' (with MAC '$mac')");
    for my $entry ( @locationlog ) {
        push @mac, $entry->{'mac'};
    }

    return @mac;
}


=item node_last_reg_non_inline_on_category

Return the last mac that has been register in a specific category
May be sometimes usefull for custom

=cut

sub node_last_reg_non_inline_on_category {
    my ($mac, $category) = @_;
    my $query =  db_query_execute(NODE, $node_statements, 'node_last_reg_non_inline_on_category_sql', $mac, $category) || return (0);
    my ($val) = $query->fetchrow_array();
    $query->finish();
    return ($val);
}

=back

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

Minor parts of this file may have been contributed. See CREDITS.

=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

Copyright (C) 2005 Kevin Amorin

Copyright (C) 2005 David LaPorte

=head1 LICENSE

This program is free software; you can redistribute it and/or
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
