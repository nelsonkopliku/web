// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { difference } from 'lodash';
import { abilityFactory } from '@lib/test-utils/factories/users';
import {
  ACTIVITY_TYPES,
  allowedActivities,
  LOGIN_ATTEMPT,
  PROFILE_UPDATE,
  USER_CREATION,
  USER_DELETION,
  USER_MODIFICATION,
  PERSONAL_ACCESS_TOKEN_CREATION,
  PERSONAL_ACCESS_TOKEN_DELETION,
  PERSONAL_ACCESS_TOKEN_ADMIN_DELETION,
  AI_CONFIGURATION_CREATION,
  AI_CONFIGURATION_MODIFICATION,
  AI_CONFIGURATION_DELETION,
  OPERATION_COMPLETED,
  TESTING_ALERTING_SETTINGS,
  availableResourceNameKeys,
  resourceNameFromMetadata,
  resourceTypes,
  taggingResourceType,
  operationResourceType,
  checkCustomizationResourceType,
  toMessage,
  toResource,
} from './activityLog';
import {
  SAPTUNE_SOLUTION_APPLY,
  OPERATION_REQUEST_FAILED,
} from '@lib/operations';

const nonUserManagementActivities = difference(ACTIVITY_TYPES, [
  LOGIN_ATTEMPT,
  USER_CREATION,
  USER_MODIFICATION,
  USER_DELETION,
  PROFILE_UPDATE,
  PERSONAL_ACCESS_TOKEN_CREATION,
  PERSONAL_ACCESS_TOKEN_DELETION,
  PERSONAL_ACCESS_TOKEN_ADMIN_DELETION,
  AI_CONFIGURATION_CREATION,
  AI_CONFIGURATION_MODIFICATION,
  AI_CONFIGURATION_DELETION,
]);

