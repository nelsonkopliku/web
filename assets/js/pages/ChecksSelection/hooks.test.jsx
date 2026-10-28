// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { act, renderHook, waitFor } from '@testing-library/react';
import { faker } from '@faker-js/faker';
import MockAdapter from 'axios-mock-adapter';
import { every, has } from 'lodash';
import { hookWrapperWithState } from '@lib/test-utils';

import { networkClient } from '@lib/network';
import {
  checksScheduleFactory,
  selectableCheckFactory,
} from '@lib/test-utils/factories';
import lastExecutionsReducer, {
  setExecutionStarted,
} from '@state/lastExecutions';
import {
  GENERIC_FAILURE,
  INVALID_VALUES,
  READY,
  useChecksSchedule,
  useChecksSelection,
} from './hooks';

const axiosMock = new MockAdapter(networkClient);

const initializeChecksSelection = async (
  groupId,
  checksSelection,
  hookResult
) => {
  axiosMock
    .onGet(`/api/v1/groups/${groupId}/checks`)
    .reply(200, { items: checksSelection });

  await act(async () => {
    hookResult.current.fetchChecksSelection(groupId);
  });
};

describe('useChecksSelection', () => {
  afterEach(() => {
    axiosMock.reset();
  });

  it('should return default state', async () => {
    let hookResult;
    const [hookWrapper, _] = hookWrapperWithState();

    await act(async () => {
      const { result } = renderHook(() => useChecksSelection(), {
        wrapper: hookWrapper,
      });
      hookResult = result;
    });
    expect(hookResult.current.checksSelectionLoading).toBe(false);
    expect(hookResult.current.checksSelection).toEqual([]);
    expect(hookResult.current.checksSelectionFetchError).toEqual(null);
    expect(hookResult.current.customizationStatus).toBe(READY);
  });

  it.each`
    statusCode | expectedError
    ${500}     | ${'Request failed with status code 500'}
    ${404}     | ${'Request failed with status code 404'}
    ${400}     | ${'Request failed with status code 400'}
  `(
    'should handle failures while fetching checks selection',
    async ({ statusCode, expectedError }) => {
      let hookResult;
      const [hookWrapper, _] = hookWrapperWithState();

      const groupId = faker.string.uuid();

      await act(async () => {
        const { result } = renderHook(() => useChecksSelection(), {
          wrapper: hookWrapper,
        });
        hookResult = result;
      });

      axiosMock.onGet(`/api/v1/groups/${groupId}/checks`).reply(statusCode);

      await act(async () => {
        hookResult.current.fetchChecksSelection(groupId);
      });

      expect(hookResult.current.checksSelectionLoading).toBe(false);
      expect(hookResult.current.checksSelection).toEqual([]);
      expect(hookResult.current.checksSelectionFetchError).toEqual(
        expectedError
      );
    }
  );

  it('should successfully fetch checks selection', async () => {
    let hookResult;
    const [hookWrapper, _] = hookWrapperWithState();

    const groupId = faker.string.uuid();

    const checksSelection = selectableCheckFactory.buildList(3);

    await act(async () => {
      const { result } = renderHook(() => useChecksSelection(), {
        wrapper: hookWrapper,
      });
      hookResult = result;
    });

    axiosMock
      .onGet(`/api/v1/groups/${groupId}/checks`)
      .reply(200, { items: checksSelection });

    await act(async () => {
      hookResult.current.fetchChecksSelection(groupId);
    });

    expect(hookResult.current.checksSelectionLoading).toBe(false);
    expect(hookResult.current.checksSelection).toEqual(checksSelection);
    expect(hookResult.current.checksSelectionFetchError).toEqual(null);
  });

  it('should successfully save check customization', async () => {
    let hookResult;
    const [hookWrapper, store] = hookWrapperWithState();

    const customValue = { name: 'checkValueName', value: '222' };

    const checksSelection = [
      selectableCheckFactory.build({
        values: [{ name: customValue.name, default_value: '123' }],
        customized: false,
      }),
      selectableCheckFactory.build({ customized: false }),
    ];
    const groupID = faker.string.uuid();
    const checkID = checksSelection[0].id;

    await act(async () => {
      const { result } = renderHook(() => useChecksSelection(), {
        wrapper: hookWrapper,
      });
      hookResult = result;
    });

    await initializeChecksSelection(groupID, checksSelection, hookResult);

    const customValues = {
      values: [customValue],
    };

    axiosMock
      .onPost(
        `/api/v1/groups/${groupID}/checks/${checkID}/customization`,
        customValues
      )
      .reply(200, customValues);

    await act(async () => {
      hookResult.current.saveChecksCustomization(checkID, groupID, [
        customValue,
      ]);
    });
    const updatedChecksSelection = hookResult.current.checksSelection;

    expect(updatedChecksSelection.length).toEqual(checksSelection.length);

    updatedChecksSelection.forEach(({ id, customized, values }) => {
      if (id === checkID) {
        expect(customized).toBe(true);
        expect(values[0].name).toBe(customValue.name);
        expect(values[0].custom_value).toBe(customValue.value);
      } else {
        expect(customized).toBe(false);
      }
    });
    expect(store.getActions()).toEqual([
      {
        type: 'NOTIFICATION',
        payload: { text: `Check was customized successfully`, icon: '✅' },
      },
    ]);
  });

  it.each`
    statusCode | expectedState
    ${400}     | ${INVALID_VALUES}
    ${404}     | ${GENERIC_FAILURE}
    ${500}     | ${GENERIC_FAILURE}
    ${503}     | ${GENERIC_FAILURE}
  `(
    'should handle failures while saving check customization',
    async ({ statusCode, expectedState }) => {
      let hookResult;
      const [hookWrapper, store] = hookWrapperWithState();

      const checksSelection = selectableCheckFactory.buildList(3, {
        customized: false,
      });

      const groupId = faker.string.uuid();
      const checkId = faker.string.uuid();

      await act(async () => {
        const { result } = renderHook(() => useChecksSelection(), {
          wrapper: hookWrapper,
        });
        hookResult = result;
      });

      await initializeChecksSelection(groupId, checksSelection, hookResult);

      axiosMock
        .onPost(`/api/v1/groups/${groupId}/checks/${checkId}/customization`)
        .reply(statusCode);

      await act(async () => {
        hookResult.current.saveChecksCustomization(checkId, groupId, []);
      });

      const updatedChecksSelection = hookResult.current.checksSelection;

      expect(updatedChecksSelection.length).toEqual(checksSelection.length);

      updatedChecksSelection.forEach(({ customized }) =>
        expect(customized).toBe(false)
      );

      expect(hookResult.current.customizationStatus).toBe(expectedState);
      expect(store.getActions()).toEqual([
        {
          type: 'NOTIFICATION',
          payload: { text: `Failed to customize check`, icon: '❌' },
        },
      ]);
    }
  );

  it.each([400, 404, 500, 503])(
    'should handle failures while resetting check customization',
    async (statusCode) => {
      let hookResult;
      const [hookWrapper, store] = hookWrapperWithState();

      const checksSelection = selectableCheckFactory.buildList(3, {
        customized: true,
      });
      const groupId = faker.string.uuid();
      const checkId = checksSelection[0].id;

      await act(async () => {
        const { result } = renderHook(() => useChecksSelection(), {
          wrapper: hookWrapper,
        });
        hookResult = result;
      });

      await initializeChecksSelection(groupId, checksSelection, hookResult);

      axiosMock
        .onDelete(`/api/v1/groups/${groupId}/checks/${checkId}/customization`)
        .reply(statusCode);

      await act(async () => {
        hookResult.current.resetChecksCustomization(groupId, checkId);
      });

      const updatedChecksSelection = hookResult.current.checksSelection;

      expect(updatedChecksSelection.length).toEqual(checksSelection.length);

      updatedChecksSelection.forEach(({ customized }) =>
        expect(customized).toBe(true)
      );

      expect(store.getActions()).toEqual([
        {
          type: 'NOTIFICATION',
          payload: { text: `Unable to reset customization`, icon: '❌' },
        },
      ]);
    }
  );

  it('should successfully reset check customization', async () => {
    let hookResult;
    const [hookWrapper, store] = hookWrapperWithState();

    const checksSelection = selectableCheckFactory.buildList(3, {
      customized: true,
    });
    const groupId = faker.string.uuid();
    const checkId = checksSelection[0].id;

    await act(async () => {
      const { result } = renderHook(() => useChecksSelection(), {
        wrapper: hookWrapper,
      });
      hookResult = result;
    });

    await initializeChecksSelection(groupId, checksSelection, hookResult);

    axiosMock
      .onDelete(`/api/v1/groups/${groupId}/checks/${checkId}/customization`)
      .reply(204);

    await act(async () => {
      hookResult.current.resetChecksCustomization(groupId, checkId);
    });

    const updatedChecksSelection = hookResult.current.checksSelection;

    expect(updatedChecksSelection.length).toEqual(checksSelection.length);

    const doesNotHaveCustomValue = (value) => !has(value, 'custom_value');
    updatedChecksSelection.forEach(({ id, customized, values }) => {
      if (id === checkId) {
        expect(customized).toBe(false);
        expect(every(values, doesNotHaveCustomValue)).toBe(true);
      } else {
        expect(customized).toBe(true);
      }
    });

    expect(store.getActions()).toEqual([
      {
        type: 'NOTIFICATION',
        payload: { text: `Customization was reset!`, icon: '✅' },
      },
    ]);
  });
});

