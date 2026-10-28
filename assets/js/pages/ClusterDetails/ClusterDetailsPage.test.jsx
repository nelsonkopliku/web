// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';

import { act, screen } from '@testing-library/react';
import { faker } from '@faker-js/faker';
import '@testing-library/jest-dom';
import MockAdapter from 'axios-mock-adapter';

import { networkClient } from '@lib/network';
import { withState, renderWithRouterMatch } from '@lib/test-utils';

import {
  catalogCheckFactory,
  checksScheduleFactory,
  clusterFactory,
} from '@lib/test-utils/factories';

import { ClusterDetailsPage } from './ClusterDetailsPage';

const axiosMock = new MockAdapter(networkClient);

describe('ClusterDetails ClusterDetailsPage component', () => {
  afterEach(() => {
    axiosMock.reset();
  });

  it.each([
    {
      type: 'hana_scale_up',
      label: 'HANA Scale Up Perf. Opt.',
      scenario: 'performance_optimized',
    },
    {
      type: 'hana_scale_up',
      label: 'HANA Scale Up Cost Opt.',
      scenario: 'cost_optimized',
    },
    {
      type: 'ascs_ers',
      label: 'ASCS/ERS',
      scenario: 'unknwon',
    },
    {
      type: 'unknwon',
      label: 'Unknown cluster type',
      scenario: 'unknwon',
    },
  ])(
    'should display the $type details based on cluster type',
    async ({ type, label, scenario }) => {
      const cluster = clusterFactory.build({
        type,
        details: { hana_scenario: scenario },
      });
      const initialState = {
        clustersList: { clusters: [cluster] },
        hostsList: { hosts: [] },
        sapSystemsList: { sapSystems: [], applicationInstances: [] },
        databasesList: { databases: [], databaseInstances: [] },
        lastExecutions: {
          [cluster.id]: { data: null, loading: false, error: null },
        },
        catalog: { data: null, loading: false, error: null },
        user: {
          abilities: [{ name: 'all', resource: 'all' }],
        },
      };

      const [statefulClusterDetailsPage, _] = withState(
        <ClusterDetailsPage />,
        initialState
      );

      // The page fetches the checks schedule of the cluster
      await act(async () => {
        renderWithRouterMatch(statefulClusterDetailsPage, {
          path: 'clusters/:clusterID',
          route: `/clusters/${cluster.id}`,
        });
      });

      expect(screen.getByText(label)).toBeInTheDocument();
    }
  );

  it('should show that no execution is planned when periodic executions of the cluster are disabled', async () => {
    const cluster = clusterFactory.build({
      type: 'hana_scale_up',
      details: { hana_scenario: 'performance_optimized' },
    });
    axiosMock.onGet(`/api/v1/clusters/${cluster.id}/checks/schedule`).reply(
      200,
      checksScheduleFactory.build({
        interval: 'disabled',
        effective_interval: 'disabled',
        next_execution_at: null,
      })
    );

    const [statefulClusterDetailsPage] = withState(<ClusterDetailsPage />, {
      clustersList: { clusters: [cluster] },
      hostsList: { hosts: [] },
      sapSystemsList: { sapSystems: [], applicationInstances: [] },
      databasesList: { databases: [], databaseInstances: [] },
      lastExecutions: {
        [cluster.id]: { data: null, loading: false, error: null },
      },
      catalog: {
        data: catalogCheckFactory.buildList(2),
        loading: false,
        error: null,
      },
      user: { abilities: [{ name: 'all', resource: 'all' }] },
    });

    await act(async () => {
      renderWithRouterMatch(statefulClusterDetailsPage, {
        path: 'clusters/:clusterID',
        route: `/clusters/${cluster.id}`,
      });
    });

    expect(screen.getByText('No execution planned')).toBeVisible();
  });

  it('should not start an execution while the cluster is in its exception window', async () => {
    const cluster = clusterFactory.build({
      type: 'hana_scale_up',
      details: { hana_scenario: 'performance_optimized' },
      selected_checks: [faker.string.uuid()],
    });
    axiosMock
      .onGet(`/api/v1/clusters/${cluster.id}/checks/schedule`)
      .reply(200, checksScheduleFactory.build({ in_exception_window: true }));

    const [statefulClusterDetailsPage] = withState(<ClusterDetailsPage />, {
      clustersList: { clusters: [cluster] },
      hostsList: { hosts: [] },
      sapSystemsList: { sapSystems: [], applicationInstances: [] },
      databasesList: { databases: [], databaseInstances: [] },
      lastExecutions: {
        [cluster.id]: { data: null, loading: false, error: null },
      },
      catalog: { data: [], loading: false, error: null },
      user: { abilities: [{ name: 'all', resource: 'all' }] },
    });

    await act(async () => {
      renderWithRouterMatch(statefulClusterDetailsPage, {
        path: 'clusters/:clusterID',
        route: `/clusters/${cluster.id}`,
      });
    });

    expect(
      screen.getByRole('button', { name: 'Start Execution' })
    ).toBeDisabled();
  });
});
