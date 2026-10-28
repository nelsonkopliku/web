// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { createAction, createSlice } from '@reduxjs/toolkit';

export const SUBMISSION_IDLE = 'idle';
export const SUBMISSION_SUBMITTING = 'submitting';
export const SUBMISSION_SUCCEEDED = 'succeeded';
export const SUBMISSION_FAILED = 'failed';

export const initialScheduleSubmission = {
  status: SUBMISSION_IDLE,
  operation: null,
  errors: [],
  warnings: [],
};

const initialState = {
  // Schedules of the targets shown in the details views, by target id
  byTarget: {},
  // The schedule being created, changed or cancelled from a modal
  submission: initialScheduleSubmission,
};

const initialTargetState = { loading: false, error: false, schedules: [] };

export const isSubmittingSchedule = ({ status }) =>
  status === SUBMISSION_SUBMITTING;

export const isScheduleSubmitted = ({ status }) =>
  status === SUBMISSION_SUCCEEDED;

export const hasScheduleWarnings = (submission) =>
  isScheduleSubmitted(submission) && submission.warnings.length > 0;

export const operationSchedulesSlice = createSlice({
  name: 'operationSchedules',
  initialState,
  reducers: {
    startLoadingOperationSchedules: (state, { payload: { targetID } }) => {
      state.byTarget[targetID] = {
        ...initialTargetState,
        ...state.byTarget[targetID],
        loading: true,
        error: false,
      };
    },
    setOperationSchedules: (state, { payload: { targetID, schedules } }) => {
      state.byTarget[targetID] = { ...initialTargetState, schedules };
    },
    setOperationSchedulesError: (state, { payload: { targetID } }) => {
      state.byTarget[targetID] = { ...initialTargetState, error: true };
    },
    // The details view of the target is left: its schedules are not needed
    // anymore
    forgetOperationSchedules: (state, { payload: { targetID } }) => {
      delete state.byTarget[targetID];
    },
    startOperationScheduleSubmission: (state) => {
      state.submission = {
        ...initialScheduleSubmission,
        status: SUBMISSION_SUBMITTING,
      };
    },
    // A result only counts for the submission in progress: a reset one
    // belongs to a closed modal
    setOperationScheduleSubmitted: (
      state,
      { payload: { operation, warnings = [] } }
    ) => {
      if (!isSubmittingSchedule(state.submission)) return;

      state.submission = {
        ...initialScheduleSubmission,
        status: SUBMISSION_SUCCEEDED,
        operation,
        warnings,
      };
    },
    setOperationScheduleSubmissionErrors: (state, { payload: { errors } }) => {
      if (!isSubmittingSchedule(state.submission)) return;

      state.submission = {
        ...initialScheduleSubmission,
        status: SUBMISSION_FAILED,
        errors,
      };
    },
    resetOperationScheduleSubmission: (state) => {
      state.submission = initialScheduleSubmission;
    },
  },
});

export const FETCH_OPERATION_SCHEDULES = 'FETCH_OPERATION_SCHEDULES';
export const SCHEDULE_OPERATION = 'SCHEDULE_OPERATION';

export const fetchOperationSchedules = createAction(FETCH_OPERATION_SCHEDULES);
// Payload: the schedule request, with target_type, target_id, operation,
// params, starts_at, timezone and recurrence
export const scheduleOperation = createAction(SCHEDULE_OPERATION);

export const {
  startLoadingOperationSchedules,
  setOperationSchedules,
  setOperationSchedulesError,
  forgetOperationSchedules,
  startOperationScheduleSubmission,
  setOperationScheduleSubmitted,
  setOperationScheduleSubmissionErrors,
  resetOperationScheduleSubmission,
} = operationSchedulesSlice.actions;

export default operationSchedulesSlice.reducer;