const renderScheduleHook = async (targetType, targetID) => {
  const store = configureStore({
    reducer: { lastExecutions: lastExecutionsReducer },
  });

  function wrapper({ children }) {
    return <Provider store={store}>{children}</Provider>;
  }

  const rendered = await act(() =>
    renderHook(() => useChecksSchedule(targetType, targetID), { wrapper })
  );

  return { ...rendered, store };
};

describe('useChecksSchedule', () => {
  const hostID = faker.string.uuid();
  const scheduleURL = `/api/v1/hosts/${hostID}/checks/schedule`;

  afterEach(() => {
    axiosMock.reset();
  });

  it('should fetch the checks schedule of the target', async () => {
    const schedule = checksScheduleFactory.build();
    axiosMock.onGet(scheduleURL).reply(200, schedule);

    const { result } = await renderScheduleHook('host', hostID);

    expect(result.current.schedule).toEqual(schedule);
    expect(result.current.fetchLoading).toBe(false);
    expect(result.current.fetchError).toBe(false);
  });

  it('should fetch the checks schedule of a cluster', async () => {
    const clusterID = faker.string.uuid();
    const schedule = checksScheduleFactory.build({ interval: '1w' });
    axiosMock
      .onGet(`/api/v1/clusters/${clusterID}/checks/schedule`)
      .reply(200, schedule);

    const { result } = await renderScheduleHook('cluster', clusterID);

    expect(result.current.schedule).toEqual(schedule);
  });

  it('should tell when the checks schedule cannot be fetched', async () => {
    axiosMock.onGet(scheduleURL).reply(500);

    const { result } = await renderScheduleHook('host', hostID);

    expect(result.current.schedule).toBeNull();
    expect(result.current.fetchError).toBe(true);
  });

  it('should not fetch anything without a target', async () => {
    const { result } = await renderScheduleHook('host', undefined);

    expect(axiosMock.history.get).toHaveLength(0);
    expect(result.current.schedule).toBeNull();
  });

  it('should fetch the checks schedule again when an execution of the target starts', async () => {
    const before = checksScheduleFactory.build();
    const after = checksScheduleFactory.build();
    axiosMock
      .onGet(scheduleURL)
      .replyOnce(200, before)
      .onGet(scheduleURL)
      .replyOnce(200, after);

    const { result, store } = await renderScheduleHook('host', hostID);
    expect(result.current.schedule).toEqual(before);

    await act(async () => {
      store.dispatch(setExecutionStarted({ groupID: hostID, targets: [] }));
    });

    expect(result.current.schedule).toEqual(after);
  });

  it('should keep the schedule shown, without loading, while it is fetched again', async () => {
    const before = checksScheduleFactory.build();
    const after = checksScheduleFactory.build();
    let replyAfter;
    axiosMock
      .onGet(scheduleURL)
      .replyOnce(200, before)
      .onGet(scheduleURL)
      .replyOnce(
        () =>
          new Promise((resolve) => {
            replyAfter = () => resolve([200, after]);
          })
      );

    const { result, store } = await renderScheduleHook('host', hostID);

    await act(async () => {
      store.dispatch(setExecutionStarted({ groupID: hostID, targets: [] }));
    });
    await waitFor(() => expect(replyAfter).toBeDefined());

    expect(result.current.fetchLoading).toBe(false);
    expect(result.current.schedule).toEqual(before);

    await act(async () => replyAfter());

    expect(result.current.schedule).toEqual(after);
  });

  it('should keep the latest schedule when the responses arrive out of order', async () => {
    const stale = checksScheduleFactory.build();
    const latest = checksScheduleFactory.build();
    let replyStale;
    axiosMock
      .onGet(scheduleURL)
      .replyOnce(
        () =>
          new Promise((resolve) => {
            replyStale = () => resolve([200, stale]);
          })
      )
      .onGet(scheduleURL)
      .replyOnce(200, latest);

    const { result } = await renderScheduleHook('host', hostID);
    await act(() => result.current.fetchSchedule());

    expect(result.current.schedule).toEqual(latest);

    await waitFor(() => expect(replyStale).toBeDefined());
    await act(async () => replyStale());

    expect(result.current.schedule).toEqual(latest);
    expect(result.current.fetchLoading).toBe(false);
  });

  it('should save the frequency of the target', async () => {
    axiosMock.onGet(scheduleURL).reply(200, checksScheduleFactory.build());
    const saved = checksScheduleFactory.build({
      interval: '6h',
      effective_interval: '6h',
    });
    axiosMock.onPut(scheduleURL, { interval: '6h' }).reply(200, saved);

    const { result } = await renderScheduleHook('host', hostID);
    let succeeded;
    await act(async () => {
      succeeded = await result.current.saveSchedule({ interval: '6h' });
    });

    expect(succeeded).toBe(true);
    expect(result.current.schedule).toEqual(saved);
    expect(result.current.submitErrors).toEqual([]);
    expect(result.current.submitLoading).toBe(false);
  });

  it('should keep the checks schedule and tell the errors of a refused change', async () => {
    const schedule = checksScheduleFactory.build();
    const errors = [
      {
        title: 'Invalid value',
        detail: 'is invalid',
        source: { pointer: '/interval' },
      },
    ];
    axiosMock.onGet(scheduleURL).reply(200, schedule);
    axiosMock.onPut(scheduleURL).reply(422, { errors });

    const { result } = await renderScheduleHook('host', hostID);
    let succeeded;
    await act(async () => {
      succeeded = await result.current.saveSchedule({ interval: '7m' });
    });

    expect(succeeded).toBe(false);
    expect(result.current.schedule).toEqual(schedule);
    expect(result.current.submitErrors).toEqual(errors);

    act(() => result.current.clearSubmitErrors());
    expect(result.current.submitErrors).toEqual([]);
  });

  it('should tell an unexpected error when a change fails without details', async () => {
    axiosMock.onGet(scheduleURL).reply(200, checksScheduleFactory.build());
    axiosMock.onPut(scheduleURL).networkError();

    const { result } = await renderScheduleHook('host', hostID);
    await act(() => result.current.saveSchedule({ interval: '6h' }));

    expect(result.current.submitErrors).toEqual([
      { title: 'Unexpected error', detail: 'Something went wrong.' },
    ]);
  });
});
