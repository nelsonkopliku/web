// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import MockAdapter from 'axios-mock-adapter';

import { networkClient } from '@lib/network';

import { getMaintenanceWindows } from './maintenanceWindows';

const axiosMock = new MockAdapter(networkClient);

describe('maintenance windows API', () => {
  afterEach(() => axiosMock.reset());

  it('should get the windows that cover a target', async () => {
    axiosMock.onGet('/maintenance_windows').reply(200, []);

    await getMaintenanceWindows('cluster', 'cluster-id');

    expect(axiosMock.history.get[0].params).toEqual({
      target_type: 'cluster',
      target_id: 'cluster-id',
    });
  });
});
