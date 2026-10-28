// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import userEvent from '@testing-library/user-event';

import OperationAlreadyRunningModal from './OperationAlreadyRunningModal';

describe('OperationAlreadyRunningModal', () => {
  it('should tell that another operation runs for the target', async () => {
    await act(() =>
      render(<OperationAlreadyRunningModal isOpen operation="Reboot host" />)
    );

    expect(screen.getByText('Operation Already Running')).toBeVisible();
    expect(
      screen.getByText(
        'Unable to run Reboot host operation now. Another operation is already running for this target.'
      )
    ).toBeVisible();
    expect(
      screen.getByText(
        'Request it again once the running operation completes, or schedule it.'
      )
    ).toBeVisible();
  });

  it('should close', async () => {
    const user = userEvent.setup();
    const onClose = jest.fn();

    await act(() =>
      render(
        <OperationAlreadyRunningModal
          isOpen
          operation="Reboot host"
          onClose={onClose}
        />
      )
    );

    await user.click(screen.getByRole('button', { name: 'Close' }));
    expect(onClose).toHaveBeenCalled();
  });
});
