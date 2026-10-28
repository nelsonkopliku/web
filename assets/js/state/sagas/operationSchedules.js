// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { call, put, select, takeEvery } from 'redux-saga/effects';
import { get, sortBy } from 'lodash';

import {
  createOperationSchedule,
  getOperationSchedules,
} from '@lib/api/operationSchedules';
import { defaultGlobalError } from '@lib/api/validationErrors';
import { getOperationLabel } from '@lib/operations';

import { notify } from '@state/notifications';
import {
  FETCH_OPERATION_SCHEDULES,
  SCHEDULE_OPERATION,
  fetchOperationSchedules as fetchOperationSchedulesAction,
  setOperationScheduleSubmissionErrors,
  setOperationScheduleSubmitted,
  setOperationSchedules,
  setOperationSchedulesError,
  startLoadingOperationSchedules,
  startOperationScheduleSubmission,
} from '@state/operationSchedules';
import { getCluster } from '@state/selectors/cluster';
import { getHost } from '@state/selectors/host';
import { getDatabase, getSapSystem } from '@state/selectors/sapSystem';

const targetNameSelectors = {
  host: (id) => (state) => getHost(id)(state)?.hostname,
  cluster: (id) => (state) => getCluster(id)(state)?.name,
  sap_system: (id) => (state) => getSapSystem(id)(state)?.sid,
  database: (id) => (state) => getDatabase(id)(state)?.sid,
};

export function* getTargetName(targetType, targetID) {
  const selector = targetNameSelectors[targetType];

  return (selector && (yield select(selector(targetID)))) || 'unknown';
}

const requestErrors = (error) =>
  get(error, ['response', 'data', 'errors'], [defaultGlobalError]);

export function* fetchOperationSchedules({ payload: { targetID } }) {
  yield put(startLoadingOperationSchedules({ targetID }));

  try {
    const { data } = yield call(getOperationSchedules, targetID);
    yield put(
      setOperationSchedules({
        targetID,
        schedules: sortBy(data, 'next_run_at'),
      })
    );
  } catch {
    yield put(setOperationSchedulesError({ targetID }));
  }
}

export function* scheduleOperation({ payload: request }) {
  const { target_type: targetType, target_id: targetID, operation } = request;

  yield put(startOperationScheduleSubmission());

  try {
    const {
      data: { warnings },
    } = yield call(createOperationSchedule, request);
    const targetName = yield call(getTargetName, targetType, targetID);

    yield put(setOperationScheduleSubmitted({ operation, warnings }));
    yield put(
      notify({
        text: `Operation ${getOperationLabel(operation)} scheduled for ${targetName}`,
        icon: '📅',
      })
    );
    yield put(fetchOperationSchedulesAction({ targetID }));
  } catch (error) {
    yield put(
      setOperationScheduleSubmissionErrors({ errors: requestErrors(error) })
    );
  }
}

export function* watchOperationSchedules() {
  yield takeEvery(FETCH_OPERATION_SCHEDULES, fetchOperationSchedules);
  yield takeEvery(SCHEDULE_OPERATION, scheduleOperation);
}
