// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { createAction, createSlice } from '@reduxjs/toolkit';

export const WINDOW_SUBMISSION_IDLE = 'idle';
export const WINDOW_SUBMISSION_SUBMITTING = 'submitting';
export const WINDOW_SUBMISSION_SUCCEEDED = 'succeeded';
export const WINDOW_SUBMISSION_FAILED = 'failed';

export const initialWindowSubmission = {
  status: WINDOW_SUBMISSION_IDLE,
  errors: [],
};

const initialState = {
  // Windows covering the targets shown in the details views, by target id
  byTarget: {},
  // The window being scheduled, changed or deleted from a modal
  submission: initialWindowSubmission,
};

const initialTargetState = { loading: false, error: false, windows: [] };

export const isSubmittingWindow = ({ status }) =>
  status === WINDOW_SUBMISSION_SUBMITTING;

export const isWindowSubmitted = ({ status }) =>
  status === WINDOW_SUBMISSION_SUCCEEDED;

export const maintenanceWindowsSlice = createSlice({
  name: 'maintenanceWindows',
  initialState,
  reducers: {
    startLoadingMaintenanceWindows: (
      state,
      { payload: { targetType, targetID } }
    ) => {
      state.byTarget[targetID] = {
        ...initialTargetState,
        ...state.byTarget[targetID],
        targetType,
        loading: true,
        error: false,
      };
    },
    setMaintenanceWindows: (
      state,
      { payload: { targetType, targetID, windows } }
    ) => {
      state.byTarget[targetID] = { ...initialTargetState, targetType, windows };
    },
    setMaintenanceWindowsError: (
      state,
      { payload: { targetType, targetID } }
    ) => {
      state.byTarget[targetID] = {
        ...initialTargetState,
        targetType,
        error: true,
      };
    },
    forgetMaintenanceWindows: (state, { payload: { targetID } }) => {
      delete state.byTarget[targetID];
    },
    startMaintenanceWindowSubmission: (state) => {
      state.submission = {
        ...initialWindowSubmission,
        status: WINDOW_SUBMISSION_SUBMITTING,
      };
    },
    // A result only counts for the submission in progress: a reset one
    // belongs to a closed modal
    setMaintenanceWindowSubmitted: (state) => {
      if (!isSubmittingWindow(state.submission)) return;

      state.submission = {
        ...initialWindowSubmission,
        status: WINDOW_SUBMISSION_SUCCEEDED,
      };
    },
    setMaintenanceWindowSubmissionErrors: (state, { payload: { errors } }) => {
      if (!isSubmittingWindow(state.submission)) return;

      state.submission = {
        ...initialWindowSubmission,
        status: WINDOW_SUBMISSION_FAILED,
        errors,
      };
    },
    resetMaintenanceWindowSubmission: (state) => {
      state.submission = initialWindowSubmission;
    },
  },
});

export const FETCH_MAINTENANCE_WINDOWS = 'FETCH_MAINTENANCE_WINDOWS';
export const SCHEDULE_MAINTENANCE_WINDOW = 'SCHEDULE_MAINTENANCE_WINDOW';
export const UPDATE_MAINTENANCE_WINDOW = 'UPDATE_MAINTENANCE_WINDOW';
export const DELETE_MAINTENANCE_WINDOW = 'DELETE_MAINTENANCE_WINDOW';
export const MAINTENANCE_WINDOWS_CHANGED = 'MAINTENANCE_WINDOWS_CHANGED';
export const BULK_SCHEDULE_MAINTENANCE_WINDOWS =
  'BULK_SCHEDULE_MAINTENANCE_WINDOWS';

// Payload: { targetType, targetID }
export const fetchMaintenanceWindows = createAction(FETCH_MAINTENANCE_WINDOWS);
// Payload: { request }, with target_type, target_id, starts_at, timezone,
// duration_minutes, recurrence and forbids
export const scheduleMaintenanceWindow = createAction(
  SCHEDULE_MAINTENANCE_WINDOW
);
// Payload: { window, changes }, the window and its new starts_at, timezone,
// duration_minutes, recurrence and forbids
export const updateMaintenanceWindow = createAction(UPDATE_MAINTENANCE_WINDOW);
// Payload: { window }
export const deleteMaintenanceWindow = createAction(DELETE_MAINTENANCE_WINDOW);
// Payload: { request }, with target_type, target_ids, starts_at, timezone,
// duration_minutes, recurrence and forbids: one window per target
export const bulkScheduleMaintenanceWindows = createAction(
  BULK_SCHEDULE_MAINTENANCE_WINDOWS
);
// Payload: { targetType, targetID }, broadcast by the server after any change
// of the windows of a target
export const maintenanceWindowsChanged = createAction(
  MAINTENANCE_WINDOWS_CHANGED
);

export const {
  startLoadingMaintenanceWindows,
  setMaintenanceWindows,
  setMaintenanceWindowsError,
  forgetMaintenanceWindows,
  startMaintenanceWindowSubmission,
  setMaintenanceWindowSubmitted,
  setMaintenanceWindowSubmissionErrors,
  resetMaintenanceWindowSubmission,
} = maintenanceWindowsSlice.actions;

export default maintenanceWindowsSlice.reducer;
