// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { networkClient } from '@lib/network';

const windowsPath = '/maintenance_windows';

// The windows of the target and the ones it inherits from the targets that
// cover it
export const getMaintenanceWindows = (targetType, targetID) =>
  networkClient.get(windowsPath, {
    params: { target_type: targetType, target_id: targetID },
  });

export const createMaintenanceWindow = (window) =>
  networkClient.post(windowsPath, window);

export const createBulkMaintenanceWindows = (request) =>
  networkClient.post(`${windowsPath}/bulk`, request);

export const updateMaintenanceWindow = (windowID, changes) =>
  networkClient.put(`${windowsPath}/${windowID}`, changes);

export const deleteMaintenanceWindow = (windowID) =>
  networkClient.delete(`${windowsPath}/${windowID}`);
