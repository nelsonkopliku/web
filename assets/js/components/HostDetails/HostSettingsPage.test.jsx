import React from 'react';

import { screen } from '@testing-library/react';
import '@testing-library/jest-dom';

import { faker } from '@faker-js/faker';
import {
  withState,
  defaultInitialState,
  renderWithRouterMatch,
} from '@lib/test-utils';
import { catalogCheckFactory, hostFactory } from '@lib/test-utils/factories';

import HostSettingsPage from './HostSettingsPage';

describe('HostSettingsPage component', () => {
  it('should render a loading box', () => {
    const state = {
      ...defaultInitialState,
      hostsList: { hosts: [] },
    };

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    renderWithRouterMatch(StatefulHostSettingsPage, {
      path: 'hosts/:hostID/settings',
      route: `/hosts/${faker.datatype.uuid()}/settings`,
    });

    expect(screen.getByText('Loading...')).toBeVisible();
    expect(screen.queryByText('Provider')).not.toBeTruthy();
    expect(screen.queryByText('Agent version')).not.toBeTruthy();
    expect(
      screen.queryByRole('button', { name: 'Save Check Selection' })
    ).not.toBeTruthy();
  });

  it('should render the host checks selection', () => {
    const group0 = faker.animal.cat();
    const group1 = faker.animal.dog();
    const group2 = faker.lorem.word();
    const catalog = [
      ...catalogCheckFactory.buildList(2, { group: group0 }),
      ...catalogCheckFactory.buildList(2, { group: group1 }),
      ...catalogCheckFactory.buildList(2, { group: group2 }),
    ];
    const hosts = hostFactory.buildList(3, { provider: 'azure' });

    const state = {
      ...defaultInitialState,
      catalog: { ...defaultInitialState.catalog, data: catalog },
      hostsList: { hosts },
    };
    const { id: hostID, agent_version: agentVersion } = hosts[1];

    const [StatefulHostSettingsPage] = withState(<HostSettingsPage />, state);

    renderWithRouterMatch(StatefulHostSettingsPage, {
      path: 'hosts/:hostID/settings',
      route: `/hosts/${hostID}/settings`,
    });

    expect(screen.getByText('Provider')).toBeVisible();
    expect(screen.getByText('Azure')).toBeVisible();
    expect(screen.getByText('Agent version')).toBeVisible();
    expect(screen.getByText(agentVersion)).toBeVisible();
    expect(screen.getByText(group0)).toBeVisible();
    expect(screen.getByText(group1)).toBeVisible();
    expect(screen.getByText(group2)).toBeVisible();

    expect(
      screen.getByRole('button', { name: 'Save Check Selection' })
    ).toBeVisible();
  });
});
