// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { maintenanceWindowFactory } from '@lib/test-utils/factories';

import {
  CHECKS_EXECUTION,
  OPERATIONS,
  activeWindows,
  checksExecutionBlockedBy,
  describeForbids,
  describeMaintenanceWindow,
  formToMaintenanceWindow,
  maintenanceWindowFormErrors,
  maintenanceWindowToForm,
  nextWindowsBoundary,
  checksExecutionBlockedReason,
} from './maintenanceWindows';

describe('maintenance windows', () => {
  it('should describe what a window forbids', () => {
    expect(describeForbids([CHECKS_EXECUTION])).toBe('Check execution');
    expect(describeForbids([OPERATIONS])).toBe('Operations');
    expect(describeForbids([OPERATIONS, CHECKS_EXECUTION])).toBe(
      'Check execution and operations'
    );
  });

  it('should describe a window in its own timezone', () => {
    const window = maintenanceWindowFactory.build({
      starts_at: '2026-11-20T22:00:00Z',
      timezone: 'Europe/Berlin',
      duration_minutes: 120,
      recurrence: null,
    });

    expect(describeMaintenanceWindow(window)).toBe(
      '20 Nov 2026, 23:00 – 01:00 (Europe/Berlin)'
    );
    expect(
      describeMaintenanceWindow({
        ...window,
        recurrence: {
          frequency: 'weekly',
          interval: 1,
          weekdays: [6],
          ends_on: '2027-01-01',
        },
      })
    ).toBe(
      'Saturdays, 23:00 – 01:00, until 01 Jan 2027 (excluded) (Europe/Berlin)'
    );
  });

  describe('form', () => {
    const now = new Date('2026-11-20T10:20:00Z');

    it('should start a new window at the next full hour, forbidding everything for one hour', () => {
      expect(maintenanceWindowToForm(null, 'Europe/Berlin', now)).toEqual({
        forbids: [CHECKS_EXECUTION, OPERATIONS],
        type: 'one_time',
        date: '2026-11-20',
        time: '12:00',
        durationValue: '1',
        durationUnit: 'hours',
        repeatValue: '1',
        repeatUnit: 'days',
        weekdays: [],
        ends: 'never',
        endsOn: '',
      });
    });

    it('should turn a window into a form in its own timezone, and back', () => {
      const window = {
        starts_at: '2026-11-20T22:00:00.000Z',
        timezone: 'Europe/Berlin',
        duration_minutes: 90,
        recurrence: {
          frequency: 'weekly',
          interval: 2,
          weekdays: [6],
          ends_on: '2027-01-01',
        },
        forbids: [OPERATIONS],
      };

      const form = maintenanceWindowToForm(
        maintenanceWindowFactory.build(window),
        'Etc/UTC'
      );

      expect(form).toEqual({
        forbids: [OPERATIONS],
        type: 'periodic',
        date: '2026-11-20',
        time: '23:00',
        durationValue: '90',
        durationUnit: 'minutes',
        repeatValue: '2',
        repeatUnit: 'weeks',
        weekdays: [6],
        ends: 'on',
        endsOn: '2027-01-01',
      });
      expect(formToMaintenanceWindow(form, 'Europe/Berlin')).toEqual(window);
    });

    it('should save a one-time window without recurrence', () => {
      expect(
        formToMaintenanceWindow(
          maintenanceWindowToForm(null, 'Etc/UTC', now),
          'Etc/UTC'
        )
      ).toEqual({
        starts_at: '2026-11-20T11:00:00.000Z',
        timezone: 'Etc/UTC',
        duration_minutes: 60,
        recurrence: null,
        forbids: [CHECKS_EXECUTION, OPERATIONS],
      });
    });

    const form = maintenanceWindowToForm(null, 'Etc/UTC', now);

    it.each`
      change                                                    | errors
      ${{}}                                                     | ${{}}
      ${{ forbids: [] }}                                        | ${{ forbids: 'Forbid check execution, operations or both' }}
      ${{ time: '10:00' }}                                      | ${{ start: 'Pick a date and time in the future' }}
      ${{ durationValue: '0' }}                                 | ${{ duration: 'Last at least 1 minute' }}
      ${{ durationValue: '745', durationUnit: 'hours' }}        | ${{ duration: 'Last at most 31 days' }}
      ${{ type: 'periodic', repeatValue: '' }}                  | ${{ repeat: 'Repeat at least every 1' }}
      ${{ type: 'periodic', ends: 'on', endsOn: '' }}           | ${{ ends: 'Pick the end date' }}
      ${{ type: 'periodic', ends: 'on', endsOn: '2026-11-20' }} | ${{ ends: 'The end date must be after the start date' }}
    `('should validate $change', ({ change, errors }) => {
      expect(
        maintenanceWindowFormErrors({ ...form, ...change }, 'Etc/UTC', { now })
      ).toEqual(errors);
    });

    it('should keep the past start of an existing window', () => {
      expect(
        maintenanceWindowFormErrors({ ...form, time: '08:00' }, 'Etc/UTC', {
          now,
          unchangedStart: { date: '2026-11-20', time: '08:00' },
        })
      ).toEqual({});
    });
  });

  describe('active windows', () => {
    const checksWindow = maintenanceWindowFactory.build({
      active: true,
      forbids: [CHECKS_EXECUTION],
    });
    const operationsWindow = maintenanceWindowFactory.build({
      active: true,
      forbids: [OPERATIONS],
    });
    const upcomingWindow = maintenanceWindowFactory.build({
      active: false,
      forbids: [CHECKS_EXECUTION, OPERATIONS],
    });

    it('should tell the active windows', () => {
      expect(
        activeWindows([checksWindow, upcomingWindow, operationsWindow])
      ).toEqual([checksWindow, operationsWindow]);
    });

    it('should tell why the checks cannot be executed now', () => {
      expect(
        checksExecutionBlockedReason([operationsWindow, checksWindow])
      ).toBe('Checks cannot be executed during a maintenance window');
      expect(checksExecutionBlockedReason([operationsWindow])).toBeNull();
    });

    it('should tell the active window that blocks the checks executions', () => {
      expect(checksExecutionBlockedBy([operationsWindow, checksWindow])).toBe(
        checksWindow
      );
      expect(
        checksExecutionBlockedBy([operationsWindow, upcomingWindow])
      ).toBeUndefined();
    });
  });

  it('should tell when the windows start or end next', () => {
    const now = new Date('2026-11-20T10:00:00Z');
    const active = maintenanceWindowFactory.build({
      active: true,
      current_occurrence: {
        starts_at: '2026-11-20T09:00:00Z',
        ends_at: '2026-11-20T12:00:00Z',
      },
      next_occurrence: null,
    });
    const upcoming = maintenanceWindowFactory.build({
      active: false,
      current_occurrence: null,
      next_occurrence: {
        starts_at: '2026-11-20T11:00:00Z',
        ends_at: '2026-11-20T13:00:00Z',
      },
    });

    expect(nextWindowsBoundary([active, upcoming], now)).toEqual(
      new Date('2026-11-20T11:00:00Z')
    );
    expect(nextWindowsBoundary([active], now)).toEqual(
      new Date('2026-11-20T12:00:00Z')
    );
    expect(nextWindowsBoundary([], now)).toBeNull();
  });
});
