// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import MockAdapter from 'axios-mock-adapter';
import { faker } from '@faker-js/faker';

import { recordSaga } from '@lib/test-utils';
import { networkClient } from '@lib/network';
import { defaultGlobalError } from '@lib/api/validationErrors';
import {
  clusterFactory,
  hostFactory,
  operationScheduleFactory,
  policyWarningFactory,
} from '@lib/test-utils/factories';

import { notify } from '@state/notifications';
import {
  fetchOperationSchedules as fetchOperationSchedulesAction,
  setOperationScheduleConflicts,
  setOperationScheduleSubmissionErrors,
  setOperationScheduleSubmitted,
  setOperationSchedules,
  setOperationSchedulesError,
  startLoadingOperationSchedules,
  startOperationScheduleSubmission,
} from '@state/operationSchedules';

import {
  bulkScheduleOperation,
  cancelOperationSchedule,
  fetchOperationSchedules,
  refreshOperationSchedules,
  scheduleOperation,
  updateOperationSchedule,
} from './operationSchedules';

const axiosMock = new MockAdapter(networkClient);

describe('operation schedules saga', () => {
  afterEach(() => {
    axiosMock.reset();
  });

  describe('fetching the schedules of a target', () => {
    const targetID = faker.string.uuid();

    it('should set the schedules of the target, the next one first', async () => {
      const later = operationScheduleFactory.build({
        next_run_at: '2099-11-21T03:00:00Z',
      });
      const sooner = operationScheduleFactory.build({
        next_run_at: '2099-11-20T03:00:00Z',
      });
      axiosMock
        .onGet('/operation_schedules', { params: { target_id: targetID } })
        .reply(200, [later, sooner]);

      const dispatched = await recordSaga(fetchOperationSchedules, {
        payload: { targetID },
      });

      expect(dispatched).toEqual([
        startLoadingOperationSchedules({ targetID }),
        setOperationSchedules({ targetID, schedules: [sooner, later] }),
      ]);
    });

    it('should tell when the schedules of the target cannot be fetched', async () => {
      axiosMock.onGet('/operation_schedules').reply(500);

      const dispatched = await recordSaga(fetchOperationSchedules, {
        payload: { targetID },
      });

      expect(dispatched).toEqual([
        startLoadingOperationSchedules({ targetID }),
        setOperationSchedulesError({ targetID }),
      ]);
    });
  });

  describe('scheduling an operation', () => {
    const host = hostFactory.build();
    const request = {
      target_type: 'host',
      target_id: host.id,
      operation: 'reboot',
      params: {},
      starts_at: '2099-11-20T03:00:00.000Z',
      timezone: 'Etc/UTC',
      recurrence: null,
    };
    const state = { hostsList: { hosts: [host] } };

    it('should create the schedule, tell it and fetch the schedules of the target again', async () => {
      const warnings = policyWarningFactory.buildList(1);
      axiosMock
        .onPost('/operation_schedules', request)
        .reply(201, { ...operationScheduleFactory.build(request), warnings });

      const dispatched = await recordSaga(
        scheduleOperation,
        { payload: request },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmitted({ operation: 'reboot', warnings }),
        notify({
          text: `Operation Reboot host scheduled for ${host.hostname}`,
          icon: '📅',
        }),
        fetchOperationSchedulesAction({ targetID: host.id }),
      ]);
    });

    it('should name a cluster target in the notification', async () => {
      const cluster = clusterFactory.build();
      const clusterRequest = {
        ...request,
        target_type: 'cluster',
        target_id: cluster.id,
        operation: 'cluster_maintenance_change',
        params: { maintenance: true },
      };
      axiosMock
        .onPost('/operation_schedules')
        .reply(201, { ...operationScheduleFactory.build(), warnings: [] });

      const dispatched = await recordSaga(
        scheduleOperation,
        { payload: clusterRequest },
        { clustersList: { clusters: [cluster] } }
      );

      expect(dispatched).toContainEqual(
        notify({
          text: `Operation Cluster maintenance change scheduled for ${cluster.name}`,
          icon: '📅',
        })
      );
    });

    it('should keep the errors of a refused schedule', async () => {
      const errors = [
        {
          title: 'Invalid value',
          detail: 'must be in the future',
          source: { pointer: '/starts_at' },
        },
      ];
      axiosMock.onPost('/operation_schedules').reply(422, { errors });

      const dispatched = await recordSaga(
        scheduleOperation,
        { payload: request },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmissionErrors({ errors }),
      ]);
    });

    it('should tell an unexpected error when the request fails without details', async () => {
      axiosMock.onPost('/operation_schedules').networkError();

      const dispatched = await recordSaga(
        scheduleOperation,
        { payload: request },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmissionErrors({ errors: [defaultGlobalError] }),
      ]);
    });
  });

  describe('changing a schedule', () => {
    const host = hostFactory.build();
    const schedule = operationScheduleFactory.build({
      target_type: 'host',
      target_id: host.id,
      operation: 'reboot',
    });
    const changes = {
      params: {},
      starts_at: '2099-11-21T03:00:00.000Z',
      timezone: 'Etc/UTC',
      recurrence: null,
    };
    const state = { hostsList: { hosts: [host] } };

    it('should save the changes, tell it and fetch the schedules of the target again', async () => {
      const warnings = policyWarningFactory.buildList(1);
      axiosMock
        .onPut(`/operation_schedules/${schedule.id}`, changes)
        .reply(200, { ...schedule, ...changes, warnings });

      const dispatched = await recordSaga(
        updateOperationSchedule,
        { payload: { schedule, changes } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmitted({ operation: 'reboot', warnings }),
        notify({
          text: `Schedule of operation Reboot host for ${host.hostname} changed`,
          icon: '📅',
        }),
        fetchOperationSchedulesAction({ targetID: host.id }),
      ]);
    });

    it('should keep the errors of a refused change', async () => {
      const errors = [
        {
          title: 'Not Found',
          detail: 'The requested resource cannot be found.',
        },
      ];
      axiosMock
        .onPut(`/operation_schedules/${schedule.id}`)
        .reply(404, { errors });

      const dispatched = await recordSaga(
        updateOperationSchedule,
        { payload: { schedule, changes } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmissionErrors({ errors }),
      ]);
    });
  });

  describe('cancelling a schedule', () => {
    const host = hostFactory.build();
    const schedule = operationScheduleFactory.build({
      target_type: 'host',
      target_id: host.id,
      operation: 'reboot',
    });
    const state = { hostsList: { hosts: [host] } };

    it('should delete the schedule, tell it and fetch the schedules of the target again', async () => {
      axiosMock.onDelete(`/operation_schedules/${schedule.id}`).reply(204);

      const dispatched = await recordSaga(
        cancelOperationSchedule,
        { payload: { schedule } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmitted({ operation: 'reboot' }),
        notify({
          text: `Schedule of operation Reboot host for ${host.hostname} cancelled`,
          icon: '🗑️',
        }),
        fetchOperationSchedulesAction({ targetID: host.id }),
      ]);
    });

    it('should keep the errors of a refused cancellation', async () => {
      axiosMock.onDelete(`/operation_schedules/${schedule.id}`).reply(500);

      const dispatched = await recordSaga(
        cancelOperationSchedule,
        { payload: { schedule } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmissionErrors({ errors: [defaultGlobalError] }),
      ]);
    });
  });

  describe('refreshing the schedules of a target', () => {
    const targetID = faker.string.uuid();

    it('should fetch the schedules of a displayed target again', async () => {
      const dispatched = await recordSaga(
        refreshOperationSchedules,
        { payload: { targetID } },
        {
          operationSchedules: {
            byTarget: {
              [targetID]: { loading: false, error: false, schedules: [] },
            },
          },
        }
      );

      expect(dispatched).toEqual([fetchOperationSchedulesAction({ targetID })]);
    });

    it('should ignore the targets that are not displayed', async () => {
      const dispatched = await recordSaga(
        refreshOperationSchedules,
        { payload: { targetID } },
        { operationSchedules: { byTarget: {} } }
      );

      expect(dispatched).toEqual([]);
    });

    it('should refresh the target of a completed operation', async () => {
      const dispatched = await recordSaga(
        refreshOperationSchedules,
        { payload: { groupID: targetID } },
        {
          operationSchedules: {
            byTarget: {
              [targetID]: { loading: false, error: false, schedules: [] },
            },
          },
        }
      );

      expect(dispatched).toEqual([fetchOperationSchedulesAction({ targetID })]);
    });
  });

  describe('scheduling an operation on several targets', () => {
    const [host1, host2] = hostFactory.buildList(2);
    const request = {
      target_type: 'host',
      target_ids: [host1.id, host2.id],
      operation: 'reboot',
      params: {},
      starts_at: '2099-11-20T03:00:00.000Z',
      timezone: 'Etc/UTC',
      recurrence: null,
    };
    const state = { hostsList: { hosts: [host1, host2] } };
    const lookupParams = {
      target_ids: `${host1.id},${host2.id}`,
      operation: 'reboot',
    };

    it('should create the schedules when no target has one, telling the warnings of each target', async () => {
      const warning = policyWarningFactory.build();
      axiosMock
        .onGet('/operation_schedules', { params: lookupParams })
        .reply(200, []);
      axiosMock.onPost('/operation_schedules/bulk', request).reply(201, {
        bulk_id: 'bulk-id',
        schedules: [
          {
            ...operationScheduleFactory.build({ target_id: host1.id }),
            warnings: [warning],
          },
          {
            ...operationScheduleFactory.build({ target_id: host2.id }),
            warnings: [],
          },
        ],
      });

      const dispatched = await recordSaga(
        bulkScheduleOperation,
        { payload: { request } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmitted({
          operation: 'reboot',
          warnings: [{ ...warning, targetName: host1.hostname }],
        }),
        notify({
          text: 'Operation Reboot host scheduled for 2 hosts',
          icon: '📅',
        }),
      ]);
    });

    it('should tell the targets that already have a schedule of the operation', async () => {
      const existing = operationScheduleFactory.buildList(1, {
        target_id: host2.id,
        operation: 'reboot',
      });
      axiosMock
        .onGet('/operation_schedules', { params: lookupParams })
        .reply(200, existing);

      const dispatched = await recordSaga(
        bulkScheduleOperation,
        { payload: { request } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleConflicts({ conflicts: existing }),
      ]);
      expect(axiosMock.history.post).toHaveLength(0);
    });

    it('should create the schedules once confirmed', async () => {
      axiosMock
        .onPost('/operation_schedules/bulk')
        .reply(201, { bulk_id: 'bulk-id', schedules: [] });

      const dispatched = await recordSaga(
        bulkScheduleOperation,
        { payload: { request, confirmed: true } },
        state
      );

      expect(axiosMock.history.get).toHaveLength(0);
      expect(dispatched).toContainEqual(
        setOperationScheduleSubmitted({ operation: 'reboot', warnings: [] })
      );
    });

    it('should keep the errors when the existing schedules cannot be looked up', async () => {
      axiosMock.onGet('/operation_schedules').reply(500);

      const dispatched = await recordSaga(
        bulkScheduleOperation,
        { payload: { request } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmissionErrors({ errors: [defaultGlobalError] }),
      ]);
    });

    it('should keep the errors of a refused bulk schedule', async () => {
      const errors = [
        {
          title: 'Invalid value',
          detail: 'must be in the future',
          source: { pointer: '/starts_at' },
        },
      ];
      axiosMock.onPost('/operation_schedules/bulk').reply(422, { errors });

      const dispatched = await recordSaga(
        bulkScheduleOperation,
        { payload: { request, confirmed: true } },
        state
      );

      expect(dispatched).toEqual([
        startOperationScheduleSubmission(),
        setOperationScheduleSubmissionErrors({ errors }),
      ]);
    });
  });
});
