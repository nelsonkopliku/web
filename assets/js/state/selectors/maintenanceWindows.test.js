// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { maintenanceWindowFactory } from '@lib/test-utils/factories';
import { initialWindowSubmission } from '@state/maintenanceWindows';

import {
  getMaintenanceWindowSubmission,
  getMaintenanceWindows,
} from './maintenanceWindows';

describe('maintenance windows selectors', () => {
  it('should get the windows of a target', () => {
    const windows = maintenanceWindowFactory.buildList(2);
    const target = {
      targetType: 'host',
      loading: false,
      error: false,
      windows,
    };

    expect(
      getMaintenanceWindows('target')({
        maintenanceWindows: { byTarget: { target } },
      })
    ).toEqual(target);
  });

  it('should get no windows without the state of the windows', () => {
    expect(getMaintenanceWindows('target')({})).toEqual({
      loading: false,
      error: false,
      windows: [],
    });
    expect(getMaintenanceWindowSubmission({})).toEqual(initialWindowSubmission);
  });
});
