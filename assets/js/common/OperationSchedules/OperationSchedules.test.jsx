// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { operationScheduleFactory } from '@lib/test-utils/factories';
import {
  initialScheduleSubmission,
  SUBMISSION_FAILED,
  SUBMISSION_SUBMITTING,
  SUBMISSION_SUCCEEDED,
} from '@state/operationSchedules';

import OperationSchedules from './OperationSchedules';

const abilities = [{ name: 'all', resource: 'all' }];

const weeklySchedule = operationScheduleFactory.build({
  target_type: 'sap_system',
  operation: 'sap_system_stop',
  params: { instance_type: 'abap', timeout: 300 },
  starts_at: '2026-11-21T02:00:00.000000Z',
  timezone: 'Europe/Berlin',
  recurrence: {
    frequency: 'weekly',
    interval: 2,
    weekdays: [6, 7],
    ends_on: null,
    max_occurrences: 5,
  },
  next_run_at: '2026-11-28T02:00:00.000000Z',
});

const oneTimeSchedule = operationScheduleFactory.build({
  operation: 'reboot',
  params: {},
  starts_at: '2026-11-20T03:00:00.000000Z',
  timezone: 'Etc/UTC',
  recurrence: null,
  next_run_at: '2026-11-20T03:00:00.000000Z',
});

const renderSchedules = (props) =>
  act(() =>
    render(
      <OperationSchedules
        schedules={[weeklySchedule, oneTimeSchedule]}
        timezone="Etc/UTC"
        userAbilities={abilities}
        {...props}
      />
    )
  );

describe('OperationSchedules', () => {
  it('should list the scheduled operations with their options and when they run', async () => {
    await renderSchedules();

    expect(screen.getByText('Scheduled Operations')).toBeVisible();

    const [, weeklyRow, oneTimeRow] = screen.getAllByRole('row');
    expect(
      within(weeklyRow)
        .getAllByRole('cell')
        .map(({ textContent }) => textContent)
        .slice(0, 4)
    ).toEqual([
      'SAP system stop',
      'Instances: ABAP, Timeout: 5 minutes',
      '28 Nov 2026, 02:00:00',
      'Every 2 weeks on Saturdays, Sundays at 03:00, 5 times (Europe/Berlin)',
    ]);
    expect(
      within(oneTimeRow)
        .getAllByRole('cell')
        .map(({ textContent }) => textContent)
        .slice(0, 4)
    ).toEqual([
      'Reboot host',
      '',
      '20 Nov 2026, 03:00:00',
      '20 Nov 2026 at 03:00',
    ]);
  });

  it('should open a schedule to change it', async () => {
    const user = userEvent.setup();
    const onEdit = jest.fn();

    await renderSchedules({ onEdit });

    await user.click(
      screen.getByRole('button', {
        name: 'Edit the schedule of Reboot host, next run 20 Nov 2026, 03:00:00',
      })
    );
    expect(onEdit).toHaveBeenCalledWith(oneTimeSchedule);
  });

  it('should cancel a schedule after a confirmation, and close once it is cancelled', async () => {
    const user = userEvent.setup();
    const onCancel = jest.fn();

    const { rerender } = await renderSchedules({ onCancel });

    await user.click(
      screen.getByRole('button', {
        name: 'Cancel the schedule of Reboot host, next run 20 Nov 2026, 03:00:00',
      })
    );
    expect(onCancel).not.toHaveBeenCalled();
    expect(
      screen.getByText(
        'Cancel this schedule of Reboot host? The operation will not be requested anymore.'
      )
    ).toBeVisible();

    await user.click(
      screen.getByRole('button', { name: 'Yes, Cancel Schedule' })
    );
    expect(onCancel).toHaveBeenCalledWith(oneTimeSchedule);

    const props = {
      schedules: [weeklySchedule, oneTimeSchedule],
      timezone: 'Etc/UTC',
      userAbilities: abilities,
      onCancel,
    };

    rerender(
      <OperationSchedules
        {...props}
        submission={{
          ...initialScheduleSubmission,
          status: SUBMISSION_SUBMITTING,
        }}
      />
    );
    expect(
      screen.getByRole('button', { name: 'Yes, Cancel Schedule' })
    ).toBeDisabled();

    rerender(
      <OperationSchedules
        {...props}
        submission={{
          ...initialScheduleSubmission,
          status: SUBMISSION_FAILED,
          errors: [{ title: 'Not Found', detail: 'The schedule is gone.' }],
        }}
      />
    );
    expect(screen.getByText('The schedule is gone.')).toBeVisible();

    rerender(
      <OperationSchedules
        {...props}
        submission={{
          ...initialScheduleSubmission,
          status: SUBMISSION_SUCCEEDED,
        }}
      />
    );
    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    );
  });

  it('should keep a schedule when the cancellation is not confirmed', async () => {
    const user = userEvent.setup();
    const onCancel = jest.fn();
    const onResetSubmission = jest.fn();

    await renderSchedules({ onCancel, onResetSubmission });

    await user.click(
      screen.getByRole('button', {
        name: 'Cancel the schedule of Reboot host, next run 20 Nov 2026, 03:00:00',
      })
    );
    expect(onResetSubmission).toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'Keep Schedule' }));

    expect(onCancel).not.toHaveBeenCalled();
    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    );
  });

  it('should allow changes only with the abilities of the operation', async () => {
    await renderSchedules({
      userAbilities: [{ name: 'reboot', resource: 'host' }],
    });

    expect(
      screen.getByRole('button', {
        name: 'Edit the schedule of Reboot host, next run 20 Nov 2026, 03:00:00',
      })
    ).toBeEnabled();
    expect(
      screen.getByRole('button', {
        name: 'Cancel the schedule of Reboot host, next run 20 Nov 2026, 03:00:00',
      })
    ).toBeEnabled();
    expect(
      screen.getByRole('button', {
        name: 'Edit the schedule of SAP system stop, next run 28 Nov 2026, 02:00:00',
      })
    ).toBeDisabled();
    expect(
      screen.getByRole('button', {
        name: 'Cancel the schedule of SAP system stop, next run 28 Nov 2026, 02:00:00',
      })
    ).toBeDisabled();
  });

  it('should tell when the scheduled operations cannot be loaded', async () => {
    const user = userEvent.setup();
    const onRetry = jest.fn();

    await renderSchedules({ schedules: [], error: true, onRetry });

    expect(
      screen.getByText('Unable to load the scheduled operations.')
    ).toBeVisible();
    await user.click(screen.getByRole('button', { name: 'Retry' }));
    expect(onRetry).toHaveBeenCalled();
  });

  it('should render nothing without schedules', async () => {
    const { container } = await renderSchedules({ schedules: [] });

    expect(container).toBeEmptyDOMElement();
  });
});
