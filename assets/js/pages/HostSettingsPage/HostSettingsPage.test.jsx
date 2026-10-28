// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';

import { act, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { faker } from '@faker-js/faker';
import {
  withState,
  defaultInitialState,
  renderWithRouterMatch,
} from '@lib/test-utils';

import { networkClient } from '@lib/network';
import MockAdapter from 'axios-mock-adapter';

import {
  checksScheduleFactory,
  hostFactory,
  maintenanceWindowFactory,
  selectableCheckFactory,
} from '@lib/test-utils/factories';

import HostSettingsPage from './HostSettingsPage';

const axiosMock = new MockAdapter(networkClient);

describe('HostSettingsPage component', () => {
  it('should render a loading box', async () => {
    const state = {
      ...defaultInitialState,
      hostsList: { hosts: [] },
      user: { abilities: [] },
    };

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    await act(async () => {
      renderWithRouterMatch(StatefulHostSettingsPage, {
        path: 'hosts/:hostID/settings',
        route: `/hosts/${faker.string.uuid()}/settings`,
      });
    });

    expect(screen.getByText('Loading...')).toBeVisible();
    expect(screen.queryByText('Provider')).not.toBeTruthy();
    expect(screen.queryByText('Agent version')).not.toBeTruthy();
    expect(screen.queryByText('Architecture')).not.toBeTruthy();
    expect(
      screen.queryByRole('button', { name: 'Save Check Selection' })
    ).not.toBeTruthy();
  });

  it('should render the host checks selection', async () => {
    const group0 = faker.animal.cat();
    const group1 = faker.animal.dog();
    const group2 = faker.lorem.word();
    const selectableChecks = [
      ...selectableCheckFactory.buildList(2, { group: group0 }),
      ...selectableCheckFactory.buildList(2, { group: group1 }),
      ...selectableCheckFactory.buildList(2, { group: group2 }),
    ];
    const hosts = hostFactory.buildList(3, { provider: 'azure' });

    const state = {
      ...defaultInitialState,
      hostsList: { hosts },
      user: { abilities: [] },
    };
    const { id: hostID, agent_version: agentVersion, arch } = hosts[1];

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    axiosMock
      .onGet(`/api/v1/groups/${hostID}/checks`)
      .reply(200, { items: selectableChecks });

    await act(async () => {
      renderWithRouterMatch(StatefulHostSettingsPage, {
        path: 'hosts/:hostID/settings',
        route: `/hosts/${hostID}/settings`,
      });
    });

    expect(screen.getByText('Provider')).toBeVisible();
    expect(screen.getByText('Azure')).toBeVisible();
    expect(screen.getByText('Agent version')).toBeVisible();
    expect(screen.getByText(agentVersion)).toBeVisible();
    expect(screen.getByText('Architecture')).toBeVisible();
    expect(screen.getByText(arch)).toBeVisible();
    expect(screen.getByText(group0)).toBeVisible();
    expect(screen.getByText(group1)).toBeVisible();
    expect(screen.getByText(group2)).toBeVisible();

    expect(screen.getByText('Save Checks Selection')).toBeVisible();
  });

  it('should render HostSettingsPage with a disabled start execution button, as no checks are selected', async () => {
    const hosts = hostFactory.buildList(2, {
      provider: 'azure',
      selected_checks: [],
    });
    const state = {
      ...defaultInitialState,
      hostsList: { hosts },
      user: { abilities: [{ name: 'all', resource: 'host_checks_execution' }] },
    };
    const { id: hostID } = hosts[1];

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    await act(async () => {
      renderWithRouterMatch(StatefulHostSettingsPage, {
        path: 'hosts/:hostID/settings',
        route: `/hosts/${hostID}/settings`,
      });
    });
    const startExecutionButton = screen.getByText('Start Execution');
    expect(startExecutionButton).toBeDisabled();
  });

  it('should render HostSettingsPage with an enabled start execution button, as checks are selected', async () => {
    const hosts = hostFactory.buildList(2, {
      provider: 'azure',
      selected_checks: [faker.animal.bear(), faker.animal.bear()],
    });
    const state = {
      ...defaultInitialState,
      hostsList: { hosts },
      user: { abilities: [{ name: 'all', resource: 'host_checks_execution' }] },
    };
    const { id: hostID } = hosts[1];
    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    await act(async () => {
      renderWithRouterMatch(StatefulHostSettingsPage, {
        path: 'hosts/:hostID/settings',
        route: `/hosts/${hostID}/settings`,
      });
    });
    const startExecutionButton = screen.getByText('Start Execution');
    expect(startExecutionButton).toBeEnabled();
  });

  it('should render the check execution frequency of the host', async () => {
    const hosts = hostFactory.buildList(2);
    const { id: hostID } = hosts[0];
    const state = {
      ...defaultInitialState,
      hostsList: { hosts },
      user: { abilities: [{ name: 'all', resource: 'check_frequency' }] },
    };

    axiosMock.onGet(`/api/v1/hosts/${hostID}/checks/schedule`).reply(
      200,
      checksScheduleFactory.build({
        interval: '6h',
        effective_interval: '6h',
        global_interval: '5m',
      })
    );

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    await act(async () => {
      renderWithRouterMatch(StatefulHostSettingsPage, {
        path: 'hosts/:hostID/settings',
        route: `/hosts/${hostID}/settings`,
      });
    });

    expect(
      screen.getByText(
        'Configure how often the checks of this host are executed.'
      )
    ).toBeVisible();
    expect(
      screen.getByLabelText('checks-execution-frequency')
    ).toHaveTextContent(
      'Every 6 hours (overrides the system setting: every 5 minutes)'
    );
    expect(screen.getByRole('button', { name: 'Edit Settings' })).toBeEnabled();
  });

  it('should not start an execution during a maintenance window that forbids it', async () => {
    const user = userEvent.setup();
    const hosts = hostFactory.buildList(1, {
      selected_checks: [faker.string.uuid()],
    });
    const { id: hostID } = hosts[0];

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, {
      ...defaultInitialState,
      hostsList: { hosts },
      user: { abilities: [{ name: 'all', resource: 'all' }] },
      maintenanceWindows: {
        byTarget: {
          [hostID]: {
            targetType: 'host',
            loading: false,
            error: false,
            windows: [
              maintenanceWindowFactory.build({
                active: true,
                forbids: ['checks_execution'],
              }),
            ],
          },
        },
      },
    });

    await act(async () => {
      renderWithRouterMatch(StatefulHostSettingsPage, {
        path: 'hosts/:hostID/settings',
        route: `/hosts/${hostID}/settings`,
      });
    });

    const startExecution = screen.getByRole('button', {
      name: 'Start Execution',
    });
    expect(startExecution).toBeDisabled();
    await user.hover(startExecution);
    expect(
      screen.getByText('Checks cannot be executed during a maintenance window')
    ).toBeVisible();
  });
});
