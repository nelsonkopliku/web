import React from 'react';

import { screen, act, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import userEvent from '@testing-library/user-event';

import { faker } from '@faker-js/faker';
import { withState, renderWithRouter } from '@lib/test-utils';
import { catalogCheckFactory, clusterFactory } from '@lib/test-utils/factories';

import ChecksSelection from './ChecksSelection';

describe('ClusterDetails ChecksSelection component', () => {
  it('should change individual check switches accordingly if the group switch is clicked', async () => {
    const user = userEvent.setup();

    const group = faker.animal.cat();
    const catalog = catalogCheckFactory.buildList(2, { group });
    const cluster = clusterFactory.build();

    const initialState = {
      catalog: { loading: false, data: catalog, error: null },
    };
    const [statefulChecksSelection] = withState(
      <ChecksSelection clusterId={cluster.id} cluster={cluster} />,
      initialState
    );

    await act(async () => renderWithRouter(statefulChecksSelection));

    const groupItem = await waitFor(() => screen.getByText(group));

    await user.click(groupItem);
    let switches = screen.getAllByRole('switch');

    expect(switches[0]).not.toBeChecked();
    expect(switches[1]).not.toBeChecked();
    expect(switches[2]).not.toBeChecked();

    await user.click(switches[0]);

    switches = screen.getAllByRole('switch');

    expect(switches[1]).toBeChecked();
    expect(switches[2]).toBeChecked();

    await user.click(switches[0]);

    switches = screen.getAllByRole('switch');

    expect(switches[1]).not.toBeChecked();
    expect(switches[2]).not.toBeChecked();
  });

  it('should change group check switch accordingly if the children check switches are clicked', async () => {
    const user = userEvent.setup();

    const group = faker.animal.cat();
    const catalog = catalogCheckFactory.buildList(2, { group });
    const cluster = clusterFactory.build({
      selected_checks: [catalog[0].id, catalog[1].id],
    });

    const initialState = {
      catalog: { loading: false, data: catalog, error: null },
    };
    const [statefulChecksSelection] = withState(
      <ChecksSelection clusterId={cluster.id} cluster={cluster} />,
      initialState
    );

    await act(async () => renderWithRouter(statefulChecksSelection));

    const groupItem = await waitFor(() => screen.getByText(group));

    await user.click(groupItem);
    let switches = screen.getAllByRole('switch');

    expect(switches[0]).toBeChecked();
    expect(switches[1]).toBeChecked();
    expect(switches[2]).toBeChecked();

    await user.click(switches[1]);
    switches = screen.getAllByRole('switch');

    expect(switches[0]).not.toBeChecked();
    expect(switches[0].classList.contains('bg-green-300')).toBe(true);

    await user.click(switches[2]);

    switches = screen.getAllByRole('switch');

    expect(switches[0]).not.toBeChecked();
  });

  it('should dispatch selected checks message when the save button is clicked', async () => {
    const user = userEvent.setup();

    const catalog = catalogCheckFactory.buildList(2);
    const selectedChecks = [catalog[0].id, catalog[1].id];
    const cluster = clusterFactory.build({
      selected_checks: selectedChecks,
    });

    const initialState = {
      catalog: { loading: false, data: catalog, error: null },
    };
    const [statefulChecksSelection, store] = withState(
      <ChecksSelection clusterId={cluster.id} cluster={cluster} />,
      initialState
    );

    await act(async () => renderWithRouter(statefulChecksSelection));

    await waitFor(() => screen.getAllByRole('heading'));

    const saveButton = screen.getByRole('button', {
      name: 'Select Checks for Execution',
    });
    await user.click(saveButton);

    const actions = store.getActions();
    const expectedActions = [
      {
        type: 'UPDATE_CATALOG',
        payload: {
          provider: cluster.provider,
          target_type: 'cluster',
        },
      },
      {
        type: 'CLUSTER_CHECKS_SELECTED',
        payload: {
          checks: selectedChecks,
          clusterID: cluster.id,
          clusterName: cluster.name,
        },
      },
    ];
    expect(actions).toEqual(expect.arrayContaining(expectedActions));
  });
});
