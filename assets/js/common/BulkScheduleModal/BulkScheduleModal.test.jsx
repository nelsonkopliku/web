// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { HOST_REBOOT } from '@lib/operations';
import { operationScheduleFactory } from '@lib/test-utils/factories';
import {
  initialScheduleSubmission,
  SUBMISSION_CONFLICTS,
  SUBMISSION_FAILED,
  SUBMISSION_SUBMITTING,
} from '@state/operationSchedules';

import BulkScheduleModal from './BulkScheduleModal';

const setDateAndTime = (date, time) => {
  fireEvent.change(screen.getByLabelText('Date'), { target: { value: date } });
  fireEvent.change(screen.getByLabelText('Start Time'), {
    target: { value: time },
  });
};

const renderModal = (props) =>
  act(() =>
    render(
      <BulkScheduleModal
        isOpen
        operation={HOST_REBOOT}
        targetType="host"
        targetsCount={3}
        timezone="Etc/UTC"
        {...props}
      />
    )
  );

describe('BulkScheduleModal', () => {
  it('should schedule an operation on the selected targets', async () => {
    const user = userEvent.setup();
    const onSchedule = jest.fn();

    await renderModal({ onSchedule });

    expect(screen.getByText('Schedule Reboot host')).toBeVisible();
    expect(
      screen.getByText(
        'Reboot host on 3 hosts. Each one gets its own schedule, that can be changed and cancelled on its own.'
      )
    ).toBeVisible();
    expect(screen.getByText('Premium')).toBeVisible();
    expect(screen.queryByText('Now')).not.toBeInTheDocument();

    setDateAndTime('2099-11-20', '03:00');
    await user.click(screen.getByRole('button', { name: 'Schedule' }));

    expect(onSchedule).toHaveBeenCalledWith(
      {
        starts_at: '2099-11-20T03:00:00.000Z',
        timezone: 'Etc/UTC',
        recurrence: null,
      },
      { confirmed: false }
    );
  });

  it('should count a single target', async () => {
    await renderModal({ targetsCount: 1 });

    expect(screen.getByText(/^Reboot host on 1 host\./)).toBeVisible();
  });

  it('should not schedule without targets', async () => {
    const conflicts = operationScheduleFactory.buildList(1);

    const { rerender } = await renderModal({ targetsCount: 0 });

    setDateAndTime('2099-11-20', '03:00');
    expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();

    rerender(
      <BulkScheduleModal
        isOpen
        operation={HOST_REBOOT}
        targetType="host"
        targetsCount={0}
        timezone="Etc/UTC"
        submission={{
          ...initialScheduleSubmission,
          status: SUBMISSION_CONFLICTS,
          conflicts,
        }}
      />
    );
    expect(screen.getByRole('button', { name: 'Continue' })).toBeDisabled();
  });

  it('should not schedule an operation in the past', async () => {
    await renderModal();

    setDateAndTime('2020-11-20', '03:00');

    expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();
    expect(
      screen.getByText('Pick a date and time in the future')
    ).toBeVisible();
  });

  it('should warn about the targets that already have a schedule of the operation', async () => {
    const user = userEvent.setup();
    const onSchedule = jest.fn();
    const conflict = operationScheduleFactory.build({
      target_id: 'host-2',
      operation: HOST_REBOOT,
      starts_at: '2099-11-19T03:00:00Z',
      timezone: 'Etc/UTC',
      recurrence: null,
    });

    const { rerender } = await renderModal({ onSchedule });

    setDateAndTime('2099-11-20', '03:00');

    rerender(
      <BulkScheduleModal
        isOpen
        operation={HOST_REBOOT}
        targetType="host"
        targetsCount={3}
        timezone="Etc/UTC"
        targetNames={{ 'host-2': 'vmhana02' }}
        submission={{
          ...initialScheduleSubmission,
          status: SUBMISSION_CONFLICTS,
          conflicts: [conflict],
        }}
        onSchedule={onSchedule}
      />
    );

    expect(
      screen.getByText(
        'Reboot host is already scheduled for 1 host of the selection:'
      )
    ).toBeVisible();
    expect(
      screen.getByText('vmhana02: 19 Nov 2099 at 03:00 (Etc/UTC)')
    ).toBeVisible();

    await user.click(screen.getByRole('button', { name: 'Continue' }));

    expect(onSchedule).toHaveBeenCalledWith(
      {
        starts_at: '2099-11-20T03:00:00.000Z',
        timezone: 'Etc/UTC',
        recurrence: null,
      },
      { confirmed: true }
    );
  });

  it('should go back to the selection when the warning is cancelled', async () => {
    const user = userEvent.setup();
    const onCancel = jest.fn();

    await renderModal({
      onCancel,
      submission: {
        ...initialScheduleSubmission,
        status: SUBMISSION_CONFLICTS,
        conflicts: operationScheduleFactory.buildList(1),
      },
    });

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onCancel).toHaveBeenCalled();
  });

  it('should not schedule twice while scheduling', async () => {
    await renderModal({
      submission: {
        ...initialScheduleSubmission,
        status: SUBMISSION_SUBMITTING,
      },
    });

    expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();
  });

  it('should show the errors of a refused bulk schedule', async () => {
    await renderModal({
      submission: {
        ...initialScheduleSubmission,
        status: SUBMISSION_FAILED,
        errors: [
          {
            title: 'Invalid value',
            detail: 'must be in the future',
            source: { pointer: '/starts_at' },
          },
          {
            title: 'Invalid value',
            detail: 'Array length 501 is larger than maxItems: 500',
            source: { pointer: '/target_ids' },
          },
          { title: 'Forbidden', detail: 'You can not perform this action.' },
        ],
      },
    });

    expect(screen.getByText('Must be in the future')).toBeVisible();
    expect(
      screen.getByText(
        'Target_ids: Array length 501 is larger than maxItems: 500'
      )
    ).toBeVisible();
    expect(screen.getByText('You can not perform this action.')).toBeVisible();
  });

  it('should cancel', async () => {
    const user = userEvent.setup();
    const onCancel = jest.fn();

    await renderModal({ onCancel });

    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onCancel).toHaveBeenCalled();
  });
});
