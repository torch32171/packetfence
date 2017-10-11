package pf::role::pool;

=head1 NAME

pf::role::pool - Object oriented module for VLAN pool

=head1 SYNOPSIS

The pf::role::pool module contains the functions necessary for the VLAN Pool.

=cut

use strict;
use warnings;

use Log::Log4perl;

use pf::config;
use pf::util;
use pf::log();

use pf::node;

use Number::Range;

=head1 SUBROUTINES

Warning: The list of subroutine is incomplete

=cut

=head2 new

Constructor.

=cut

sub new {
    my $logger =  pf::log::get_logger();
    $logger->debug("instantiating new pf::role::pool object");
    my ( $class, %argv ) = @_;
    my $this = bless {}, $class;
    return $this;
}

sub getVlanFromPool {
    my ($self, $args) = @_;
    my $logger =  pf::log::get_logger();

    return $pool_args->{'vlan'} if $self->rangeValidator($args->{'vlan'});
    my $range = Number::Range->new($args->{'vlan'});

    my $vlan = $self->getRoundRobin($args, $range);
    return $vlan;
}

=head2 rangeValidator

Validate the range definition
Should be something like that 20..23 or 20..23,27..30

=cut

sub rangeValidator {
    my ($self, $range) =@_;
    my $rangesep = qr/(?:\.\.)/;
    my $sectsep  = qr/(?:\s|,)/;
    my $validation = qr/(?:
         [^0-9,. -]|
         $rangesep$sectsep|
         $sectsep$rangesep|
         \d-\d|
         ^$sectsep|
         ^$rangesep|
         $sectsep$|
         $rangesep$
         )/x;
    return 1 if ($range =~ m/$validation/g);
    return 0;
}


=head2 getRoundRobin

Return the vlan id based on the last registered device + 1
First test if the last_vlan of the device is in the range then use it
Else get the last registered device vlan and add + 1 (+1 in the range)

=cut

sub getRoundRobin {
    my ($self, $args, $range) = @_;
    my $logger =  pf::log::get_logger();

    my $vlan_count = $range->size;
    my $node_info_complete = node_view($args->{'mac'});
    if ( defined($node_info_complete->{'last_vlan'}) && $range->inrange($node_info_complete->{'last_vlan'}) ) {
        $logger->debug("NODE LAST VLAN ".$node_info_complete->{'last_vlan'});
        return ($node_info_complete->{'last_vlan'});
    }
    my $last_reg_mac = node_last_reg_non_inline_on_category($args->{'mac'}, $args->{'user_role'});
    my @array = $range->range;

    if (defined($last_reg_mac) && $last_reg_mac ne '') {
        my $new_vlan;
        my $last_reg_mac_info = node_view($last_reg_mac);
        $logger->debug("LAST VLAN FROM REG $last_reg_mac_info->{'last_vlan'}");
        if (defined($last_reg_mac_info->{'last_vlan'})) {
            my ( $index )= grep { $array[$_] =~ /^$last_reg_mac_info->{'last_vlan'}$/ } 0..$#array;
            if( 0 <= $index && $index <= $vlan_count) {
                $new_vlan = ($index + 1) % $vlan_count;
            } else {
               $new_vlan = 0;
            }
        } else {
            $new_vlan = 0;
        }
        return ($array[$new_vlan]);
    } else {
        $logger->warn("Welcome to the workflow, you are the first registered node");
        return ($array[0]);
    }
}


=head2 getVlanByUsername

Return the vlan id based on a hash of the username

=cut

sub getVlanByUsername {
    my ( $self, $args, $range ) = @_;

    my $index = unpack( "%16C*", $args->{'node_info'}->{'pid'} ) + length($args->{'node_info'}->{'pid'});

    my $vlan_count = $range->size;
    my @array = $range->range;
    my $new_vlan = ($index + 1) % $vlan_count;
    return ($array[$new_vlan]);

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

# vim: set shiftwidth=4:
# vim: set expandtab:
# vim: set backspace=indent,eol,start:
