// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { createSelector } from '@reduxjs/toolkit';
import { get } from 'lodash';

import { initialScheduleSubmission } from '@state/operationSchedules';

const noSchedules = { loading: false, error: false, schedules: [] };

const getOperationSchedulesState = ({ operationSchedules }) =>
  operationSchedules;

export const getOperationSchedules = (targetID) =>
  createSelector([getOperationSchedulesState], (operationSchedules) =>
    get(operationSchedules, ['byTarget', targetID], noSchedules)
  );

export const getOperationScheduleSubmission = createSelector(
  [getOperationSchedulesState],
  (operationSchedules) =>
    get(operationSchedules, 'submission', initialScheduleSubmission)
);
