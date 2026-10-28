// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, screen, within } from '@testing-library/react';
import '@testing-library/jest-dom';
import userEvent from '@testing-library/user-event';

import { renderWithRouter } from '@lib/test-utils';
import { hostFactory, policyWarningFactory } from '@lib/test-utils/factories';

import ScheduleWarningsModal from './ScheduleWarningsModal';

describe('ScheduleWarningsModal', () => {
  it('should tell the pre-requisites that are not met now, with links to the resources', async () => {
    const { id, hostname } = hostFactory.build();

    await act(() =>
      renderWithRouter(
        <ScheduleWarningsModal
          isOpen
          operation="Reboot host"
          warnings={[
            policyWarningFactory.build({
              message: 'Trento agent is not currently running in the host {0}',
              metadata: [{ id, label: hostname, type: 'host' }],
            }),
          ]}
        />
      )
    );

    expect(screen.getByText('Operation Scheduled')).toBeVisible();
    expect(
      screen.getByText(
        'Reboot host is scheduled, but it could not run now. These pre-requisites are checked again when it runs:'
      )
    ).toBeVisible();
    const [item] = within(screen.getByRole('list')).getAllByRole('listitem');
    expect(item).toHaveTextContent(
      `Trento agent is not currently running in the host ${hostname}`
    );
    expect(screen.getByRole('link', { name: hostname })).toHaveAttribute(
      'href',
      `/hosts/${id}`
    );
  });

  it('should tell the target of each warning of a bulk schedule', async () => {
    await act(() =>
      renderWithRouter(
        <ScheduleWarningsModal
          isOpen
          operation="Reboot host"
          warnings={[
            {
              ...policyWarningFactory.build({
                message: 'Trento agent is not currently running in the host',
              }),
              targetName: 'vmhana01',
            },
            {
              ...policyWarningFactory.build({
                message: 'Trento agent is not currently running in the host',
              }),
              targetName: 'vmhana02',
            },
          ]}
        />
      )
    );

    const items = within(screen.getByRole('list')).getAllByRole('listitem');
    expect(items.map(({ textContent }) => textContent)).toEqual([
      'vmhana01: Trento agent is not currently running in the host',
      'vmhana02: Trento agent is not currently running in the host',
    ]);
  });

  it('should close', async () => {
    const user = userEvent.setup();
    const onClose = jest.fn();

    await act(() =>
      renderWithRouter(
        <ScheduleWarningsModal
          isOpen
          operation="Reboot host"
          warnings={[policyWarningFactory.build()]}
          onClose={onClose}
        />
      )
    );

    await user.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalled();
  });
});
