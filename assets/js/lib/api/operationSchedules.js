// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { networkClient } from '@lib/network';

const schedulesPath = '/operation_schedules';

export const getOperationSchedules = (targetID) =>
  networkClient.get(schedulesPath, { params: { target_id: targetID } });

// The schedules of one operation on several targets, before a bulk request
export const getOperationSchedulesOfTargets = (targetIDs, operation) =>
  networkClient.get(schedulesPath, {
    params: { target_ids: targetIDs.join(','), operation },
  });

export const createOperationSchedule = (schedule) =>
  networkClient.post(schedulesPath, schedule);

export const createBulkOperationSchedules = (schedule) =>
  networkClient.post(`${schedulesPath}/bulk`, schedule);

export const updateOperationSchedule = (scheduleID, schedule) =>
  networkClient.put(`${schedulesPath}/${scheduleID}`, schedule);

export const deleteOperationSchedule = (scheduleID) =>
  networkClient.delete(`${schedulesPath}/${scheduleID}`);
