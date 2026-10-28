// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { all, call, put, select, takeEvery } from 'redux-saga/effects';
import { get, map } from 'lodash';

import {
  createBulkMaintenanceWindows,
  createMaintenanceWindow,
  deleteMaintenanceWindow as deleteMaintenanceWindowRequest,
  getMaintenanceWindows,
  updateMaintenanceWindow as updateMaintenanceWindowRequest,
} from '@lib/api/maintenanceWindows';
import { defaultGlobalError } from '@lib/api/validationErrors';
import { countTargets } from '@lib/operations';

import { notify } from '@state/notifications';
import {
  BULK_SCHEDULE_MAINTENANCE_WINDOWS,
  DELETE_MAINTENANCE_WINDOW,
  FETCH_MAINTENANCE_WINDOWS,
  MAINTENANCE_WINDOWS_CHANGED,
  SCHEDULE_MAINTENANCE_WINDOW,
  UPDATE_MAINTENANCE_WINDOW,
  fetchMaintenanceWindows as fetchMaintenanceWindowsAction,
  setMaintenanceWindowSubmissionErrors,
  setMaintenanceWindowSubmitted,
  setMaintenanceWindows,
  setMaintenanceWindowsError,
  startLoadingMaintenanceWindows,
  startMaintenanceWindowSubmission,
} from '@state/maintenanceWindows';
import { getTargetName } from '@state/sagas/operationSchedules';

const requestErrors = (error) =>
  get(error, ['response', 'data', 'errors'], [defaultGlobalError]);

export function* fetchMaintenanceWindows({
  payload: { targetType, targetID },
}) {
  yield put(startLoadingMaintenanceWindows({ targetType, targetID }));

  try {
    const { data: windows } = yield call(
      getMaintenanceWindows,
      targetType,
      targetID
    );
    yield put(setMaintenanceWindows({ targetType, targetID, windows }));
  } catch {
    yield put(setMaintenanceWindowsError({ targetType, targetID }));
  }
}

// A window covers other targets than its own: every displayed target is
// fetched again after a change of any window
export function* refreshMaintenanceWindows() {
  const displayed = yield select((state) =>
    get(state, ['maintenanceWindows', 'byTarget'], {})
  );

  yield all(
    map(displayed, ({ targetType }, targetID) =>
      put(fetchMaintenanceWindowsAction({ targetType, targetID }))
    )
  );
}

function* submitWindowChange(request, notification) {
  yield put(startMaintenanceWindowSubmission());

  try {
    yield request;
    yield put(setMaintenanceWindowSubmitted());
    yield put(notify(yield call(notification)));
    yield call(refreshMaintenanceWindows);
  } catch (error) {
    yield put(
      setMaintenanceWindowSubmissionErrors({ errors: requestErrors(error) })
    );
  }
}

export function* scheduleMaintenanceWindow({ payload: { request } }) {
  yield call(
    submitWindowChange,
    call(createMaintenanceWindow, request),
    function* scheduled() {
      const targetName = yield call(
        getTargetName,
        request.target_type,
        request.target_id
      );
      return {
        text: `Maintenance window scheduled for ${targetName}`,
        icon: '🛠️',
      };
    }
  );
}

export function* updateMaintenanceWindow({ payload: { window, changes } }) {
  yield call(
    submitWindowChange,
    call(updateMaintenanceWindowRequest, window.id, changes),
    () => ({
      text: `Maintenance window of ${window.target_name} changed`,
      icon: '🛠️',
    })
  );
}

export function* deleteMaintenanceWindow({ payload: { window } }) {
  yield call(
    submitWindowChange,
    call(deleteMaintenanceWindowRequest, window.id),
    () => ({
      text: `Maintenance window of ${window.target_name} deleted`,
      icon: '🗑️',
    })
  );
}

export function* bulkScheduleMaintenanceWindows({ payload: { request } }) {
  yield call(
    submitWindowChange,
    call(createBulkMaintenanceWindows, request),
    () => ({
      text: `Maintenance window scheduled for ${countTargets(request.target_ids.length, request.target_type)}`,
      icon: '🛠️',
    })
  );
}

export function* watchMaintenanceWindows() {
  yield takeEvery(FETCH_MAINTENANCE_WINDOWS, fetchMaintenanceWindows);
  yield takeEvery(SCHEDULE_MAINTENANCE_WINDOW, scheduleMaintenanceWindow);
  yield takeEvery(UPDATE_MAINTENANCE_WINDOW, updateMaintenanceWindow);
  yield takeEvery(DELETE_MAINTENANCE_WINDOW, deleteMaintenanceWindow);
  yield takeEvery(
    BULK_SCHEDULE_MAINTENANCE_WINDOWS,
    bulkScheduleMaintenanceWindows
  );
  yield takeEvery(MAINTENANCE_WINDOWS_CHANGED, refreshMaintenanceWindows);
}
