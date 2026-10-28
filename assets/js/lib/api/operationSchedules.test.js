// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import MockAdapter from 'axios-mock-adapter';

import { networkClient } from '@lib/network';

import {
  getOperationSchedules,
  getOperationSchedulesOfTargets,
} from './operationSchedules';

const axiosMock = new MockAdapter(networkClient);

describe('operation schedules API', () => {
  afterEach(() => axiosMock.reset());

  it('should get the schedules of a target', async () => {
    axiosMock.onGet('/operation_schedules').reply(200, []);

    await getOperationSchedules('host-id');

    expect(axiosMock.history.get[0].params).toEqual({ target_id: 'host-id' });
  });

  it('should look up the schedules of an operation on several targets', async () => {
    axiosMock.onGet('/operation_schedules').reply(200, []);

    await getOperationSchedulesOfTargets(['host-1', 'host-2'], 'reboot');

    expect(axiosMock.history.get[0].params).toEqual({
      target_ids: 'host-1,host-2',
      operation: 'reboot',
    });
  });
});
