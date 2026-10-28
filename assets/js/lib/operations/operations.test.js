// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import {
  getOperationLabel,
  getOperationInternalName,
  getOperationResourceType,
  operationSucceeded,
  getOperationTitle,
  shouldShowOperationDisclaimer,
  STORAGE_OPERATION_DISCLAIMER_KEY,
  waiveOperationDisclaimer,
  resetOperationDisclaimer,
  describeOperationParams,
  isSchedulable,
  getOperationPermittedFor,
} from '.';

describe('operations', () => {
  it.each`
    operation                       | label
    ${'unknown'}                    | ${'unknown'}
    ${'saptune_solution_apply'}     | ${'Apply Saptune solution'}
    ${'saptune_solution_change'}    | ${'Change Saptune solution'}
    ${'cluster_maintenance_change'} | ${'Cluster maintenance change'}
    ${'cluster_resource_refresh'}   | ${'Refresh cluster resources'}
    ${'sap_instance_start'}         | ${'SAP instance start'}
    ${'sap_instance_stop'}          | ${'SAP instance stop'}
    ${'sap_system_start'}           | ${'SAP system start'}
    ${'sap_system_stop'}            | ${'SAP system stop'}
    ${'pacemaker_enable'}           | ${'Enable Pacemaker'}
    ${'pacemaker_disable'}          | ${'Disable Pacemaker'}
    ${'database_start'}             | ${'Database start'}
    ${'database_stop'}              | ${'Database stop'}
    ${'cluster_host_start'}         | ${'Set node online in cluster'}
    ${'cluster_host_stop'}          | ${'Set node offline in cluster'}
    ${'reboot'}                     | ${'Reboot host'}
  `(`should return the operation $operation label`, ({ operation, label }) => {
    expect(getOperationLabel(operation)).toBe(label);
  });

  it.each`
    operation                       | title
    ${'unknown'}                    | ${'unknown operation'}
    ${'database_start'}             | ${'Start database'}
    ${'database_stop'}              | ${'Stop database'}
    ${'sap_system_start'}           | ${'Start SAP system'}
    ${'sap_system_stop'}            | ${'Stop SAP system'}
    ${'sap_instance_start'}         | ${'Start SAP instance'}
    ${'sap_instance_stop'}          | ${'Stop SAP instance'}
    ${'saptune_solution_apply'}     | ${'Apply Saptune solution'}
    ${'saptune_solution_change'}    | ${'Change Saptune solution'}
    ${'pacemaker_enable'}           | ${'Enable Pacemaker'}
    ${'pacemaker_disable'}          | ${'Disable Pacemaker'}
    ${'cluster_maintenance_change'} | ${'Maintenance change'}
    ${'cluster_host_start'}         | ${'Set node online in cluster'}
    ${'cluster_host_stop'}          | ${'Set node offline in cluster'}
    ${'cluster_resource_refresh'}   | ${'Refresh resources'}
    ${'reboot'}                     | ${'Reboot host'}
  `(`should return the operation $operation title`, ({ operation, title }) => {
    expect(getOperationTitle(operation)).toBe(title);
  });

  it.each`
    operation                        | name
    ${'unknown'}                     | ${'unknown'}
    ${'saptuneapplysolution@v1'}     | ${'saptune_solution_apply'}
    ${'saptunechangesolution@v1'}    | ${'saptune_solution_change'}
    ${'clustermaintenancechange@v1'} | ${'cluster_maintenance_change'}
    ${'clusterresourcerefresh@v1'}   | ${'cluster_resource_refresh'}
    ${'sapinstancestart@v1'}         | ${'sap_instance_start'}
    ${'sapinstancestop@v1'}          | ${'sap_instance_stop'}
    ${'sapsystemstart@v1'}           | ${'sap_system_start'}
    ${'sapsystemstop@v1'}            | ${'sap_system_stop'}
    ${'pacemakerenable@v1'}          | ${'pacemaker_enable'}
    ${'pacemakerdisable@v1'}         | ${'pacemaker_disable'}
    ${'databasestart@v1'}            | ${'database_start'}
    ${'databasestop@v1'}             | ${'database_stop'}
    ${'crmclusterstart@v1'}          | ${'cluster_host_start'}
    ${'crmclusterstop@v1'}           | ${'cluster_host_stop'}
    ${'hostreboot@v1'}               | ${'reboot'}
  `(
    `should return the operation $operation internal name`,
    ({ operation, name }) => {
      expect(getOperationInternalName(operation)).toBe(name);
    }
  );

  it.each`
    operation                       | resourceType
    ${'unknown'}                    | ${'unknown'}
    ${'saptune_solution_apply'}     | ${'host'}
    ${'saptune_solution_change'}    | ${'host'}
    ${'cluster_maintenance_change'} | ${'cluster'}
    ${'cluster_resource_refresh'}   | ${'cluster'}
    ${'sap_instance_start'}         | ${'application_instance'}
    ${'sap_instance_stop'}          | ${'application_instance'}
    ${'sap_system_start'}           | ${'sap_system'}
    ${'sap_system_stop'}            | ${'sap_system'}
    ${'pacemaker_enable'}           | ${'cluster_host'}
    ${'pacemaker_disable'}          | ${'cluster_host'}
    ${'database_start'}             | ${'database'}
    ${'database_stop'}              | ${'database'}
    ${'cluster_host_start'}         | ${'cluster_host'}
    ${'cluster_host_stop'}          | ${'cluster_host'}
    ${'reboot'}                     | ${'host'}
  `(
    `should return the operation $operation resource type`,
    ({ operation, resourceType }) => {
      expect(getOperationResourceType(operation)).toBe(resourceType);
    }
  );

  it('should check if an operation succeeded', () => {
    expect(operationSucceeded('UPDATED')).toBeTruthy();
    expect(operationSucceeded('NOT_UPDATED')).toBeTruthy();
    expect(operationSucceeded('FAILED')).toBeFalsy();
  });
});

