package pf::dal::_dhcp_option82_history;

=head1 NAME

pf::dal::_dhcp_option82_history - pf::dal implementation for the table dhcp_option82_history

=cut

=head1 DESCRIPTION

pf::dal::_dhcp_option82_history

pf::dal implementation for the table dhcp_option82_history

=cut

use strict;
use warnings;

###
### pf::dal::_dhcp_option82_history is auto generated any change to this file will be lost
### Instead change in the pf::dal::dhcp_option82_history module
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
        dhcp_option82_history_id
        mac
        created_at
        option82_switch
        switch_id
        port
        vlan
        circuit_id_string
        module
        host
    );

    %DEFAULTS = (
        mac => '',
        option82_switch => undef,
        switch_id => undef,
        port => '',
        vlan => undef,
        circuit_id_string => undef,
        module => undef,
        host => undef,
    );

    @INSERTABLE_FIELDS = qw(
        mac
        option82_switch
        switch_id
        port
        vlan
        circuit_id_string
        module
        host
    );

    %FIELDS_META = (
        dhcp_option82_history_id => {
            type => 'INT',
            is_auto_increment => 1,
            is_primary_key => 1,
            is_nullable => 0,
        },
        mac => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        created_at => {
            type => 'TIMESTAMP',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 0,
        },
        option82_switch => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        switch_id => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
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
        circuit_id_string => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        module => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
        host => {
            type => 'VARCHAR',
            is_auto_increment => 0,
            is_primary_key => 0,
            is_nullable => 1,
        },
    );

    @PRIMARY_KEYS = qw(
        dhcp_option82_history_id
    );

    @COLUMN_NAMES = qw(
        dhcp_option82_history.dhcp_option82_history_id
        dhcp_option82_history.mac
        dhcp_option82_history.created_at
        dhcp_option82_history.option82_switch
        dhcp_option82_history.switch_id
        dhcp_option82_history.port
        dhcp_option82_history.vlan
        dhcp_option82_history.circuit_id_string
        dhcp_option82_history.module
        dhcp_option82_history.host
    );

}

use Class::XSAccessor {
    accessors => \@FIELD_NAMES,
};

=head2 _defaults

The default values of dhcp_option82_history

=cut

sub _defaults {
    return {%DEFAULTS};
}

=head2 field_names

Field names of dhcp_option82_history

=cut

sub field_names {
    return [@FIELD_NAMES];
}

=head2 primary_keys

The primary keys of dhcp_option82_history

=cut

sub primary_keys {
    return [@PRIMARY_KEYS];
}

=head2

The table name

=cut

sub table { "dhcp_option82_history" }

our $FIND_SQL = do {
    my $where = join(", ", map { "$_ = ?" } @PRIMARY_KEYS);
    "SELECT * FROM `dhcp_option82_history` WHERE $where;";
};

=head2 find_columns

find_columns

=cut

sub find_columns {
    return [@COLUMN_NAMES];
}

=head2 _find_one_sql

The precalculated sql to find a single row dhcp_option82_history

=cut

sub _find_one_sql {
    return $FIND_SQL;
}

=head2 _updateable_fields

The updateable fields for dhcp_option82_history

=cut

sub _updateable_fields {
    return [@FIELD_NAMES];
}

=head2 _insertable_fields

The insertable fields for dhcp_option82_history

=cut

sub _insertable_fields {
    return [@INSERTABLE_FIELDS];
}

=head2 get_meta

Get the meta data for dhcp_option82_history

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
