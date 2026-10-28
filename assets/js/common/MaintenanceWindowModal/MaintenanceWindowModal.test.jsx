// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { maintenanceWindowFactory } from '@lib/test-utils/factories';

import MaintenanceWindowModal from './MaintenanceWindowModal';

const setStart = (date, time) => {
  fireEvent.change(screen.getByLabelText('Date'), { target: { value: date } });
  fireEvent.change(screen.getByLabelText('Start Time'), {
    target: { value: time },
  });
};

const renderModal = (props) =>
  act(() =>
    render(
      <MaintenanceWindowModal
        isOpen
        targetLabel="host vmhana01"
        timezone="Europe/Berlin"
        {...props}
      />
    )
  );

describe('MaintenanceWindowModal', () => {
  it('should schedule a one-time window in the user timezone', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();

    await renderModal({ onSave });

    expect(screen.getByText('Schedule Maintenance')).toBeVisible();
    expect(
      screen.getByText(
        'During the window, Trento does not execute the forbidden actions on host vmhana01 and on the targets it covers.'
      )
    ).toBeVisible();
    expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();
    expect(screen.getByLabelText('Check execution')).toBeChecked();
    expect(screen.getByLabelText('Operations')).toBeChecked();

    setStart('2099-11-20', '23:00');
    await user.clear(screen.getByLabelText('Duration'));
    await user.type(screen.getByLabelText('Duration'), '2');

    expect(screen.getByLabelText('window-summary')).toHaveTextContent(
      '20 Nov 2099, 23:00 – 01:00'
    );

    await user.click(screen.getByRole('button', { name: 'Schedule' }));

    expect(onSave).toHaveBeenCalledWith({
      starts_at: '2099-11-20T22:00:00.000Z',
      timezone: 'Europe/Berlin',
      duration_minutes: 120,
      recurrence: null,
      forbids: ['checks_execution', 'operations'],
    });
  });

  it('should schedule a periodic window forbidding operations only, ending on a date', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();

    await renderModal({ onSave, timezone: 'Etc/UTC' });

    await user.click(screen.getByLabelText('Check execution'));
    await user.click(screen.getByText('One Time'));
    await user.click(screen.getByRole('option', { name: 'Periodic' }));
    setStart('2099-11-21', '22:00');

    await user.click(screen.getByText('Days'));
    await user.click(screen.getByRole('option', { name: 'Weeks' }));
    await user.click(screen.getByText('Day of the start'));
    await user.click(screen.getByRole('option', { name: 'Saturday' }));

    await user.click(screen.getByText('Never'));
    await user.click(screen.getByRole('option', { name: 'On date' }));
    fireEvent.change(screen.getByLabelText('End date'), {
      target: { value: '2100-01-01' },
    });

    await user.click(screen.getByRole('button', { name: 'Schedule' }));

    expect(onSave).toHaveBeenCalledWith({
      starts_at: '2099-11-21T22:00:00.000Z',
      timezone: 'Etc/UTC',
      duration_minutes: 60,
      recurrence: {
        frequency: 'weekly',
        interval: 1,
        weekdays: [6],
        ends_on: '2100-01-01',
      },
      forbids: ['operations'],
    });
  });

  it('should forbid at least one action', async () => {
    const user = userEvent.setup();

    await renderModal();

    await user.click(screen.getByLabelText('Check execution'));
    await user.click(screen.getByLabelText('Operations'));

    expect(
      screen.getByText('Forbid check execution, operations or both')
    ).toBeVisible();
    expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();
  });

  it('should not schedule a window in the past', async () => {
    await renderModal();

    setStart('2020-11-20', '23:00');

    expect(
      screen.getByText('Pick a date and time in the future')
    ).toBeVisible();
    expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();
  });

  it('should change a window in its own timezone, keeping the start of an active one', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const window = maintenanceWindowFactory.build({
      starts_at: '2020-11-20T22:00:00Z',
      timezone: 'Europe/Berlin',
      duration_minutes: 90,
      recurrence: { frequency: 'daily', interval: 1, ends_on: null },
      forbids: ['operations'],
    });

    await renderModal({ window, timezone: 'Etc/UTC', onSave });

    expect(screen.getByText('Change Maintenance Window')).toBeVisible();
    expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();
    expect(screen.getByLabelText('Check execution')).not.toBeChecked();
    expect(screen.getByLabelText('Start Time')).toHaveValue('23:00');

    await user.click(screen.getByLabelText('Check execution'));
    await user.click(screen.getByRole('button', { name: 'Save Changes' }));

    expect(onSave).toHaveBeenCalledWith({
      starts_at: '2020-11-20T22:00:00.000Z',
      timezone: 'Europe/Berlin',
      duration_minutes: 90,
      recurrence: {
        frequency: 'daily',
        interval: 1,
        weekdays: [],
        ends_on: null,
      },
      forbids: ['operations', 'checks_execution'],
    });
  });

  it('should show the errors of a refused window', async () => {
    await renderModal({
      errors: [
        {
          title: 'Invalid value',
          detail: 'must be less than or equal to 44640',
          source: { pointer: '/duration_minutes' },
        },
        {
          title: 'Invalid value',
          detail: 'is not a valid timezone',
          source: { pointer: '/timezone' },
        },
        {
          title: 'Invalid value',
          detail: 'leaves no occurrence that is not over',
          source: { pointer: '/starts_at' },
        },
        { title: 'Forbidden', detail: 'You can not perform this action.' },
      ],
    });

    expect(
      screen.getByText('Must be less than or equal to 44640')
    ).toBeVisible();
    expect(
      screen.getByText('Leaves no occurrence that is not over')
    ).toBeVisible();
    expect(screen.getByText('Timezone: is not a valid timezone')).toBeVisible();
    expect(screen.getByText('You can not perform this action.')).toBeVisible();
  });

  it('should not save twice while saving', async () => {
    await renderModal({ loading: true });

    expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();
  });

  it('should cancel', async () => {
    const user = userEvent.setup();
    const onCancel = jest.fn();

    await renderModal({ onCancel });

    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onCancel).toHaveBeenCalled();
  });
});
