// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import MockAdapter from 'axios-mock-adapter';
import { faker } from '@faker-js/faker';

import { recordSaga } from '@lib/test-utils';
import { networkClient } from '@lib/network';
import { defaultGlobalError } from '@lib/api/validationErrors';
import {
  hostFactory,
  maintenanceWindowFactory,
} from '@lib/test-utils/factories';

import { notify } from '@state/notifications';
import {
  fetchMaintenanceWindows as fetchMaintenanceWindowsAction,
  setMaintenanceWindowSubmissionErrors,
  setMaintenanceWindowSubmitted,
  setMaintenanceWindows,
  setMaintenanceWindowsError,
  startLoadingMaintenanceWindows,
  startMaintenanceWindowSubmission,
} from '@state/maintenanceWindows';

import {
  deleteMaintenanceWindow,
  fetchMaintenanceWindows,
  refreshMaintenanceWindows,
  scheduleMaintenanceWindow,
  updateMaintenanceWindow,
} from './maintenanceWindows';

const axiosMock = new MockAdapter(networkClient);

describe('maintenance windows saga', () => {
  afterEach(() => {
    axiosMock.reset();
  });

  const host = hostFactory.build();
  const displayed = {
    hostsList: { hosts: [host] },
    maintenanceWindows: {
      byTarget: {
        [host.id]: {
          targetType: 'host',
          loading: false,
          error: false,
          windows: [],
        },
      },
    },
  };

  describe('fetching the windows of a target', () => {
    it('should set the windows that cover the target', async () => {
      const windows = maintenanceWindowFactory.buildList(2);
      axiosMock
        .onGet('/maintenance_windows', {
          params: { target_type: 'host', target_id: host.id },
        })
        .reply(200, windows);

      const dispatched = await recordSaga(fetchMaintenanceWindows, {
        payload: { targetType: 'host', targetID: host.id },
      });

      expect(dispatched).toEqual([
        startLoadingMaintenanceWindows({
          targetType: 'host',
          targetID: host.id,
        }),
        setMaintenanceWindows({
          targetType: 'host',
          targetID: host.id,
          windows,
        }),
      ]);
    });

    it('should tell when the windows cannot be fetched', async () => {
      axiosMock.onGet('/maintenance_windows').reply(500);

      const dispatched = await recordSaga(fetchMaintenanceWindows, {
        payload: { targetType: 'host', targetID: host.id },
      });

      expect(dispatched).toEqual([
        startLoadingMaintenanceWindows({
          targetType: 'host',
          targetID: host.id,
        }),
        setMaintenanceWindowsError({ targetType: 'host', targetID: host.id }),
      ]);
    });
  });

  describe('scheduling a window', () => {
    const request = {
      target_type: 'host',
      target_id: host.id,
      starts_at: '2099-11-20T22:00:00.000Z',
      timezone: 'Etc/UTC',
      duration_minutes: 60,
      recurrence: null,
      forbids: ['operations'],
    };

    it('should create the window, tell it and fetch the windows of the displayed targets again', async () => {
      axiosMock
        .onPost('/maintenance_windows', request)
        .reply(201, maintenanceWindowFactory.build(request));

      const dispatched = await recordSaga(
        scheduleMaintenanceWindow,
        { payload: { request } },
        displayed
      );

      expect(dispatched).toEqual([
        startMaintenanceWindowSubmission(),
        setMaintenanceWindowSubmitted(),
        notify({
          text: `Maintenance window scheduled for ${host.hostname}`,
          icon: '🛠️',
        }),
        fetchMaintenanceWindowsAction({
          targetType: 'host',
          targetID: host.id,
        }),
      ]);
    });

    it('should keep the errors of a refused window', async () => {
      const errors = [
        {
          title: 'Invalid value',
          detail: 'is in the past',
          source: { pointer: '/starts_at' },
        },
      ];
      axiosMock.onPost('/maintenance_windows').reply(422, { errors });

      const dispatched = await recordSaga(
        scheduleMaintenanceWindow,
        { payload: { request } },
        displayed
      );

      expect(dispatched).toEqual([
        startMaintenanceWindowSubmission(),
        setMaintenanceWindowSubmissionErrors({ errors }),
      ]);
    });
  });

  describe('changing and deleting a window', () => {
    const window = maintenanceWindowFactory.build({
      target_type: 'host',
      target_id: host.id,
      target_name: host.hostname,
    });
    const changes = {
      starts_at: window.starts_at,
      timezone: 'Etc/UTC',
      duration_minutes: 90,
      recurrence: null,
      forbids: ['checks_execution'],
    };

    it('should save the changes of a window', async () => {
      axiosMock
        .onPut(`/maintenance_windows/${window.id}`, changes)
        .reply(200, { ...window, ...changes });

      const dispatched = await recordSaga(
        updateMaintenanceWindow,
        { payload: { window, changes } },
        displayed
      );

      expect(dispatched).toEqual([
        startMaintenanceWindowSubmission(),
        setMaintenanceWindowSubmitted(),
        notify({
          text: `Maintenance window of ${host.hostname} changed`,
          icon: '🛠️',
        }),
        fetchMaintenanceWindowsAction({
          targetType: 'host',
          targetID: host.id,
        }),
      ]);
    });

    it('should delete a window', async () => {
      axiosMock.onDelete(`/maintenance_windows/${window.id}`).reply(204);

      const dispatched = await recordSaga(
        deleteMaintenanceWindow,
        { payload: { window } },
        displayed
      );

      expect(dispatched).toEqual([
        startMaintenanceWindowSubmission(),
        setMaintenanceWindowSubmitted(),
        notify({
          text: `Maintenance window of ${host.hostname} deleted`,
          icon: '🗑️',
        }),
        fetchMaintenanceWindowsAction({
          targetType: 'host',
          targetID: host.id,
        }),
      ]);
    });

    it('should tell an unexpected error when a deletion fails without details', async () => {
      axiosMock.onDelete(`/maintenance_windows/${window.id}`).networkError();

      const dispatched = await recordSaga(
        deleteMaintenanceWindow,
        { payload: { window } },
        displayed
      );

      expect(dispatched).toEqual([
        startMaintenanceWindowSubmission(),
        setMaintenanceWindowSubmissionErrors({ errors: [defaultGlobalError] }),
      ]);
    });
  });

  it('should fetch the windows of every displayed target after a change of any window, because windows are inherited', async () => {
    const clusterID = faker.string.uuid();

    const dispatched = await recordSaga(
      refreshMaintenanceWindows,
      { payload: { targetType: 'cluster', targetID: clusterID } },
      displayed
    );

    expect(dispatched).toEqual([
      fetchMaintenanceWindowsAction({ targetType: 'host', targetID: host.id }),
    ]);
  });
});
