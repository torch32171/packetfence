#!/usr/bin/perl -w

use strict;
use warnings;
use diagnostics;

use Test::More;
use Test::NoWarnings;

my @php_files = (
    '/usr/local/pf/html/admin/administration/adduser.php',
    '/usr/local/pf/html/admin/administration/index.php',
    '/usr/local/pf/html/admin/administration/services.php',
    '/usr/local/pf/html/admin/administration/ui_options.php',
    '/usr/local/pf/html/admin/administration/version.php',
    '/usr/local/pf/html/admin/3rdparty/calendar/calendar.php',
    '/usr/local/pf/html/admin/check_login.php',
    '/usr/local/pf/html/admin/common.php',
    '/usr/local/pf/html/admin/common/adminperm.inc',
    '/usr/local/pf/html/admin/common/helpers.inc',
    '/usr/local/pf/html/admin/common/sajax/Sajax.php',
    '/usr/local/pf/html/admin/configuration/captive-portal.php',
    '/usr/local/pf/html/admin/configuration/fingerprint.php',
    '/usr/local/pf/html/admin/configuration/floatingnetworkdevice_add.php',
    '/usr/local/pf/html/admin/configuration/floatingnetworkdevice_edit.php',
    '/usr/local/pf/html/admin/configuration/floatingnetworkdevice.php',
    '/usr/local/pf/html/admin/configuration/index.php',
    '/usr/local/pf/html/admin/configuration/interfaces_add.php',
    '/usr/local/pf/html/admin/configuration/interfaces_edit.php',
    '/usr/local/pf/html/admin/configuration/interfaces.php',
    '/usr/local/pf/html/admin/configuration/main.php',
    '/usr/local/pf/html/admin/configuration/more_info.php',
    '/usr/local/pf/html/admin/configuration/networks_add.php',
    '/usr/local/pf/html/admin/configuration/networks_edit.php',
    '/usr/local/pf/html/admin/configuration/networks.php',
    '/usr/local/pf/html/admin/configuration/switches_add.php',
    '/usr/local/pf/html/admin/configuration/switches_edit.php',
    '/usr/local/pf/html/admin/configuration/switches.php',
    '/usr/local/pf/html/admin/configuration/useragent.php',
    '/usr/local/pf/html/admin/configuration/violation_add.php',
    '/usr/local/pf/html/admin/configuration/violation_edit.php',
    '/usr/local/pf/html/admin/configuration/violation.php',
    '/usr/local/pf/html/admin/exporter.php',
    '/usr/local/pf/html/admin/footer.php',
    '/usr/local/pf/html/admin/header.php',
    '/usr/local/pf/html/admin/index.php',
    '/usr/local/pf/html/admin/login.php',
    '/usr/local/pf/html/admin/node/add.php',
    '/usr/local/pf/html/admin/node/categories.php',
    '/usr/local/pf/html/admin/node/categories_add.php',
    '/usr/local/pf/html/admin/node/categories_edit.php',
    '/usr/local/pf/html/admin/node/edit.php',
    '/usr/local/pf/html/admin/node/index.php',
    '/usr/local/pf/html/admin/node/lookup.php',
    '/usr/local/pf/html/admin/node/useragent.php',
    '/usr/local/pf/html/admin/node/view.php',
    '/usr/local/pf/html/admin/person/add.php',
    '/usr/local/pf/html/admin/person/edit.php',
    '/usr/local/pf/html/admin/person/index.php',
    '/usr/local/pf/html/admin/person/lookup.php',
    '/usr/local/pf/html/admin/person/view.php',
    '/usr/local/pf/html/admin/printer.php',
    '/usr/local/pf/html/admin/scan/edit.php',
    '/usr/local/pf/html/admin/scan/index.php',
    '/usr/local/pf/html/admin/scan/results.php',
    '/usr/local/pf/html/admin/scan/scan.php',
    '/usr/local/pf/html/admin/status/dashboard.php',
    '/usr/local/pf/html/admin/status/grapher.php',
    '/usr/local/pf/html/admin/status/graphs.php',
    '/usr/local/pf/html/admin/status/index.php',
    '/usr/local/pf/html/admin/status/reports.php',
    '/usr/local/pf/html/admin/status/sajax-dashboard.php',
    '/usr/local/pf/html/admin/violation/add.php',
    '/usr/local/pf/html/admin/violation/edit.php',
    '/usr/local/pf/html/admin/violation/index.php',
    '/usr/local/pf/html/admin/violation/view.php',
    '/usr/local/pf/html/user/content/remediation.php',
    '/usr/local/pf/html/user/content/violations/banned_os.php',
    '/usr/local/pf/html/user/content/violations/banned_devices.php',
    '/usr/local/pf/html/user/content/violations/darknet.php',
    '/usr/local/pf/html/user/content/violations/failed_scan.php',
    '/usr/local/pf/html/user/content/violations/generic.php',
    '/usr/local/pf/html/user/content/violations/lsass.php',
    '/usr/local/pf/html/user/content/violations/nat.php',
    '/usr/local/pf/html/user/content/violations/p2p.php',
    '/usr/local/pf/html/user/content/violations/roguedhcp.php',
    '/usr/local/pf/html/user/content/violations/scanning.php',
    '/usr/local/pf/html/user/content/violations/spam.php',
    '/usr/local/pf/html/user/content/violations/system_scan.php',
    '/usr/local/pf/html/user/content/violations/trojan.php',
    '/usr/local/pf/html/user/content/violations/zotob.php',
);

# all files + no warnings
plan tests => scalar @php_files + 1;


foreach my $currentPHPFile (@php_files) {
    ok( system("/usr/bin/php -l $currentPHPFile 2>&1") == 0,
        "$currentPHPFile compiles" );
}

# TODO test for @license, @copyright and @author presence

=head1 AUTHOR

Dominik Ghel <dghel@inverse.ca>

Olivier Bilodeau <obilodeau@inverse.ca>
        
=head1 COPYRIGHT
        
Copyright (C) 2009-2011 Inverse inc.

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

