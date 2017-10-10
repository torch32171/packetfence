package pf::file_paths;

=head1 NAME

pf::file_paths add documentation

=cut

=head1 DESCRIPTION

pf::file_paths

file paths for PacketFence
These will re-exported in pf::config

=cut

use strict;
use warnings;
use File::Spec::Functions;


our (
    #Directories
    $install_dir, $bin_dir, $conf_dir, $lib_dir, $html_dir, $users_cert_dir, $log_dir, $generated_conf_dir, $var_dir,
    $tt_compile_cache_dir, $pfconfig_cache_dir, $domains_chroot_dir, $domains_ntlm_cache_users_dir, $systemd_unit_dir, 

    #Config files
    #pf.conf.default
    $pf_default_file,
    #pf.conf
    $pf_config_file,
    #network.conf
    $network_config_file,
    #oauth2-ips.conf
    $oauth_ip_file,
    #documentation.conf variables
    $pf_doc_file,
    #floating_network_device.conf variables
    $floating_devices_config_file,
    #dhcp_fingerprints.conf variables
    $dhcp_fingerprints_file, $dhcp_fingerprints_url,
    #oui.txt variables
    $oui_file, $oui_url,
    #DHCP OMAPI key file
    $pf_omapi_key_file,
    # Local secret file for RADIUS
    $local_secret_file,
    #profiles.conf variables
    $profiles_config_file, $profiles_default_config_file,
    #Other configuraton files variables
    $switches_config_file, $switches_default_config_file,
    $violations_config_file, $violations_default_config_file,
    $authentication_config_file,
    $chi_config_file, $chi_defaults_config_file,
    $ui_config_file, $floating_devices_file, $log_config_file,
    @stored_config_files, @log_files,
    $provisioning_config_file,
    $device_registration_config_file,
    $admin_roles_config_file,
    $wrix_config_file,
    $firewall_sso_config_file,
    $pfdetect_config_file,
    $pfqueue_config_file, $pfqueue_default_config_file,
    $allowed_device_oui_file, $allowed_device_types_file,
    $apache_filters_config_file,
    $cache_control_file,
    $config_version_file,
    $log_conf_dir,
    $vlan_filters_config_file, $vlan_filters_config_default_file,
    $pfcmd_binary,
    $report_config_file, $report_default_config_file,
    $realm_config_file, $realm_default_config_file,
    $survey_config_file,
    $cluster_config_file,
    $server_cert, $server_key, $server_pem,
    $radius_server_key, $radius_server_cert, $radius_ca_cert,
    $ssl_configuration_file,
    $domain_config_file,
    $scan_config_file,
    $wmi_config_file,
    $pki_provider_config_file,
    $suricata_categories_file,
    $radius_filters_config_file,
    $billing_tiers_config_file,
    $dhcp_filters_config_file,
    $roles_config_file,
    $roles_default_config_file,
    $dns_filters_config_file, $dns_filters_default_config_file,
    $admin_audit_log,
    $violation_log,
    $portal_modules_config_file, $portal_modules_default_config_file,
    $captiveportal_templates_path,
    $captiveportal_profile_templates_path,
    $captiveportal_default_profile_templates_path,
    $maintenance_file,
    $pffilter_socket_path,
    $control_dir,
    $switch_control_dir,
    $pfmon_config_file, $pfmon_default_config_file,
    $switch_filters_config_file,
);

BEGIN {

    use Exporter ();
    our ( @ISA, @EXPORT_OK );
    @ISA = qw(Exporter);
    # Categorized by feature, pay attention when modifying
    @EXPORT_OK = qw(
        $install_dir $bin_dir $conf_dir $lib_dir $html_dir $users_cert_dir $log_dir $generated_conf_dir $var_dir
        $tt_compile_cache_dir $pfconfig_cache_dir $domains_chroot_dir $domains_ntlm_cache_users_dir $systemd_unit_dir
        $pf_default_file
        $pf_config_file
        $network_config_file
        $oauth_ip_file
        $pf_doc_file
        $floating_devices_config_file
        $dhcp_fingerprints_file $dhcp_fingerprints_url
        $oui_file $oui_url
        $pf_omapi_key_file
        $local_secret_file
        $profiles_config_file $profiles_default_config_file
        $switches_config_file $switches_default_config_file
        $violations_config_file $violations_default_config_file
        $authentication_config_file
        $chi_config_file $chi_defaults_config_file
        $ui_config_file $floating_devices_file $log_config_file
        @stored_config_files @log_files
        $provisioning_config_file
        $device_registration_config_file
        $admin_roles_config_file
        $wrix_config_file
        @stored_config_files
        $firewall_sso_config_file
        $pfdetect_config_file
        $pfqueue_config_file $pfqueue_default_config_file
        $allowed_device_oui_file $allowed_device_types_file
        $apache_filters_config_file
        $cache_control_file
        $config_version_file
        $log_conf_dir
        $vlan_filters_config_file $vlan_filters_config_default_file
        $pfcmd_binary
        $report_config_file $report_default_config_file
        $realm_config_file $realm_default_config_file
        $survey_config_file
        $cluster_config_file
        $server_cert $server_key $server_pem
        $radius_server_cert $radius_server_key $radius_ca_cert
        $ssl_configuration_file
        $domain_config_file
        $scan_config_file
        $wmi_config_file
        $pki_provider_config_file
        $suricata_categories_file
        $radius_filters_config_file
        $billing_tiers_config_file
        $dhcp_filters_config_file
        $roles_config_file
        $roles_default_config_file
        $dns_filters_config_file $dns_filters_default_config_file
        $admin_audit_log
        $violation_log
        $portal_modules_config_file $portal_modules_default_config_file
        $captiveportal_templates_path
        $captiveportal_profile_templates_path
        $captiveportal_default_profile_templates_path
        $maintenance_file
        $pffilter_socket_path
        $control_dir
        $switch_control_dir
        $pfmon_config_file $pfmon_default_config_file
        $switch_filters_config_file
    );
}

