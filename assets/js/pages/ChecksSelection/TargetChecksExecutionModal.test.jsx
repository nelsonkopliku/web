// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import {
  checksScheduleFactory,
  exceptionWindowFactory,
} from '@lib/test-utils/factories';

import TargetChecksExecutionModal from './TargetChecksExecutionModal';

const systemSchedule = checksScheduleFactory.build({
  interval: null,
  effective_interval: '15m',
  global_interval: '15m',
  exception_window: null,
});

describe('TargetChecksExecutionModal', () => {
  it('should save a frequency for the target', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();

    render(
      <TargetChecksExecutionModal
        open
        schedule={systemSchedule}
        onSave={onSave}
      />
    );

    expect(screen.getByText('Check Execution Settings')).toBeVisible();
    expect(
      screen.getByText('The system setting is every 15 minutes.')
    ).toBeVisible();

    await user.click(screen.getByText('System setting'));
    await user.click(screen.getByRole('option', { name: 'Hours' }));
    await user.click(screen.getByRole('button', { name: 'Save Settings' }));

    expect(onSave).toHaveBeenCalledWith({
      interval: '1h',
      exception_window: null,
    });
  });

  it('should go back to the system setting', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();

    render(
      <TargetChecksExecutionModal
        open
        schedule={checksScheduleFactory.build({
          interval: '1h',
          effective_interval: '1h',
          global_interval: '15m',
        })}
        onSave={onSave}
      />
    );

    await user.click(screen.getByText('Hours'));
    await user.click(screen.getByRole('option', { name: 'System setting' }));
    await user.click(screen.getByRole('button', { name: 'Save Settings' }));

    expect(onSave).toHaveBeenCalledWith({
      interval: null,
      exception_window: null,
    });
  });

  it('should not save twice while saving', async () => {
    await act(async () => {
      render(
        <TargetChecksExecutionModal open loading schedule={systemSchedule} />
      );
    });

    expect(
      screen.getByRole('button', { name: 'Save Settings' })
    ).toBeDisabled();
  });

  it('should show the errors of a refused change', async () => {
    await act(async () => {
      render(
        <TargetChecksExecutionModal
          open
          schedule={systemSchedule}
          errors={[
            {
              title: 'Invalid value',
              detail: 'is invalid',
              source: { pointer: '/interval' },
            },
            { title: 'Forbidden', detail: 'You can not perform this action.' },
          ]}
        />
      );
    });

    expect(screen.getByText('Is invalid')).toBeVisible();
    expect(screen.getByText('You can not perform this action.')).toBeVisible();
  });

  it('should cancel without saving', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const onCancel = jest.fn();

    render(
      <TargetChecksExecutionModal
        open
        schedule={systemSchedule}
        onSave={onSave}
        onCancel={onCancel}
      />
    );

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onCancel).toHaveBeenCalled();
    expect(onSave).not.toHaveBeenCalled();
  });

  describe('exception window', () => {
    const setStart = (date, time) => {
      fireEvent.change(screen.getByLabelText('Date'), {
        target: { value: date },
      });
      fireEvent.change(screen.getByLabelText('Start Time'), {
        target: { value: time },
      });
    };

    it('should save a periodic exception window in the user timezone', async () => {
      const user = userEvent.setup();
      const onSave = jest.fn();

      render(
        <TargetChecksExecutionModal
          open
          schedule={systemSchedule}
          timezone="Europe/Berlin"
          onSave={onSave}
        />
      );

      await user.click(screen.getByText('None'));
      await user.click(screen.getByRole('option', { name: 'Periodic' }));

      expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();

      setStart('2099-10-13', '00:00');

      await user.click(screen.getByText('Days'));
      await user.click(screen.getByRole('option', { name: 'Weeks' }));
      await user.click(screen.getByText('Day of the start'));
      await user.click(screen.getByRole('option', { name: 'Monday' }));

      await user.clear(screen.getByLabelText('Duration'));
      await user.type(screen.getByLabelText('Duration'), '90');
      await user.click(screen.getByText('Hours'));
      await user.click(screen.getByRole('option', { name: 'Minutes' }));

      expect(screen.getByLabelText('window-summary')).toHaveTextContent(
        'Mondays, 00:00 – 01:30'
      );

      await user.click(screen.getByRole('button', { name: 'Save Settings' }));

      expect(onSave).toHaveBeenCalledWith({
        interval: null,
        exception_window: {
          starts_at: '2099-10-12T22:00:00.000Z',
          timezone: 'Europe/Berlin',
          duration_minutes: 90,
          recurrence: { frequency: 'weekly', interval: 1, weekdays: [1] },
        },
      });
    });

    it('should change an exception window in its own timezone, keeping the start of an active one', async () => {
      const user = userEvent.setup();
      const onSave = jest.fn();

      render(
        <TargetChecksExecutionModal
          open
          schedule={{
            ...systemSchedule,
            exception_window: exceptionWindowFactory.build({
              starts_at: '2020-10-13T10:00:00Z',
              timezone: 'Europe/Berlin',
              duration_minutes: 30,
              recurrence: { frequency: 'daily', interval: 1 },
            }),
          }}
          timezone="Etc/UTC"
          onSave={onSave}
        />
      );

      expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();
      expect(screen.getByLabelText('Date')).toHaveValue('2020-10-13');
      expect(screen.getByLabelText('Start Time')).toHaveValue('12:00');

      await user.clear(screen.getByLabelText('Duration'));
      await user.type(screen.getByLabelText('Duration'), '45');
      await user.click(screen.getByRole('button', { name: 'Save Settings' }));

      expect(onSave).toHaveBeenCalledWith({
        interval: null,
        exception_window: {
          starts_at: '2020-10-13T10:00:00.000Z',
          timezone: 'Europe/Berlin',
          duration_minutes: 45,
          recurrence: { frequency: 'daily', interval: 1, weekdays: [] },
        },
      });
    });

    it('should remove the exception window', async () => {
      const user = userEvent.setup();
      const onSave = jest.fn();

      render(
        <TargetChecksExecutionModal
          open
          schedule={{
            ...systemSchedule,
            exception_window: exceptionWindowFactory.build(),
          }}
          onSave={onSave}
        />
      );

      await user.click(screen.getByText('One Time'));
      await user.click(screen.getByRole('option', { name: 'None' }));
      await user.click(screen.getByRole('button', { name: 'Save Settings' }));

      expect(onSave).toHaveBeenCalledWith({
        interval: null,
        exception_window: null,
      });
    });

    it('should not save a new exception window in the past', async () => {
      const user = userEvent.setup();

      render(<TargetChecksExecutionModal open schedule={systemSchedule} />);

      await user.click(screen.getByText('None'));
      await user.click(screen.getByRole('option', { name: 'One Time' }));
      setStart('2020-10-13', '00:00');

      expect(
        screen.getByText('Pick a date and time in the future')
      ).toBeVisible();
      expect(
        screen.getByRole('button', { name: 'Save Settings' })
      ).toBeDisabled();
    });

    it('should show the errors of a refused exception window', async () => {
      const user = userEvent.setup();

      render(
        <TargetChecksExecutionModal
          open
          schedule={systemSchedule}
          errors={[
            {
              title: 'Invalid value',
              detail: 'must be less than or equal to 44640',
              source: { pointer: '/exception_window/duration_minutes' },
            },
            {
              title: 'Invalid value',
              detail: 'the exception window has already ended',
              source: { pointer: '/window_starts_at' },
            },
            {
              title: 'Invalid value',
              detail: 'is not a valid timezone',
              source: { pointer: '/window_timezone' },
            },
          ]}
        />
      );

      await user.click(screen.getByText('None'));
      await user.click(screen.getByRole('option', { name: 'One Time' }));

      expect(
        screen.getByText('Must be less than or equal to 44640')
      ).toBeVisible();
      expect(
        screen.getByText('The exception window has already ended')
      ).toBeVisible();
      expect(
        screen.getByText('Window_timezone: is not a valid timezone')
      ).toBeVisible();
    });
  });
});
