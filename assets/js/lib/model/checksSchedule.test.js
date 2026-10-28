// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { flatMap } from 'lodash';

import {
  DISABLED,
  FREQUENCY_UNITS,
  describeFrequency,
  describeWindow,
  formToWindow,
  frequencyLabel,
  nextWindowBoundary,
  toFrequency,
  toInterval,
  windowFormErrors,
  windowToForm,
  executionBlockedReason,
} from './checksSchedule';

describe('checksSchedule', () => {
  it('should split an interval into a value and a unit, and back', () => {
    expect(toFrequency('15m')).toEqual({ value: 15, unit: 'minutes' });
    expect(toFrequency('6h')).toEqual({ value: 6, unit: 'hours' });
    expect(toFrequency('2w')).toEqual({ value: 2, unit: 'weeks' });
    expect(toFrequency(DISABLED)).toEqual({ value: null, unit: DISABLED });
    expect(toInterval({ value: 24, unit: 'hours' })).toBe('24h');
    expect(toInterval({ value: null, unit: DISABLED })).toBe(DISABLED);
  });

  it('should offer the frequencies of the contract', () => {
    const intervals = flatMap(FREQUENCY_UNITS, ({ values }, unit) =>
      values.map((value) => toInterval({ value, unit }))
    );

    expect(intervals).toEqual([
      '5m',
      '15m',
      '30m',
      '1h',
      '6h',
      '12h',
      '24h',
      '1w',
      '2w',
      '4w',
    ]);
    intervals.forEach((interval) =>
      expect(toInterval(toFrequency(interval))).toBe(interval)
    );
  });

  it('should label an interval', () => {
    expect(frequencyLabel('5m')).toBe('5 minutes');
    expect(frequencyLabel('1h')).toBe('1 hour');
    expect(frequencyLabel('24h')).toBe('24 hours');
    expect(frequencyLabel('1w')).toBe('1 week');
    expect(frequencyLabel(DISABLED)).toBe('Disabled');
  });

  it('should describe how often the checks are executed', () => {
    expect(describeFrequency('15m')).toBe('Every 15 minutes');
    expect(describeFrequency('1h')).toBe('Every hour');
    expect(describeFrequency('2w')).toBe('Every 2 weeks');
    expect(describeFrequency(DISABLED)).toBe('Disabled');
  });

  describe('exception window', () => {
    const window = {
      starts_at: '2026-10-12T22:00:00Z',
      timezone: 'Europe/Berlin',
      duration_minutes: 60,
      recurrence: null,
    };

    it('should describe a missing window', () => {
      expect(describeWindow(null, 'Europe/Berlin')).toBe('None');
    });

    it('should describe a one-time window in its own timezone', () => {
      expect(describeWindow(window)).toBe(
        '13 Oct 2026, 00:00 – 01:00 (Europe/Berlin)'
      );
    });

    it('should describe periodic windows', () => {
      expect(
        describeWindow({
          ...window,
          recurrence: { frequency: 'weekly', interval: 1, weekdays: [1, 5] },
        })
      ).toBe('Mondays, Fridays, 00:00 – 01:00 (Europe/Berlin)');

      expect(
        describeWindow({
          ...window,
          recurrence: { frequency: 'yearly', interval: 1 },
        })
      ).toBe('Every year on 13 Oct, 00:00 – 01:00 (Europe/Berlin)');
    });

    it('should start a new window at the next full hour, lasting one hour', () => {
      expect(
        windowToForm(null, 'Etc/UTC', new Date('2026-10-12T10:20:00Z'))
      ).toEqual({
        type: 'none',
        date: '2026-10-12',
        time: '11:00',
        durationValue: '1',
        durationUnit: 'hours',
        repeatValue: '1',
        repeatUnit: 'days',
        weekdays: [],
      });
      expect(formToWindow({ type: 'none' }, 'Etc/UTC')).toBeNull();
    });

    it('should turn a window into a form in its own timezone, and back', () => {
      const periodic = {
        starts_at: '2026-10-12T22:00:00.000Z',
        timezone: 'Europe/Berlin',
        duration_minutes: 90,
        recurrence: { frequency: 'weekly', interval: 1, weekdays: [1, 5] },
      };

      const form = windowToForm(periodic, 'Etc/UTC');

      expect(form).toEqual({
        type: 'periodic',
        date: '2026-10-13',
        time: '00:00',
        durationValue: '90',
        durationUnit: 'minutes',
        repeatValue: '1',
        repeatUnit: 'weeks',
        weekdays: [1, 5],
      });

      expect(formToWindow(form, 'Europe/Berlin')).toEqual(periodic);
    });

    it('should tell when the window starts or ends next', () => {
      expect(nextWindowBoundary(null)).toBeNull();
      expect(
        nextWindowBoundary(window, new Date('2026-10-12T21:00:00Z'))
      ).toEqual(new Date('2026-10-12T22:00:00Z'));
      expect(
        nextWindowBoundary(window, new Date('2026-10-12T22:10:00Z'))
      ).toEqual(new Date('2026-10-12T23:00:00Z'));
      expect(
        nextWindowBoundary(window, new Date('2026-10-13T00:00:00Z'))
      ).toBeNull();
    });
  });

  describe('exception window validation', () => {
    const now = new Date('2026-10-12T10:00:00Z');
    const form = {
      type: 'one_time',
      date: '2026-10-12',
      time: '11:00',
      durationValue: '1',
      durationUnit: 'hours',
      repeatValue: '1',
      repeatUnit: 'days',
      weekdays: [],
    };

    it.each`
      change                                   | errors
      ${{}}                                    | ${{}}
      ${{ type: 'none', date: '2020-01-01' }}  | ${{}}
      ${{ time: '09:00' }}                     | ${{ start: 'Pick a date and time in the future' }}
      ${{ date: '' }}                          | ${{ start: 'Pick a date and a start time' }}
      ${{ durationValue: '0' }}                | ${{ duration: 'Last at least 1 minute' }}
      ${{ type: 'periodic', repeatValue: '' }} | ${{ repeat: 'Repeat at least every 1' }}
    `('should validate $change', ({ change, errors }) => {
      expect(
        windowFormErrors({ ...form, ...change }, 'Etc/UTC', { now })
      ).toEqual(errors);
    });

    it('should keep the past start of an existing window', () => {
      expect(
        windowFormErrors({ ...form, time: '09:00' }, 'Etc/UTC', {
          now,
          unchangedStart: { date: '2026-10-12', time: '09:00' },
        })
      ).toEqual({});
    });
  });

  it('should tell why the checks cannot be executed now', () => {
    expect(executionBlockedReason(null)).toBeNull();
    expect(executionBlockedReason({ in_exception_window: false })).toBeNull();
    expect(executionBlockedReason({ in_exception_window: true })).toBe(
      'Checks cannot be executed during exception window'
    );
  });
});