$install_dir = '/usr/local/pf';

# TODO bug#920 all application config data should use Readonly to avoid accidental post-startup alterration
$bin_dir  = catdir( $install_dir,"bin" );
$conf_dir = catdir( $install_dir,"conf" );
$var_dir  = catdir( $install_dir,"var" );
$lib_dir  = catdir( $install_dir,"lib" );
$html_dir = catdir( $install_dir,"html" );
$log_dir  = catdir( $install_dir,"logs" );
$log_conf_dir  = catdir( $conf_dir,"log.conf.d" );

$generated_conf_dir   = catdir( $var_dir,"conf");
$tt_compile_cache_dir = catdir( $var_dir,"tt_compile_cache");
$control_dir  = catdir( $var_dir, "control");
$switch_control_dir  = catdir( $var_dir, "switch_control");
$pfconfig_cache_dir = catdir( $var_dir,"cache/pfconfig");
$domains_chroot_dir = catdir( "/chroots");
$domains_ntlm_cache_users_dir = catdir( $var_dir, "cache/ntlm_cache_users");
$systemd_unit_dir   = "/usr/lib/systemd/system"; 

$pfcmd_binary = catfile( $bin_dir, "pfcmd" );

$oui_file           = catfile($conf_dir, "oui.txt");
$suricata_categories_file = catfile($conf_dir, "suricata_categories.txt");
$pf_omapi_key_file  = catfile($conf_dir, "pf_omapi_key");
$local_secret_file  = catfile($conf_dir, "local_secret");
$pf_doc_file        = catfile($conf_dir, "documentation.conf");
$oauth_ip_file      = catfile($conf_dir, "oauth2-ips.conf");
$ui_config_file     = catfile($conf_dir, "ui.conf");
$pf_config_file     = catfile($conf_dir, "pf.conf"); # TODO: Adjust. See $config_file
$pf_default_file    = catfile($conf_dir, "pf.conf.defaults"); # TODO: Adjust. See $default_config_file
$chi_config_file    = catfile($conf_dir, "chi.conf");
$chi_defaults_config_file = catfile($conf_dir, "chi.conf.defaults");
$log_config_file    = catfile($conf_dir, "log.conf");
$provisioning_config_file = catfile($conf_dir, 'provisioning.conf');
$device_registration_config_file = catfile($conf_dir,"device_registration.conf");
$pki_provider_config_file  = catfile($conf_dir,"pki_provider.conf");

$network_config_file    = catfile($conf_dir, "networks.conf");
$switches_config_file   = catfile($conf_dir, "switches.conf");
$switches_default_config_file   = catfile($conf_dir, "switches.conf.defaults");
$profiles_config_file   = catfile($conf_dir, "profiles.conf");
$profiles_default_config_file   = catfile($conf_dir, "profiles.conf.defaults");
$floating_devices_file  = catfile($conf_dir, "floating_network_device.conf");  # TODO: To be deprecated. See $floating_devices_config_file
$violations_config_file = catfile($conf_dir, "violations.conf");
$violations_default_config_file = catfile($conf_dir, "violations.conf.defaults");
$dhcp_fingerprints_file = catfile($conf_dir, "dhcp_fingerprints.conf");
$admin_roles_config_file = catfile($conf_dir, "adminroles.conf");

