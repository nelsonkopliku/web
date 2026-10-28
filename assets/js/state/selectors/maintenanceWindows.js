// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { createSelector } from '@reduxjs/toolkit';
import { get } from 'lodash';

import { initialWindowSubmission } from '@state/maintenanceWindows';

const noWindows = { loading: false, error: false, windows: [] };

const getMaintenanceWindowsState = ({ maintenanceWindows }) =>
  maintenanceWindows;

export const getMaintenanceWindows = (targetID) =>
  createSelector([getMaintenanceWindowsState], (maintenanceWindows) =>
    get(maintenanceWindows, ['byTarget', targetID], noWindows)
  );

export const getMaintenanceWindowSubmission = createSelector(
  [getMaintenanceWindowsState],
  (maintenanceWindows) =>
    get(maintenanceWindows, 'submission', initialWindowSubmission)
);
