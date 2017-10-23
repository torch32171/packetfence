package pf::dal::_locationlog;

=head1 NAME

pf::dal::_locationlog - pf::dal implementation for the table locationlog

=cut

=head1 DESCRIPTION

pf::dal::_locationlog

pf::dal implementation for the table locationlog

=cut

use strict;
use warnings;

###
### pf::dal::_locationlog is auto generated any change to this file will be lost
### Instead change in the pf::dal::locationlog module
###
use base qw(pf::dal);

our @FIELD_NAMES;
our @INSERTABLE_FIELDS;
our @PRIMARY_KEYS;
our %DEFAULTS;
our %FIELDS_META;
our @COLUMN_NAMES;

BEGIN {
    @FIELD_NAMES = qw(
        id
        mac
        switch
        port
        vlan
        role
        connection_type
        connection_sub_type
        dot1x_username
        ssid
        start_time
        end_time
        switch_ip
        switch_mac
        stripped_user_name
        realm
        session_id
        ifDesc
    );

    %DEFAULTS = (
        mac => undef,
        switch => '',
        port => '',
        vlan => undef,
        role => undef,
        connection_type => '',
        connection_sub_type => undef,
        dot1x_username => '',
        ssid => '',
        start_time => '0000-00-00 00:00:00',
        end_time => '0000-00-00 00:00:00',
        switch_ip => undef,
        switch_mac => undef,
        stripped_user_name => undef,
        realm => undef,
        session_id => undef,
        ifDesc => undef,
    );

    @INSERTABLE_FIELDS = qw(
        mac
        switch
        port
        vlan
        role
        connection_type
        connection_sub_type
        dot1x_username
        ssid
        start_time
        end_time
        switch_ip
        switch_mac
        stripped_user_name
        realm
        session_id
        ifDesc
    );

    %FIELDS_META = (
        id => {
            type => 'INT',
            is_auto_increment => 1,
            is_primary_key => 1,
            is_nullable => 0,
        },
        mac => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        switch => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        port => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        vlan => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        role => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        connection_type => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        connection_sub_type => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        dot1x_username => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        ssid => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        start_time => {
            type => 'DATETIME',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        end_time => {
            type => 'DATETIME',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        switch_ip => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        switch_mac => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        stripped_user_name => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        realm => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        session_id => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        ifDesc => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
    );

    @PRIMARY_KEYS = qw(
        id
    );

    @COLUMN_NAMES = qw(
        locationlog.id
        locationlog.mac
        locationlog.switch
        locationlog.port
        locationlog.vlan
        locationlog.role
        locationlog.connection_type
        locationlog.connection_sub_type
        locationlog.dot1x_username
        locationlog.ssid
        locationlog.start_time
        locationlog.end_time
        locationlog.switch_ip
        locationlog.switch_mac
        locationlog.stripped_user_name
        locationlog.realm
        locationlog.session_id
        locationlog.ifDesc
    );

}

use Class::XSAccessor {
    accessors => \@FIELD_NAMES,
};

=head2 _defaults

The default values of locationlog

=cut

sub _defaults {
    return {%DEFAULTS};
}

=head2 field_names

Field names of locationlog

=cut

sub field_names {
    return [@FIELD_NAMES];
}

=head2 primary_keys

The primary keys of locationlog

=cut

sub primary_keys {
    return [@PRIMARY_KEYS];
}

=head2

The table name

=cut

sub table { "locationlog" }

our $FIND_SQL = do {
    my $where = join(", ", map { "$_ = ?" } @PRIMARY_KEYS);
    "SELECT * FROM `locationlog` WHERE $where;";
};

=head2 find_columns

find_columns

=cut

sub find_columns {
    return [@COLUMN_NAMES];
}

=head2 _find_one_sql

The precalculated sql to find a single row locationlog

=cut

sub _find_one_sql {
    return $FIND_SQL;
}

=head2 _updateable_fields

The updateable fields for locationlog

=cut

sub _updateable_fields {
    return [@FIELD_NAMES];
}

=head2 _insertable_fields

The insertable fields for locationlog

=cut

sub _insertable_fields {
    return [@INSERTABLE_FIELDS];
}

=head2 get_meta

Get the meta data for locationlog

=cut

sub get_meta {
    return \%FIELDS_META;
}
 
=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

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
