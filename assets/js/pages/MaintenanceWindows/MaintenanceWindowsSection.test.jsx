// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import {
  act,
  fireEvent,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';
import { faker } from '@faker-js/faker';

import { renderWithRouter } from '@lib/test-utils';
import { maintenanceWindowFactory } from '@lib/test-utils/factories';
import {
  WINDOW_SUBMISSION_FAILED,
  WINDOW_SUBMISSION_SUCCEEDED,
  initialWindowSubmission,
} from '@state/maintenanceWindows';

import MaintenanceWindowsSection from './MaintenanceWindowsSection';

const abilities = [{ name: 'all', resource: 'all' }];

const ownWindow = maintenanceWindowFactory.build({
  target_type: 'host',
  target_name: 'vmhana01',
  starts_at: '2099-11-20T22:00:00Z',
  timezone: 'Etc/UTC',
  duration_minutes: 120,
  recurrence: null,
  forbids: ['checks_execution', 'operations'],
  inherited: false,
  active: false,
  current_occurrence: null,
  next_occurrence: {
    starts_at: '2099-11-20T22:00:00Z',
    ends_at: '2099-11-21T00:00:00Z',
  },
});

const clusterID = faker.string.uuid();
const inheritedWindow = maintenanceWindowFactory.build({
  target_type: 'cluster',
  target_id: clusterID,
  target_name: 'hana_cluster',
  starts_at: '2026-01-01T08:00:00Z',
  timezone: 'Europe/Berlin',
  duration_minutes: 60,
  recurrence: { frequency: 'daily', interval: 1, weekdays: [], ends_on: null },
  forbids: ['operations'],
  inherited: true,
  active: true,
  current_occurrence: {
    starts_at: '2026-11-20T08:00:00Z',
    ends_at: '2026-11-20T09:00:00Z',
  },
  next_occurrence: {
    starts_at: '2026-11-21T08:00:00Z',
    ends_at: '2026-11-21T09:00:00Z',
  },
});

const ownLabel = 'the maintenance window of 20 Nov 2099, 22:00 – 00:00';

const renderSection = (props) =>
  act(() =>
    renderWithRouter(
      <MaintenanceWindowsSection
        windows={[inheritedWindow, ownWindow]}
        timezone="Etc/UTC"
        targetLabel="host vmhana01"
        userAbilities={abilities}
        {...props}
      />
    )
  );

