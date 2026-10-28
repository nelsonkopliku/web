// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';
import MockAdapter from 'axios-mock-adapter';
import { faker } from '@faker-js/faker';

import { networkClient } from '@lib/network';
import { renderWithRouter, withState } from '@lib/test-utils';
import { checksScheduleFactory } from '@lib/test-utils/factories';

import { useChecksSchedule } from './hooks';
import TargetChecksExecutionSection from './TargetChecksExecutionSection';

function HostChecksExecutionSection({ hostID, ...props }) {
  const checksSchedule = useChecksSchedule('host', hostID);

  return (
    <TargetChecksExecutionSection
      targetType="host"
      checksSchedule={checksSchedule}
      {...props}
    />
  );
}

const axiosMock = new MockAdapter(networkClient);

const abilities = [{ name: 'all', resource: 'all' }];

const renderSection = async (targetID) => {
  const [StatefulSection] = withState(
    <HostChecksExecutionSection hostID={targetID} userAbilities={abilities} />,
    { lastExecutions: {} }
  );

  await act(async () => {
    renderWithRouter(StatefulSection);
  });
};

describe('TargetChecksExecutionSection', () => {
  const hostID = faker.string.uuid();
  const scheduleURL = `/api/v1/hosts/${hostID}/checks/schedule`;

  afterEach(() => {
    axiosMock.reset();
  });

  it('should render a loading box while fetching the checks schedule', async () => {
    axiosMock.onGet(scheduleURL).reply(
      () =>
        new Promise((resolve) => {
          setTimeout(() => resolve([200, {}]), 5000);
        })
    );

    await renderSection(hostID);

    expect(
      screen.getByText('Loading Check Execution Settings...')
    ).toBeVisible();
  });

  it('should render a connection error and fetch the checks schedule again', async () => {
    const user = userEvent.setup();
    axiosMock
      .onGet(scheduleURL)
      .replyOnce(500)
      .onGet(scheduleURL)
      .reply(200, checksScheduleFactory.build({ effective_interval: '1w' }));

    await renderSection(hostID);
    await user.click(screen.getByRole('button', { name: 'Reload' }));

    expect(
      await screen.findByLabelText('checks-execution-frequency')
    ).toHaveTextContent('Every week');
  });

  it('should change the frequency of the target and close the modal', async () => {
    const user = userEvent.setup();
    axiosMock.onGet(scheduleURL).reply(
      200,
      checksScheduleFactory.build({
        interval: null,
        effective_interval: '15m',
        global_interval: '15m',
      })
    );
    axiosMock
      .onPut(scheduleURL, { interval: '1h', exception_window: null })
      .reply(
        200,
        checksScheduleFactory.build({
          interval: '1h',
          effective_interval: '1h',
          global_interval: '15m',
        })
      );

    await renderSection(hostID);
    await user.click(screen.getByRole('button', { name: 'Edit Settings' }));

    const modal = screen.getByRole('dialog');
    await user.click(within(modal).getByText('System setting'));
    await user.click(within(modal).getByRole('option', { name: 'Hours' }));
    await user.click(
      within(modal).getByRole('button', { name: 'Save Settings' })
    );

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    );
    expect(
      screen.getByLabelText('checks-execution-frequency')
    ).toHaveTextContent(
      'Every hour (overrides the system setting: every 15 minutes)'
    );
  });

  it('should keep the modal open when the schedule is fetched again', async () => {
    const user = userEvent.setup();
    axiosMock.onGet(scheduleURL).reply(200, checksScheduleFactory.build());
    let state = { lastExecutions: {} };
    const [StatefulSection, store] = withState(
      <HostChecksExecutionSection hostID={hostID} userAbilities={abilities} />,
      () => state
    );
    await act(async () => {
      renderWithRouter(StatefulSection);
    });

    await user.click(screen.getByRole('button', { name: 'Edit Settings' }));
    await user.click(
      within(screen.getByRole('dialog')).getByText('System setting')
    );
    await user.click(screen.getByRole('option', { name: 'Hours' }));

    // An execution of the host starts: the next execution moves
    state = {
      lastExecutions: { [hostID]: { data: { status: 'running' } } },
    };
    await act(async () => {
      store.dispatch({ type: 'EXECUTION_STARTED' });
    });
    await waitFor(() => expect(axiosMock.history.get).toHaveLength(2));

    const modal = screen.getByRole('dialog');
    expect(modal).toBeVisible();
    expect(within(modal).getByText('Hours')).toBeVisible();
  });

  it('should keep the modal open with the error of a refused change', async () => {
    const user = userEvent.setup();
    axiosMock.onGet(scheduleURL).reply(200, checksScheduleFactory.build());
    axiosMock.onPut(scheduleURL).reply(403, {
      errors: [
        { title: 'Forbidden', detail: 'You can not perform this action.' },
      ],
    });

    await renderSection(hostID);
    await user.click(screen.getByRole('button', { name: 'Edit Settings' }));
    await user.click(screen.getByRole('button', { name: 'Save Settings' }));

    expect(
      await screen.findByText('You can not perform this action.')
    ).toBeVisible();
    expect(screen.getByRole('dialog')).toBeVisible();
  });
});
