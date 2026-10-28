// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import ChecksExecutionSettingsModal from './ChecksExecutionSettingsModal';

describe('ChecksExecutionSettingsModal', () => {
  it('should save the new frequency', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();

    render(
      <ChecksExecutionSettingsModal open initialInterval="5m" onSave={onSave} />
    );

    expect(screen.getByText('Check Execution Settings')).toBeVisible();

    await user.click(screen.getByText('Minutes'));
    await user.click(screen.getByRole('option', { name: 'Hours' }));
    await user.click(screen.getByRole('button', { name: 'Save Settings' }));

    expect(onSave).toHaveBeenCalledWith({ interval: '1h' });
  });

  it('should not save twice while saving', async () => {
    await act(async () => {
      render(
        <ChecksExecutionSettingsModal open loading initialInterval="5m" />
      );
    });

    expect(
      screen.getByRole('button', { name: 'Save Settings' })
    ).toBeDisabled();
  });

  it('should show the errors of a refused change', async () => {
    await act(async () => {
      render(
        <ChecksExecutionSettingsModal
          open
          initialInterval="5m"
          errors={[
            {
              detail: 'is invalid',
              source: { pointer: '/interval' },
              title: 'Invalid value',
            },
            {
              detail: 'The frequency is enforced by CHECKS_INTERVAL',
              title: 'Conflict',
            },
          ]}
        />
      );
    });

    expect(screen.getByText('Is invalid')).toBeVisible();
    expect(
      screen.getByText('The frequency is enforced by CHECKS_INTERVAL')
    ).toBeVisible();
  });

  it('should cancel without saving', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const onCancel = jest.fn();

    render(
      <ChecksExecutionSettingsModal
        open
        initialInterval="5m"
        onSave={onSave}
        onCancel={onCancel}
      />
    );

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onCancel).toHaveBeenCalled();
    expect(onSave).not.toHaveBeenCalled();
  });
});
