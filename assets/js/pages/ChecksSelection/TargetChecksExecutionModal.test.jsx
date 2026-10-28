// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { checksScheduleFactory } from '@lib/test-utils/factories';

import TargetChecksExecutionModal from './TargetChecksExecutionModal';

const systemSchedule = checksScheduleFactory.build({
  interval: null,
  effective_interval: '15m',
  global_interval: '15m',
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

    expect(onSave).toHaveBeenCalledWith({ interval: '1h' });
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

    expect(onSave).toHaveBeenCalledWith({ interval: null });
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
});
