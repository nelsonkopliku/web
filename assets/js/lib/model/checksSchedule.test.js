// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { flatMap } from 'lodash';

import {
  DISABLED,
  FREQUENCY_UNITS,
  describeFrequency,
  frequencyLabel,
  toFrequency,
  toInterval,
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
});