describe('operations disclaimer', () => {
  beforeEach(() => {
    resetOperationDisclaimer();
  });

  afterEach(() => {
    window.localStorage.removeItem(STORAGE_OPERATION_DISCLAIMER_KEY);
  });

  test('should detect whether the operation disclaimer should be shown', () => {
    expect(shouldShowOperationDisclaimer()).toBe(true);
  });

  test('should waive the operation disclaimer', () => {
    expect(shouldShowOperationDisclaimer()).toBe(true);
    waiveOperationDisclaimer();
    expect(shouldShowOperationDisclaimer()).toBe(false);
  });
});

describe('operation params', () => {
  it.each`
    params                                           | description
    ${{}}                                            | ${''}
    ${undefined}                                     | ${''}
    ${{ maintenance: true }}                         | ${'Maintenance: on'}
    ${{ maintenance: false, resource_id: 'rsc_ip' }} | ${'Maintenance: off, Resource: rsc_ip'}
    ${{ maintenance: true, node_id: 'node01' }}      | ${'Maintenance: on, Node: node01'}
    ${{ instance_type: 'abap', timeout: 300 }}       | ${'Instances: ABAP, Timeout: 5 minutes'}
    ${{ instance_type: 'all', timeout: 60 }}         | ${'Instances: All, Timeout: 1 minute'}
    ${{ host_id: 'host-id', instance_number: '00' }} | ${'Instance: 00'}
    ${{ instance_number: '01', timeout: 90 }}        | ${'Instance: 01, Timeout: 90 seconds'}
    ${{ site: 'NBG', timeout: 600 }}                 | ${'Site: NBG, Timeout: 10 minutes'}
  `(
    'should describe the operation params as "$description"',
    ({ params, description }) => {
      expect(describeOperationParams(params)).toBe(description);
    }
  );
});

describe('schedulable operations', () => {
  it.each`
    operation                       | schedulable
    ${'reboot'}                     | ${true}
    ${'cluster_maintenance_change'} | ${true}
    ${'sap_system_start'}           | ${true}
    ${'sap_system_stop'}            | ${true}
    ${'sap_instance_start'}         | ${true}
    ${'sap_instance_stop'}          | ${true}
    ${'database_start'}             | ${true}
    ${'database_stop'}              | ${true}
    ${'saptune_solution_apply'}     | ${false}
    ${'saptune_solution_change'}    | ${false}
    ${'cluster_resource_refresh'}   | ${false}
    ${'pacemaker_enable'}           | ${false}
    ${'cluster_host_start'}         | ${false}
  `(
    'should tell whether $operation can be scheduled',
    ({ operation, schedulable }) => {
      expect(isSchedulable(operation)).toBe(schedulable);
    }
  );
});

describe('operation abilities', () => {
  it.each`
    operation                       | permitted
    ${'reboot'}                     | ${['reboot:host', 'operation:all']}
    ${'cluster_maintenance_change'} | ${['maintenance_change:cluster', 'operation:all']}
    ${'sap_system_start'}           | ${['start:sap_system', 'operation:all']}
    ${'sap_system_stop'}            | ${['stop:sap_system', 'operation:all']}
    ${'sap_instance_start'}         | ${['start:application_instance', 'operation:all']}
    ${'sap_instance_stop'}          | ${['stop:application_instance', 'operation:all']}
    ${'database_start'}             | ${['start:database', 'operation:all']}
    ${'database_stop'}              | ${['stop:database', 'operation:all']}
    ${'unknown'}                    | ${['operation:all']}
  `(
    'should tell the abilities that permit $operation',
    ({ operation, permitted }) => {
      expect(getOperationPermittedFor(operation)).toEqual(permitted);
    }
  );
});