describe('activityLog', () => {
  it.each`
    userAbilities                         | hasUserMgmtActivities
    ${[]}                                 | ${false}
    ${[['all', 'all']]}                   | ${true}
    ${[['all', 'users']]}                 | ${true}
    ${[['all', 'all'], ['all', 'users']]} | ${true}
    ${[['all', 'all'], ['foo', 'bar']]}   | ${true}
    ${[['all', 'users'], ['bar', 'baz']]} | ${true}
    ${[['baz', 'qux'], ['bar', 'baz']]}   | ${false}
    ${[['baz', 'qux']]}                   | ${false}
    ${[['qux', 'ber']]}                   | ${false}
  `(
    'should return relevant activities for the given user abilities',
    ({ userAbilities, hasUserMgmtActivities }) => {
      const abilities = userAbilities.map(([name, resource]) =>
        abilityFactory.build({ name, resource })
      );

      const relevantActivities = allowedActivities(abilities).map(
        ([key, _value]) => key
      );

      hasUserMgmtActivities
        ? expect(relevantActivities).toEqual(ACTIVITY_TYPES)
        : expect(relevantActivities).toEqual(nonUserManagementActivities);
    }
  );

  describe('resource name detection', () => {
    it('should expose available resource name keys', () => {
      expect(availableResourceNameKeys).toStrictEqual([
        'hostname',
        'name',
        'sid',
      ]);
    });

    it.each`
      resourceType        | metadata                                    | expectedResourceName
      ${'host'}           | ${{ foo: 'bar', hostname: 'an_hostname' }}  | ${'an_hostname'}
      ${'cluster'}        | ${{ foo: 'bar', name: 'a_clustername' }}    | ${'a_clustername'}
      ${'database'}       | ${{ foo: 'bar', sid: 'a_database_sid' }}    | ${'a_database_sid'}
      ${'sap_system'}     | ${{ foo: 'bar', sid: 'an_sap_system_sid' }} | ${'an_sap_system_sid'}
      ${'not_a_resource'} | ${{ foo: 'bar', sid: 'sid' }}               | ${'unrecognized resource'}
    `(
      'should extract correct resource name from metadata, when possible',
      ({ resourceType, metadata, expectedResourceName }) => {
        expect(resourceNameFromMetadata(resourceType, metadata)).toBe(
          expectedResourceName
        );
      }
    );

    it.each(resourceTypes)(
      'should gracefully handle missing resource names',
      (resourceType) => {
        expect(resourceNameFromMetadata(resourceType, { foo: 'bar' })).toBe(
          'unrecognized resource'
        );
      }
    );
  });

  describe('resource type resolution', () => {
    it('should fallback to default resolution when unable to determine resource type', () => {
      [
        {
          metadata: {},
        },
        {
          metadata: null,
        },
        {
          metadata: undefined,
        },
        {},
      ].forEach((entry) => {
        expect(taggingResourceType(entry)).toBe(
          'Unable to determine resource type'
        );
        expect(operationResourceType(entry)).toBe(
          'Unable to determine operation type'
        );
        expect(checkCustomizationResourceType(entry)).toBe(
          'Unable to determine target type'
        );
      });
    });

    it('should resolve tagging resource types', () => {
      const scenarios = [
        {
          entry: {
            metadata: {
              resource_type: 'host',
            },
          },
          expected: 'Host',
        },
        {
          entry: {
            metadata: {
              resource_type: 'cluster',
            },
          },
          expected: 'Cluster',
        },
        {
          entry: {
            metadata: {
              resource_type: 'database',
            },
          },
          expected: 'Database',
        },
        {
          entry: {
            metadata: {
              resource_type: 'sap_system',
            },
          },
          expected: 'SAP System',
        },
      ];

      scenarios.forEach(({ entry, expected }) => {
        expect(taggingResourceType(entry)).toBe(expected);
      });
    });

    it('should resolve operation resource types', () => {
      const scenarios = [
        {
          entry: {
            metadata: {
              operation: SAPTUNE_SOLUTION_APPLY,
            },
          },
          expected: 'Host',
        },
      ];

      scenarios.forEach(({ entry, expected }) => {
        expect(operationResourceType(entry)).toBe(expected);
      });
    });

    it('should resolve checks customization resource types', () => {
      const scenarios = [
        {
          entry: {
            metadata: {
              target_type: 'host',
            },
          },
          expected: 'Host',
        },
        {
          entry: {
            metadata: {
              target_type: 'cluster',
            },
          },
          expected: 'Cluster',
        },
        {
          entry: {
            metadata: {
              target_type: 'database',
            },
          },
          expected: 'Database',
        },
        {
          entry: {
            metadata: {
              target_type: 'sap_system',
            },
          },
          expected: 'SAP System',
        },
      ];

      scenarios.forEach(({ entry, expected }) => {
        expect(checkCustomizationResourceType(entry)).toBe(expected);
      });
    });

    describe('scheduling activities', () => {
      const rebootSchedule = {
        correlation_id: 'schedule-id',
        target_type: 'host',
        host_id: 'host-id',
        hostname: 'vmhana01',
        operation: 'reboot',
        params: {},
        starts_at: '2026-11-20T02:00:00Z',
        timezone: 'Europe/Berlin',
        recurrence: null,
      };

      const maintenanceSchedule = {
        correlation_id: 'schedule-id',
        target_type: 'cluster',
        cluster_id: 'cluster-id',
        name: 'hana_cluster',
        operation: 'cluster_maintenance_change',
        params: { maintenance: true },
        starts_at: '2026-11-21T02:00:00Z',
        timezone: 'Europe/Berlin',
        recurrence: { frequency: 'weekly', interval: 1, weekdays: [6] },
      };

      it.each`
        type                               | metadata               | message
        ${'operation_scheduled'}           | ${rebootSchedule}      | ${'Operation Reboot host scheduled for vmhana01: 20 Nov 2026 at 03:00 (Europe/Berlin)'}
        ${'operation_scheduled'}           | ${maintenanceSchedule} | ${'Operation Cluster maintenance change (Maintenance: on) scheduled for hana_cluster: Saturdays at 03:00 (Europe/Berlin)'}
        ${'operation_schedule_changed'}    | ${rebootSchedule}      | ${'Schedule of operation Reboot host for vmhana01 changed: 20 Nov 2026 at 03:00 (Europe/Berlin)'}
        ${'operation_schedule_cancelled'}  | ${maintenanceSchedule} | ${'Schedule of operation Cluster maintenance change (Maintenance: on) for hana_cluster cancelled'}
        ${'scheduled_operation_requested'} | ${rebootSchedule}      | ${'Scheduled operation Reboot host requested for vmhana01'}
      `('should describe a $type entry', ({ type, metadata, message }) => {
        expect(toMessage({ type, metadata })).toBe(message);
      });

      it('should tell the run of a scheduled operation, in the timezone of the schedule', () => {
        const run = { ...rebootSchedule, run_at: '2026-11-20T02:00:00Z' };

        expect(
          toMessage({ type: 'scheduled_operation_requested', metadata: run })
        ).toBe(
          'Scheduled operation Reboot host requested for vmhana01, planned for 20 Nov 2026, 03:00:00 (Europe/Berlin)'
        );
        expect(
          toMessage({
            type: 'scheduled_operation_request_failed',
            metadata: { ...run, reason: 'policies' },
          })
        ).toBe(
          'Scheduled operation Reboot host for vmhana01, planned for 20 Nov 2026, 03:00:00 (Europe/Berlin), not requested: the operation policies did not pass'
        );
      });

      it('should tell the run of a refused scheduled operation without timezone in UTC', () => {
        expect(
          toMessage({
            type: 'scheduled_operation_request_failed',
            metadata: {
              host_id: 'host-id',
              hostname: 'vmhana01',
              operation: 'reboot',
              run_at: '2026-11-20T02:00:00Z',
              reason: 'already_running',
            },
          })
        ).toBe(
          'Scheduled operation Reboot host for vmhana01, planned for 20 Nov 2026, 02:00:00 (Etc/UTC), not requested: another operation was running'
        );
      });

      it('should describe a scheduling entry without target name and timing', () => {
        expect(
          toMessage({
            type: 'operation_scheduled',
            metadata: { operation: 'reboot' },
          })
        ).toBe('Operation Reboot host scheduled');
      });

      it.each`
        reason                | why
        ${'not_available'}    | ${'Trento was not available at the scheduled time'}
        ${'policies'}         | ${'the operation policies did not pass'}
        ${'already_running'}  | ${'another operation was running'}
        ${'target_not_found'} | ${'the target is gone'}
        ${'unexpected'}       | ${'unexpected'}
      `(
        'should tell why a scheduled operation was not requested: $reason',
        ({ reason, why }) => {
          expect(
            toMessage({
              type: 'scheduled_operation_request_failed',
              metadata: { ...rebootSchedule, reason },
            })
          ).toBe(
            `Scheduled operation Reboot host for vmhana01 not requested: ${why}`
          );
        }
      );

      it('should resolve the resource of a schedule from its target', () => {
        expect(
          toResource({ type: 'operation_scheduled', metadata: rebootSchedule })
        ).toBe('Host');
        expect(
          toResource({
            type: 'operation_schedule_cancelled',
            metadata: {
              operation: 'sap_instance_start',
              target_type: 'sap_system',
            },
          })
        ).toBe('SAP System');
        expect(
          toResource({
            type: 'scheduled_operation_requested',
            metadata: { operation: 'database_start' },
          })
        ).toBe('Database');
      });
    });

    describe('checks execution frequency activities', () => {
      it.each`
        metadata                    | message
        ${{ interval: '15m' }}      | ${'Check execution frequency changed to every 15 minutes'}
        ${{ interval: 'disabled' }} | ${'Periodic check executions disabled'}
        ${{}}                       | ${'Check execution settings updated'}
      `(
        'should describe the global settings change $metadata',
        ({ metadata, message }) => {
          expect(
            toMessage({ type: 'checks_execution_settings_updated', metadata })
          ).toBe(message);
          expect(
            toResource({ type: 'checks_execution_settings_updated', metadata })
          ).toBe('Check Execution Settings');
        }
      );

      it.each`
        type                                  | metadata                                                      | message
        ${'host_checks_frequency_changed'}    | ${{ host_id: 'id', hostname: 'vmhana01', interval: '6h' }}    | ${'Check execution frequency of host vmhana01 changed to every 6 hours'}
        ${'host_checks_frequency_changed'}    | ${{ host_id: 'id', hostname: 'vmhana01', interval: null }}    | ${'Check execution frequency of host vmhana01 reset to the system setting'}
        ${'host_checks_frequency_changed'}    | ${{ host_id: 'id', interval: 'disabled' }}                    | ${'Periodic check executions of the host disabled'}
        ${'cluster_checks_frequency_changed'} | ${{ cluster_id: 'id', name: 'hana_cluster', interval: '1w' }} | ${'Check execution frequency of cluster hana_cluster changed to every week'}
        ${'cluster_checks_frequency_changed'} | ${{ cluster_id: 'id', name: 'hana_cluster', interval: null }} | ${'Check execution frequency of cluster hana_cluster reset to the system setting'}
      `(
        'should describe a $type entry with interval $metadata.interval',
        ({ type, metadata, message }) => {
          expect(toMessage({ type, metadata })).toBe(message);
        }
      );

      it('should resolve the resource of a target frequency change', () => {
        expect(
          toResource({ type: 'host_checks_frequency_changed', metadata: {} })
        ).toBe('Host');
        expect(
          toResource({ type: 'cluster_checks_frequency_changed', metadata: {} })
        ).toBe('Cluster');
      });
    });

    it('should resolve operation completed message', () => {
      const scenarios = [
        { result: OPERATION_REQUEST_FAILED, message: 'request failed' },
        { result: 'UPDATED', message: 'completed' },
      ];

      scenarios.forEach(({ result, message }) => {
        const entry = {
          type: OPERATION_COMPLETED,
          metadata: {
            operation: SAPTUNE_SOLUTION_APPLY,
            result,
          },
        };
        expect(toMessage(entry)).toBe(
          `Operation Apply Saptune solution ${message}`
        );
      });
    });

    it.each`
      metadata                                                        | expectedMessage
      ${{ result: 'success' }}                                        | ${'Test email delivery succeeded'}
      ${{ result: 'failure', reason: 'Email alerting is disabled.' }} | ${'Test email delivery failed'}
    `(
      'should resolve alerting test email message',
      ({ metadata, expectedMessage }) => {
        expect(toMessage({ type: TESTING_ALERTING_SETTINGS, metadata })).toBe(
          expectedMessage
        );
      }
    );
  });
});
