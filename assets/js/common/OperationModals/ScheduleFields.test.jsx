// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import ScheduleFields, {
  initialScheduleForm,
  scheduleFormErrors,
  scheduleToForm,
  toScheduleRequest,
} from './ScheduleFields';

const now = new Date('2026-11-19T10:20:00Z');

const futureForm = {
  ...initialScheduleForm('Etc/UTC', now),
  type: 'one_time',
  date: '2026-11-20',
  time: '03:00',
};

describe('ScheduleFields', () => {
  describe('form', () => {
    it('should start now, with the next full hour in the user timezone', () => {
      expect(initialScheduleForm('Europe/Berlin', now)).toEqual({
        type: 'now',
        date: '2026-11-19',
        time: '12:00',
        repeatValue: '1',
        repeatUnit: 'days',
        weekdays: [],
        ends: 'never',
        endsOn: '',
        maxOccurrences: '1',
      });
    });

    it('should turn an existing schedule into a form in its own timezone', () => {
      expect(
        scheduleToForm({
          starts_at: '2026-11-20T02:00:00Z',
          timezone: 'Europe/Berlin',
          recurrence: {
            frequency: 'weekly',
            interval: 2,
            weekdays: [6],
            ends_on: null,
            max_occurrences: 5,
          },
        })
      ).toMatchObject({
        type: 'periodic',
        date: '2026-11-20',
        time: '03:00',
        repeatValue: '2',
        repeatUnit: 'weeks',
        weekdays: [6],
        ends: 'after',
        maxOccurrences: '5',
      });

      expect(
        scheduleToForm({
          starts_at: '2026-11-20T02:00:00Z',
          timezone: 'Etc/UTC',
          recurrence: {
            frequency: 'daily',
            interval: 1,
            ends_on: '2027-01-01',
          },
        })
      ).toMatchObject({
        type: 'periodic',
        time: '02:00',
        ends: 'on',
        endsOn: '2027-01-01',
      });
    });

    it('should request the operation now', () => {
      expect(
        toScheduleRequest({ ...futureForm, type: 'now' }, 'Etc/UTC')
      ).toBeNull();
    });

    it('should schedule a one-time operation in the given timezone', () => {
      expect(toScheduleRequest(futureForm, 'Europe/Berlin')).toEqual({
        starts_at: '2026-11-20T02:00:00.000Z',
        timezone: 'Europe/Berlin',
        recurrence: null,
      });
    });

    it('should schedule a periodic operation with its end', () => {
      const periodic = {
        ...futureForm,
        type: 'periodic',
        repeatUnit: 'weeks',
        weekdays: [6],
      };

      expect(
        toScheduleRequest(
          { ...periodic, ends: 'after', maxOccurrences: '5' },
          'Etc/UTC'
        )
      ).toEqual({
        starts_at: '2026-11-20T03:00:00.000Z',
        timezone: 'Etc/UTC',
        recurrence: {
          frequency: 'weekly',
          interval: 1,
          weekdays: [6],
          ends_on: null,
          max_occurrences: 5,
        },
      });

      expect(
        toScheduleRequest(
          { ...periodic, ends: 'on', endsOn: '2027-01-01' },
          'Etc/UTC'
        ).recurrence
      ).toMatchObject({ ends_on: '2027-01-01', max_occurrences: null });
    });
  });

  describe('validation', () => {
    it.each`
      change                                                     | errors
      ${{ type: 'now', date: '2020-01-01' }}                     | ${{}}
      ${{}}                                                      | ${{}}
      ${{ date: '' }}                                            | ${{ start: 'Pick a date and a start time' }}
      ${{ date: '2026-11-19', time: '10:00' }}                   | ${{ start: 'Pick a date and time in the future' }}
      ${{ type: 'periodic', repeatValue: '0' }}                  | ${{ repeat: 'Repeat at least every 1' }}
      ${{ type: 'periodic', ends: 'on', endsOn: '' }}            | ${{ ends: 'Pick the end date' }}
      ${{ type: 'periodic', ends: 'on', endsOn: '2026-11-20' }}  | ${{ ends: 'The end date must be after the start date' }}
      ${{ type: 'periodic', ends: 'after', maxOccurrences: '' }} | ${{ ends: 'Run at least once' }}
      ${{ type: 'periodic', ends: 'on', endsOn: '2026-11-21' }}  | ${{}}
    `('should validate $change', ({ change, errors }) => {
      expect(
        scheduleFormErrors({ ...futureForm, ...change }, 'Etc/UTC', { now })
      ).toEqual(errors);
    });

    it('should keep the past start of an ongoing periodic schedule', () => {
      const ongoing = {
        ...futureForm,
        type: 'periodic',
        date: '2026-11-01',
        time: '03:00',
      };

      expect(
        scheduleFormErrors(ongoing, 'Etc/UTC', {
          now,
          unchangedStart: { date: '2026-11-01', time: '03:00' },
        })
      ).toEqual({});
      expect(
        scheduleFormErrors({ ...ongoing, time: '04:00' }, 'Etc/UTC', {
          now,
          unchangedStart: { date: '2026-11-01', time: '03:00' },
        })
      ).toEqual({ start: 'Pick a date and time in the future' });
    });
  });

  describe('component', () => {
    it('should offer to request now, once or periodically, with a premium mark', async () => {
      const user = userEvent.setup();
      const onChange = jest.fn();

      render(
        <ScheduleFields
          form={{ ...futureForm, type: 'now' }}
          timezone="Europe/Berlin"
          onChange={onChange}
        />
      );

      expect(screen.getByText('Schedule')).toBeVisible();
      expect(screen.getByText('Premium')).toBeVisible();
      expect(screen.queryByLabelText('Date')).not.toBeInTheDocument();

      await user.click(screen.getByText('Now'));
      await user.click(screen.getByRole('option', { name: 'Periodic' }));

      expect(onChange).toHaveBeenLastCalledWith({
        ...futureForm,
        type: 'periodic',
      });
    });

    it('should not offer now when changing a schedule', async () => {
      const user = userEvent.setup();

      render(
        <ScheduleFields form={futureForm} timezone="Etc/UTC" allowNow={false} />
      );

      await user.click(screen.getByText('One Time'));

      expect(
        screen.queryByRole('option', { name: 'Now' })
      ).not.toBeInTheDocument();
    });

    it('should tell the timezone and summarize when the operation runs', () => {
      render(
        <ScheduleFields
          form={{
            ...futureForm,
            date: '2099-11-20',
            type: 'periodic',
            repeatUnit: 'weeks',
            weekdays: [6, 7],
            ends: 'after',
            maxOccurrences: '5',
          }}
          timezone="Europe/Berlin"
        />
      );

      expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();
      expect(screen.getByLabelText('schedule-summary')).toHaveTextContent(
        'Saturdays, Sundays at 03:00, 5 times'
      );
    });

    it('should tell why the schedule cannot be saved', () => {
      render(
        <ScheduleFields
          form={{ ...futureForm, date: '2020-11-20' }}
          timezone="Etc/UTC"
        />
      );

      expect(
        screen.getByText('Pick a date and time in the future')
      ).toBeVisible();
      expect(
        screen.queryByLabelText('schedule-summary')
      ).not.toBeInTheDocument();
    });

    it('should show the errors of a refused schedule', () => {
      render(
        <ScheduleFields
          form={{
            ...futureForm,
            date: '2099-11-20',
            type: 'periodic',
            ends: 'on',
            endsOn: '2099-12-01',
          }}
          timezone="Etc/UTC"
          errors={[
            {
              title: 'Invalid value',
              detail: 'must be in the future',
              source: { pointer: '/starts_at' },
            },
            {
              title: 'Invalid value',
              detail: 'leaves no occurrence',
              source: { pointer: '/ends_on' },
            },
          ]}
        />
      );

      expect(screen.getByText('Must be in the future')).toBeVisible();
      expect(screen.getByText('Leaves no occurrence')).toBeVisible();
    });

    it('should end a periodic schedule on a date or after some occurrences', () => {
      const onChange = jest.fn();
      const periodic = { ...futureForm, type: 'periodic' };

      const { rerender } = render(
        <ScheduleFields
          form={{ ...periodic, ends: 'on', endsOn: '2027-01-01' }}
          timezone="Etc/UTC"
          onChange={onChange}
        />
      );

      expect(screen.getByLabelText('End date')).toHaveValue('2027-01-01');
      fireEvent.change(screen.getByLabelText('End date'), {
        target: { value: '2027-02-01' },
      });
      expect(onChange).toHaveBeenLastCalledWith({
        ...periodic,
        ends: 'on',
        endsOn: '2027-02-01',
      });

      rerender(
        <ScheduleFields
          form={{ ...periodic, ends: 'after', maxOccurrences: '3' }}
          timezone="Etc/UTC"
          onChange={onChange}
        />
      );

      expect(screen.getByLabelText('Occurrences')).toHaveValue('3');
    });
  });
});