$violations_config_file       = catfile($conf_dir, "violations.conf");
$authentication_config_file   = catfile($conf_dir, "authentication.conf");
$floating_devices_config_file = catfile($conf_dir, "floating_network_device.conf"); # TODO: Adjust to /floating_devices.conf when $floating_devices_file will be deprecated
$wrix_config_file = catfile($conf_dir, "wrix.conf");
$allowed_device_oui_file   = catfile($conf_dir,"allowed_device_oui.txt");
$allowed_device_types_file = catfile($conf_dir,"allowed_device_types.txt");
$apache_filters_config_file = catfile($conf_dir, "apache_filters.conf");
$vlan_filters_config_file = catfile($conf_dir, "vlan_filters.conf");
$vlan_filters_config_default_file = catfile($conf_dir, "vlan_filters.conf.defaults");
$firewall_sso_config_file =  catfile($conf_dir,"firewall_sso.conf");
$pfdetect_config_file =  catfile($conf_dir,"pfdetect.conf");
$pfqueue_config_file =  catfile($conf_dir,"pfqueue.conf");
$report_config_file = catfile($conf_dir,"report.conf");
$report_default_config_file = catfile($conf_dir,"report.conf.defaults");
$pfqueue_default_config_file =  catfile($conf_dir,"pfqueue.conf.defaults");
$realm_config_file = catfile($conf_dir,"realm.conf");
$realm_default_config_file = catfile($conf_dir,"realm.conf.defaults");
$survey_config_file = catfile($conf_dir,"survey.conf");
$cluster_config_file = catfile($conf_dir,"cluster.conf");
$server_key = catfile($conf_dir,"ssl/server.key");
$server_cert = catfile($conf_dir,"ssl/server.crt");
$server_pem = catfile($conf_dir,"ssl/server.pem");
$radius_server_key = catfile($install_dir, "raddb/certs/server.key");
$radius_server_cert = catfile($install_dir, "raddb/certs/server.crt");
$radius_ca_cert = catfile($install_dir, "raddb/certs/ca.pem");
$ssl_configuration_file = catfile($generated_conf_dir, "ssl-certificates.conf");
$domain_config_file = catfile($conf_dir,"domain.conf");
$scan_config_file = catfile($conf_dir,"scan.conf");
$wmi_config_file = catfile($conf_dir,"wmi.conf");
$radius_filters_config_file = catfile($conf_dir,"radius_filters.conf");
$billing_tiers_config_file = catfile($conf_dir,"billing_tiers.conf");
$dhcp_filters_config_file = catfile($conf_dir,"dhcp_filters.conf");
$roles_config_file = catfile($conf_dir,"roles.conf");
$roles_default_config_file = catfile($conf_dir,"roles.conf.defaults");
$dns_filters_config_file = catfile($conf_dir,"dns_filters.conf");
$dns_filters_default_config_file = catfile($conf_dir,"dns_filters.conf.defaults");
$admin_audit_log = catfile($log_dir, "httpd.admin.audit.log");
$violation_log = catfile($log_dir, "violation.log");
$portal_modules_config_file = catfile($conf_dir,"portal_modules.conf");
$portal_modules_default_config_file = catfile($conf_dir,"portal_modules.conf.defaults");
$pfmon_config_file = catfile($conf_dir,"pfmon.conf");
$pfmon_default_config_file = catfile($conf_dir,"pfmon.conf.defaults");
$switch_filters_config_file = catfile($conf_dir,"switch_filters.conf"); 

$oui_url               = 'http://standards.ieee.org/regauth/oui/oui.txt';
$dhcp_fingerprints_url = 'http://www.packetfence.org/dhcp_fingerprints.conf';

$users_cert_dir = catdir( $html_dir, "captive-portal/certs");

$captiveportal_templates_path = catdir ($install_dir,"html/captive-portal/templates");
$captiveportal_profile_templates_path = catdir ($install_dir,"html/captive-portal/profile-templates");
$captiveportal_default_profile_templates_path = catdir ($captiveportal_profile_templates_path,"default");

@log_files = map {catfile($log_dir, $_)}
  qw(
  httpd.admin.access httpd.admin.catalyst httpd.admin.error httpd.admin.log
  httpd.portal.access httpd.admin.error httpd.portal.catalyst httpd.portal.log
  httpd.proxy.access httpd.proxy.error httpd.proxy.log
  httpd.proxy.reverse.access httpd.proxy.reverse.error
  httpd.webservices.access httpd.webservices.error
  packetfence.log pfbandwidthd.log pfdetect.log pfqueue.log
  pfdhcplistener.log pfdns.log pfmon.log pfconfig.log httpd.admin.audit.log
);

@stored_config_files = (
    $pf_config_file, $network_config_file,
    $switches_config_file, $violations_config_file,
    $authentication_config_file, $floating_devices_config_file,
    $dhcp_fingerprints_file, $profiles_config_file,
    $oui_file, $floating_devices_file,
    $chi_config_file,$allowed_device_oui_file,$allowed_device_types_file,
    $chi_defaults_config_file,
    $ui_config_file,$provisioning_config_file,$oauth_ip_file,$log_config_file,
    $device_registration_config_file,
    $admin_roles_config_file,$wrix_config_file,$apache_filters_config_file,
    $vlan_filters_config_file,$vlan_filters_config_default_file,$firewall_sso_config_file,$scan_config_file,
    $wmi_config_file,$pfdetect_config_file,$pfqueue_config_file,
    $pki_provider_config_file,
    $radius_filters_config_file,
    $dhcp_filters_config_file,
    $roles_config_file,
    $dns_filters_config_file,
    $pfmon_config_file,
    $switch_filters_config_file,
);

$pffilter_socket_path = catfile($var_dir, "run/pffilter.sock");

$cache_control_file = catfile($var_dir, "cache_control");

$config_version_file = catfile($var_dir, "config_version");

$maintenance_file = catfile($var_dir,"maintenance-mode");

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

