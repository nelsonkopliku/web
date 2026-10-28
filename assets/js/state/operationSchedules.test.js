// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { faker } from '@faker-js/faker';

import {
  operationScheduleFactory,
  policyWarningFactory,
} from '@lib/test-utils/factories';

import operationSchedulesReducer, {
  forgetOperationSchedules,
  SUBMISSION_CONFLICTS,
  SUBMISSION_FAILED,
  SUBMISSION_IDLE,
  SUBMISSION_SUBMITTING,
  SUBMISSION_SUCCEEDED,
  resetOperationScheduleSubmission,
  setOperationScheduleConflicts,
  setOperationScheduleSubmissionErrors,
  setOperationScheduleSubmitted,
  setOperationSchedules,
  setOperationSchedulesError,
  startLoadingOperationSchedules,
  startOperationScheduleSubmission,
} from './operationSchedules';

const idleSubmission = {
  status: SUBMISSION_IDLE,
  operation: null,
  errors: [],
  warnings: [],
  conflicts: [],
};

describe('operationSchedules reducer', () => {
  const targetID = faker.string.uuid();

  it('should load the schedules of a target, keeping the ones known', () => {
    const schedules = operationScheduleFactory.buildList(2);
    const state = {
      byTarget: { [targetID]: { loading: false, error: true, schedules } },
      submission: idleSubmission,
    };

    expect(
      operationSchedulesReducer(
        state,
        startLoadingOperationSchedules({ targetID })
      ).byTarget[targetID]
    ).toEqual({ loading: true, error: false, schedules });
  });

  it('should set the schedules of a target', () => {
    const schedules = operationScheduleFactory.buildList(2);

    expect(
      operationSchedulesReducer(
        undefined,
        setOperationSchedules({ targetID, schedules })
      )
    ).toEqual({
      byTarget: { [targetID]: { loading: false, error: false, schedules } },
      submission: idleSubmission,
    });
  });

  it('should tell when the schedules of a target cannot be loaded', () => {
    expect(
      operationSchedulesReducer(
        undefined,
        setOperationSchedulesError({ targetID })
      ).byTarget[targetID]
    ).toEqual({ loading: false, error: true, schedules: [] });
  });

  it('should forget the schedules of a target that is not shown anymore', () => {
    const otherTargetID = faker.string.uuid();
    const schedules = operationScheduleFactory.buildList(1);
    const state = {
      byTarget: {
        [targetID]: { loading: false, error: false, schedules },
        [otherTargetID]: { loading: false, error: false, schedules },
      },
      submission: idleSubmission,
    };

    expect(
      operationSchedulesReducer(state, forgetOperationSchedules({ targetID }))
        .byTarget
    ).toEqual({
      [otherTargetID]: { loading: false, error: false, schedules },
    });
  });

  it('should follow the submission of a schedule', () => {
    const warnings = policyWarningFactory.buildList(1);
    const errors = [{ title: 'Invalid value', detail: 'is invalid' }];

    const submitting = operationSchedulesReducer(
      {
        byTarget: {},
        submission: { ...idleSubmission, status: SUBMISSION_FAILED, errors },
      },
      startOperationScheduleSubmission()
    );
    expect(submitting.submission).toEqual({
      ...idleSubmission,
      status: SUBMISSION_SUBMITTING,
    });

    expect(
      operationSchedulesReducer(
        submitting,
        setOperationScheduleSubmitted({ operation: 'reboot', warnings })
      ).submission
    ).toEqual({
      ...idleSubmission,
      status: SUBMISSION_SUCCEEDED,
      operation: 'reboot',
      warnings,
    });

    const failed = operationSchedulesReducer(
      submitting,
      setOperationScheduleSubmissionErrors({ errors })
    );
    expect(failed.submission).toEqual({
      ...idleSubmission,
      status: SUBMISSION_FAILED,
      errors,
    });

    expect(
      operationSchedulesReducer(failed, resetOperationScheduleSubmission())
        .submission
    ).toEqual(idleSubmission);
  });

  it('should ignore the result of a submission that was reset', () => {
    // The modal was closed while its request was running, and another one
    // opened: the late result must not close it or show its errors there
    const state = { byTarget: {}, submission: idleSubmission };

    expect(
      operationSchedulesReducer(
        state,
        setOperationScheduleSubmitted({ operation: 'reboot' })
      ).submission
    ).toEqual(idleSubmission);
    expect(
      operationSchedulesReducer(
        state,
        setOperationScheduleSubmissionErrors({
          errors: [{ title: 'Invalid value', detail: 'is invalid' }],
        })
      ).submission
    ).toEqual(idleSubmission);
  });

  it('should tell the targets that already have a schedule of the operation', () => {
    const conflicts = operationScheduleFactory.buildList(2);
    const submitting = operationSchedulesReducer(
      undefined,
      startOperationScheduleSubmission()
    );

    expect(
      operationSchedulesReducer(
        submitting,
        setOperationScheduleConflicts({ conflicts })
      ).submission
    ).toEqual({
      ...idleSubmission,
      status: SUBMISSION_CONFLICTS,
      conflicts,
    });
  });

  it('should ignore the conflicts of a submission that was reset', () => {
    expect(
      operationSchedulesReducer(
        undefined,
        setOperationScheduleConflicts({
          conflicts: operationScheduleFactory.buildList(1),
        })
      ).submission
    ).toEqual(idleSubmission);
  });
});
