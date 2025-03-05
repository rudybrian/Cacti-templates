#!/usr/bin/env php
<?php
/*
 +-------------------------------------------------------------------------+
 | Copyright (C) 2004-2025 The Cacti Group                                 |
 |                                                                         |
 | This program is free software; you can redistribute it and/or           |
 | modify it under the terms of the GNU General Public License             |
 | as published by the Free Software Foundation; either version 2          |
 | of the License, or (at your option) any later version.                  |
 |                                                                         |
 | This program is distributed in the hope that it will be useful,         |
 | but WITHOUT ANY WARRANTY; without even the implied warranty of          |
 | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           |
 | GNU General Public License for more details.                            |
 +-------------------------------------------------------------------------+
 | Cacti: The Complete RRDtool-based Graphing Solution                     |
 +-------------------------------------------------------------------------+
 | This code is designed, written, and maintained by the Cacti Group. See  |
 | about.php and/or the AUTHORS file for specific developer information.   |
 +-------------------------------------------------------------------------+
 | http://www.cacti.net/                                                   |
 +-------------------------------------------------------------------------+
*/

global $config;

if (!isset($called_by_script_server)) {
	include_once(dirname(__FILE__) . '/../include/cli_check.php');
	include_once(dirname(__FILE__) . '/../lib/snmp.php');

	array_shift($_SERVER['argv']);
	print call_user_func_array('ss_idrac_status', $_SERVER['argv']);
} else {
	include_once(dirname(__FILE__) . '/../lib/snmp.php');
}

function ss_idrac_status ($host_id = '') {
	global $environ, $poller_id, $config;

	$oids = array(
		'glob_system_status'   => '.1.3.6.1.4.1.674.10892.5.2.1.0',
		'glob_storage_status'  => '.1.3.6.1.4.1.674.10892.5.2.3.0',
		'power_state'          => '.1.3.6.1.4.1.674.10892.5.2.4.0',
		'comb_power_supply'    => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.9.1',
		'comb_voltage'         => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.12.1',
		'comb_cooling_dev'     => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.21.1',
		'comb_temperature'     => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.24.1',
		'comb_memory'          => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.27.1',
		'comb_cooling_unit'    => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.44.1',
		'comb_processor'       => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.50.1',
		'comb_battery'         => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.52.1',
		'comb_sdcard'          => '.1.3.6.1.4.1.674.10892.5.4.200.10.1.54.1',
	);

	if (empty($host_id) || $host_id === NULL || !is_numeric($host_id))  {
		$output = '';

		foreach ($oids as $key => $value) {
			$output.= $key . ':0 ';
		}
		return $output . PHP_EOL;
	}

	$host = db_fetch_row_prepared('SELECT *
		FROM host
		WHERE id = ?',
		array($host_id));

	$result = '';

	foreach ($oids as $name => $oid) {
		$x = cacti_snmp_get($host['hostname'],
		$host['snmp_community'],
		$oid,
		$host['snmp_version'],
		$host['snmp_username'],
		$host['snmp_password'],
		$host['snmp_auth_protocol'],
		$host['snmp_priv_passphrase'],
		$host['snmp_priv_protocol'],
		$host['snmp_context'],
		$host['snmp_port'],
		$host['snmp_timeout'],
		$host['ping_retries'],
		SNMP_POLLER,
		$host['snmp_engine_id']);

		if (is_numeric($x)) {
			$result .= $name . ':' . $x . ' '; 
		} else {
			$result .= $name . ':0 ';
		}
	}
	return $result;
}

?>