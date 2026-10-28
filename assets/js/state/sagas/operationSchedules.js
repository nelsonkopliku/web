// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { call, put, select, takeEvery } from 'redux-saga/effects';
import { get, has, sortBy } from 'lodash';

import {
  createOperationSchedule,
  deleteOperationSchedule,
  getOperationSchedules,
  updateOperationSchedule as updateOperationScheduleRequest,
} from '@lib/api/operationSchedules';
import { defaultGlobalError } from '@lib/api/validationErrors';
import { getOperationLabel } from '@lib/operations';

import { notify } from '@state/notifications';
import { OPERATION_COMPLETED } from '@state/runningOperations';
import {
  CANCEL_OPERATION_SCHEDULE,
  FETCH_OPERATION_SCHEDULES,
  OPERATION_SCHEDULES_CHANGED,
  SCHEDULE_OPERATION,
  UPDATE_OPERATION_SCHEDULE,
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

function* notifyScheduleChange(schedule, change, icon) {
  const { target_type: targetType, target_id: targetID, operation } = schedule;
  const targetName = yield call(getTargetName, targetType, targetID);

  yield put(
    notify({
      text: `Schedule of operation ${getOperationLabel(operation)} for ${targetName} ${change}`,
      icon,
    })
  );
}

export function* updateOperationSchedule({ payload: { schedule, changes } }) {
  yield put(startOperationScheduleSubmission());

  try {
    const {
      data: { warnings },
    } = yield call(updateOperationScheduleRequest, schedule.id, changes);

    yield put(
      setOperationScheduleSubmitted({ operation: schedule.operation, warnings })
    );
    yield call(notifyScheduleChange, schedule, 'changed', '📅');
    yield put(fetchOperationSchedulesAction({ targetID: schedule.target_id }));
  } catch (error) {
    yield put(
      setOperationScheduleSubmissionErrors({ errors: requestErrors(error) })
    );
  }
}

export function* cancelOperationSchedule({ payload: { schedule } }) {
  yield put(startOperationScheduleSubmission());

  try {
    yield call(deleteOperationSchedule, schedule.id);

    yield put(setOperationScheduleSubmitted({ operation: schedule.operation }));
    yield call(notifyScheduleChange, schedule, 'cancelled', '🗑️');
    yield put(fetchOperationSchedulesAction({ targetID: schedule.target_id }));
  } catch (error) {
    yield put(
      setOperationScheduleSubmissionErrors({ errors: requestErrors(error) })
    );
  }
}

// The schedules of a target change after any change, run, or end of one of
// them, also by other users: the displayed targets are fetched again.
// Operations name their target groupID.
export function* refreshOperationSchedules({ payload: { targetID, groupID } }) {
  const id = targetID ?? groupID;
  const displayed = yield select((state) =>
    has(state, ['operationSchedules', 'byTarget', id])
  );

  if (displayed) yield put(fetchOperationSchedulesAction({ targetID: id }));
}

export function* watchOperationSchedules() {
  yield takeEvery(FETCH_OPERATION_SCHEDULES, fetchOperationSchedules);
  yield takeEvery(SCHEDULE_OPERATION, scheduleOperation);
  yield takeEvery(UPDATE_OPERATION_SCHEDULE, updateOperationSchedule);
  yield takeEvery(CANCEL_OPERATION_SCHEDULE, cancelOperationSchedule);
  yield takeEvery(
    [OPERATION_SCHEDULES_CHANGED, OPERATION_COMPLETED],
    refreshOperationSchedules
  );
}
