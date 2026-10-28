// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { act, renderHook } from '@testing-library/react';
import { faker } from '@faker-js/faker';

import { hookWrapperWithState } from '@lib/test-utils';
import { maintenanceWindowFactory } from '@lib/test-utils/factories';
import {
  deleteMaintenanceWindow,
  fetchMaintenanceWindows,
  forgetMaintenanceWindows,
  initialWindowSubmission,
  resetMaintenanceWindowSubmission,
  scheduleMaintenanceWindow,
  updateMaintenanceWindow,
} from '@state/maintenanceWindows';

import { useMaintenanceWindows } from './hooks';

const stateWith = (targetID, windows) => ({
  maintenanceWindows: {
    byTarget: {
      [targetID]: { targetType: 'host', loading: false, error: false, windows },
    },
    submission: initialWindowSubmission,
  },
});

describe('useMaintenanceWindows', () => {
  const hostID = faker.string.uuid();

  it('should fetch the windows of the target, and forget them when not displayed anymore', () => {
    const windows = maintenanceWindowFactory.buildList(1);
    const [wrapper, store] = hookWrapperWithState(stateWith(hostID, windows));

    const { result, unmount } = renderHook(
      () => useMaintenanceWindows('host', hostID),
      { wrapper }
    );

    expect(result.current.windows).toEqual(windows);
    expect(store.getActions()).toEqual([
      fetchMaintenanceWindows({ targetType: 'host', targetID: hostID }),
    ]);

    unmount();

    expect(store.getActions()).toContainEqual(
      forgetMaintenanceWindows({ targetID: hostID })
    );
    expect(store.getActions()).toContainEqual(
      resetMaintenanceWindowSubmission()
    );
  });

  it('should schedule, change and delete the windows of the target', () => {
    const window = maintenanceWindowFactory.build();
    const [wrapper, store] = hookWrapperWithState(stateWith(hostID, [window]));

    const { result } = renderHook(() => useMaintenanceWindows('host', hostID), {
      wrapper,
    });

    const request = {
      starts_at: '2099-11-20T22:00:00.000Z',
      timezone: 'Etc/UTC',
      duration_minutes: 60,
      recurrence: null,
      forbids: ['operations'],
    };

    act(() => result.current.onSchedule(request));
    act(() => result.current.onUpdate(window, request));
    act(() => result.current.onDelete(window));

    expect(store.getActions()).toEqual(
      expect.arrayContaining([
        scheduleMaintenanceWindow({
          request: { target_type: 'host', target_id: hostID, ...request },
        }),
        updateMaintenanceWindow({ window, changes: request }),
        deleteMaintenanceWindow({ window }),
      ])
    );
  });

  it('should fetch the windows again when a window starts or ends', async () => {
    jest.useFakeTimers({ now: new Date('2026-11-20T10:00:00Z') });

    try {
      const window = maintenanceWindowFactory.build({
        active: false,
        current_occurrence: null,
        next_occurrence: {
          starts_at: '2026-11-20T10:05:00Z',
          ends_at: '2026-11-20T11:05:00Z',
        },
      });
      const [wrapper, store] = hookWrapperWithState(
        stateWith(hostID, [window])
      );

      renderHook(() => useMaintenanceWindows('host', hostID), { wrapper });

      await act(async () => {
        await jest.advanceTimersByTimeAsync(4 * 60 * 1000);
      });
      expect(store.getActions()).toHaveLength(1);

      await act(async () => {
        await jest.advanceTimersByTimeAsync(2 * 60 * 1000);
      });
      expect(store.getActions()).toEqual([
        fetchMaintenanceWindows({ targetType: 'host', targetID: hostID }),
        fetchMaintenanceWindows({ targetType: 'host', targetID: hostID }),
      ]);
    } finally {
      jest.useRealTimers();
    }
  });
});
