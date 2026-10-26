// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import {
  describeOccurrences,
  formToRecurrence,
  nextFullHourIn,
  recurrenceToForm,
  startsInThePast,
} from './recurrence';

const schedule = {
  starts_at: '2026-10-24T01:00:00Z',
  timezone: 'Europe/Berlin',
  recurrence: null,
};

describe('recurrence', () => {
  describe('describeOccurrences', () => {
    it('should describe a one-time occurrence in the given timezone', () => {
      expect(describeOccurrences(schedule, 'Europe/Berlin')).toBe(
        '24 Oct 2026 at 03:00'
      );
      expect(describeOccurrences(schedule, 'America/New_York')).toBe(
        '23 Oct 2026 at 21:00'
      );
    });

    it('should describe periodic occurrences with their end', () => {
      expect(
        describeOccurrences(
          {
            ...schedule,
            recurrence: {
              frequency: 'weekly',
              interval: 2,
              weekdays: [6, 7],
              max_occurrences: 5,
            },
          },
          'Europe/Berlin'
        )
      ).toBe('Every 2 weeks on Saturdays, Sundays at 03:00, 5 times');

      expect(
        describeOccurrences(
          {
            ...schedule,
            recurrence: {
              frequency: 'daily',
              interval: 1,
              ends_on: '2027-06-01',
            },
          },
          'Europe/Berlin'
        )
      ).toBe('Every day at 03:00, until 01 Jun 2027 (excluded)');
    });

    it('should describe weekly occurrences on the day of the start without weekdays', () => {
      expect(
        describeOccurrences(
          {
            ...schedule,
            recurrence: { frequency: 'weekly', interval: 1, weekdays: [] },
          },
          'Europe/Berlin'
        )
      ).toBe('Saturdays at 03:00');
    });

    it('should describe monthly and yearly occurrences on the day of the start', () => {
      expect(
        describeOccurrences(
          { ...schedule, recurrence: { frequency: 'monthly', interval: 1 } },
          'Europe/Berlin'
        )
      ).toBe('Every month on day 24 at 03:00');

      expect(
        describeOccurrences(
          { ...schedule, recurrence: { frequency: 'yearly', interval: 2 } },
          'Europe/Berlin'
        )
      ).toBe('Every 2 years on 24 Oct at 03:00');
    });
  });

  describe('recurrence form', () => {
    const form = {
      date: '2026-10-24',
      time: '03:00',
      repeatValue: '2',
      repeatUnit: 'weeks',
      weekdays: [6, 7],
    };

    it('should turn a periodic form into a schedule in the given timezone', () => {
      expect(formToRecurrence(form, 'Europe/Berlin', true)).toEqual({
        starts_at: '2026-10-24T01:00:00.000Z',
        timezone: 'Europe/Berlin',
        recurrence: { frequency: 'weekly', interval: 2, weekdays: [6, 7] },
      });
    });

    it('should drop the weekdays of a periodic form that does not repeat weekly', () => {
      expect(
        formToRecurrence({ ...form, repeatUnit: 'days' }, 'Etc/UTC', true)
      ).toEqual({
        starts_at: '2026-10-24T03:00:00.000Z',
        timezone: 'Etc/UTC',
        recurrence: { frequency: 'daily', interval: 2, weekdays: [] },
      });
    });

    it('should turn a one-time form into a schedule without recurrence', () => {
      expect(formToRecurrence(form, 'Etc/UTC', false)).toEqual({
        starts_at: '2026-10-24T03:00:00.000Z',
        timezone: 'Etc/UTC',
        recurrence: null,
      });
    });

    it('should turn a schedule into a form in the given timezone', () => {
      expect(
        recurrenceToForm(
          {
            ...schedule,
            recurrence: { frequency: 'weekly', interval: 2, weekdays: [6, 7] },
          },
          'Europe/Berlin'
        )
      ).toEqual(form);
    });
  });

  describe('start of a new schedule', () => {
    it('should start at the next full hour in the given timezone', () => {
      const now = new Date('2026-10-24T22:30:00Z');

      expect(nextFullHourIn('Europe/Berlin', now)).toEqual({
        date: '2026-10-25',
        time: '01:00',
      });
      expect(nextFullHourIn('Etc/UTC', now)).toEqual({
        date: '2026-10-24',
        time: '23:00',
      });
      expect(nextFullHourIn('Asia/Kolkata', now)).toEqual({
        date: '2026-10-25',
        time: '05:00',
      });
    });

    it('should move to the next day at the end of a day', () => {
      expect(
        nextFullHourIn('Etc/UTC', new Date('2026-12-31T23:00:00Z'))
      ).toEqual({ date: '2027-01-01', time: '00:00' });
    });

    it('should tell whether a date and time are in the past in the given timezone', () => {
      const now = new Date('2026-10-24T10:00:00Z');

      expect(
        startsInThePast(
          { date: '2026-10-24', time: '11:59' },
          'Europe/Berlin',
          now
        )
      ).toBe(true);
      expect(
        startsInThePast(
          { date: '2026-10-24', time: '12:01' },
          'Europe/Berlin',
          now
        )
      ).toBe(false);
      expect(
        startsInThePast({ date: '2026-10-24', time: '10:00' }, 'Etc/UTC', now)
      ).toBe(true);
    });
  });
});