describe('MaintenanceWindowsSection', () => {
  it('should list the own and inherited windows of the target', async () => {
    await renderSection();

    expect(screen.getByText('Maintenance Windows')).toBeVisible();

    const [, inheritedRow, ownRow] = screen.getAllByRole('row');
    expect(
      within(inheritedRow).getByText('Every day, 09:00 – 10:00 (Europe/Berlin)')
    ).toBeVisible();
    expect(within(inheritedRow).getByText('Operations')).toBeVisible();
    expect(
      within(inheritedRow).getByText('Active until 20 Nov 2026, 09:00:00')
    ).toBeVisible();
    expect(
      within(inheritedRow).getByRole('link', { name: 'From hana_cluster' })
    ).toHaveAttribute('href', `/clusters/${clusterID}`);
    expect(within(inheritedRow).queryByRole('button')).not.toBeInTheDocument();

    expect(
      within(ownRow).getByText('20 Nov 2099, 22:00 – 00:00 (Etc/UTC)')
    ).toBeVisible();
    expect(
      within(ownRow).getByText('Check execution and operations')
    ).toBeVisible();
    expect(
      within(ownRow).getByText('Next on 20 Nov 2099, 22:00:00')
    ).toBeVisible();
    expect(
      within(ownRow).getByRole('button', { name: `Edit ${ownLabel}` })
    ).toBeEnabled();
  });

  it('should schedule a maintenance window for the target, with a premium mark', async () => {
    const user = userEvent.setup();
    const onSchedule = jest.fn();
    const onResetSubmission = jest.fn();

    await renderSection({ windows: [], onSchedule, onResetSubmission });

    expect(
      screen.getByText('No maintenance windows are scheduled.')
    ).toBeVisible();
    expect(screen.getByText('Premium')).toBeVisible();

    await user.click(
      screen.getByRole('button', { name: /Schedule Maintenance/ })
    );
    expect(onResetSubmission).toHaveBeenCalled();
    expect(
      screen.getByText(/forbidden actions on host vmhana01/)
    ).toBeVisible();

    fireEvent.change(screen.getByLabelText('Date'), {
      target: { value: '2099-11-20' },
    });
    fireEvent.change(screen.getByLabelText('Start Time'), {
      target: { value: '22:00' },
    });
    await user.click(screen.getByRole('button', { name: 'Schedule' }));

    expect(onSchedule).toHaveBeenCalledWith({
      starts_at: '2099-11-20T22:00:00.000Z',
      timezone: 'Etc/UTC',
      duration_minutes: 60,
      recurrence: null,
      forbids: ['checks_execution', 'operations'],
    });
  });

  it('should change an own window and close once it is saved', async () => {
    const user = userEvent.setup();
    const onUpdate = jest.fn();
    const props = {
      windows: [ownWindow],
      timezone: 'Etc/UTC',
      targetLabel: 'host vmhana01',
      userAbilities: abilities,
      onUpdate,
    };

    const { rerender } = await act(() =>
      renderWithRouter(<MaintenanceWindowsSection {...props} />)
    );

    await user.click(screen.getByRole('button', { name: `Edit ${ownLabel}` }));
    await user.click(screen.getByLabelText('Check execution'));
    await user.click(screen.getByRole('button', { name: 'Save Changes' }));

    expect(onUpdate).toHaveBeenCalledWith(ownWindow, {
      starts_at: '2099-11-20T22:00:00.000Z',
      timezone: 'Etc/UTC',
      duration_minutes: 120,
      recurrence: null,
      forbids: ['operations'],
    });

    rerender(
      <MaintenanceWindowsSection
        {...props}
        submission={{
          ...initialWindowSubmission,
          status: WINDOW_SUBMISSION_FAILED,
          errors: [{ title: 'Forbidden', detail: 'Not allowed' }],
        }}
      />
    );
    expect(screen.getByText('Not allowed')).toBeVisible();

    rerender(
      <MaintenanceWindowsSection
        {...props}
        submission={{
          ...initialWindowSubmission,
          status: WINDOW_SUBMISSION_SUCCEEDED,
        }}
      />
    );
    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    );
  });

  it('should delete an own window after a confirmation', async () => {
    const user = userEvent.setup();
    const onDelete = jest.fn();

    await renderSection({ onDelete });

    await user.click(
      screen.getByRole('button', { name: `Delete ${ownLabel}` })
    );
    expect(onDelete).not.toHaveBeenCalled();
    expect(
      screen.getByText(
        'Delete the maintenance window of 20 Nov 2099, 22:00 – 00:00 (Etc/UTC)?'
      )
    ).toBeVisible();

    await user.click(screen.getByRole('button', { name: 'Yes, Delete' }));
    expect(onDelete).toHaveBeenCalledWith(ownWindow);
  });

  it('should not allow changes without the maintenance windows ability', async () => {
    await renderSection({
      userAbilities: [{ name: 'all', resource: 'host_checks_selection' }],
    });

    expect(
      screen.getByRole('button', { name: /Schedule Maintenance/ })
    ).toBeDisabled();
    expect(
      screen.getByRole('button', { name: `Edit ${ownLabel}` })
    ).toBeDisabled();
    expect(
      screen.getByRole('button', { name: `Delete ${ownLabel}` })
    ).toBeDisabled();
  });

  it('should tell when the windows cannot be loaded', async () => {
    const user = userEvent.setup();
    const onRetry = jest.fn();

    await renderSection({ windows: [], error: true, onRetry });

    expect(
      screen.getByText('Unable to load the maintenance windows.')
    ).toBeVisible();
    await user.click(screen.getByRole('button', { name: 'Retry' }));
    expect(onRetry).toHaveBeenCalled();
  });
});
