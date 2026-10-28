// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { faker } from '@faker-js/faker';

import { maintenanceWindowFactory } from '@lib/test-utils/factories';

import maintenanceWindowsReducer, {
  WINDOW_SUBMISSION_FAILED,
  WINDOW_SUBMISSION_SUBMITTING,
  WINDOW_SUBMISSION_SUCCEEDED,
  forgetMaintenanceWindows,
  initialWindowSubmission,
  resetMaintenanceWindowSubmission,
  setMaintenanceWindowSubmissionErrors,
  setMaintenanceWindowSubmitted,
  setMaintenanceWindows,
  setMaintenanceWindowsError,
  startLoadingMaintenanceWindows,
  startMaintenanceWindowSubmission,
} from './maintenanceWindows';

describe('maintenanceWindows reducer', () => {
  const targetID = faker.string.uuid();

  it('should load the windows of a target, keeping the ones known', () => {
    const windows = maintenanceWindowFactory.buildList(2);
    const state = {
      byTarget: {
        [targetID]: {
          targetType: 'host',
          loading: false,
          error: true,
          windows,
        },
      },
      submission: initialWindowSubmission,
    };

    expect(
      maintenanceWindowsReducer(
        state,
        startLoadingMaintenanceWindows({ targetType: 'host', targetID })
      ).byTarget[targetID]
    ).toEqual({ targetType: 'host', loading: true, error: false, windows });
  });

  it('should set the windows of a target', () => {
    const windows = maintenanceWindowFactory.buildList(2);

    expect(
      maintenanceWindowsReducer(
        undefined,
        setMaintenanceWindows({ targetType: 'cluster', targetID, windows })
      ).byTarget[targetID]
    ).toEqual({ targetType: 'cluster', loading: false, error: false, windows });
  });

  it('should tell when the windows of a target cannot be loaded', () => {
    expect(
      maintenanceWindowsReducer(
        undefined,
        setMaintenanceWindowsError({ targetType: 'host', targetID })
      ).byTarget[targetID]
    ).toEqual({ targetType: 'host', loading: false, error: true, windows: [] });
  });

  it('should forget a target that is not displayed anymore', () => {
    const state = maintenanceWindowsReducer(
      undefined,
      setMaintenanceWindows({ targetType: 'host', targetID, windows: [] })
    );

    expect(
      maintenanceWindowsReducer(state, forgetMaintenanceWindows({ targetID }))
        .byTarget
    ).toEqual({});
  });

  it('should follow the submission of a window', () => {
    const errors = [{ title: 'Forbidden', detail: 'Not allowed' }];

    const submitting = maintenanceWindowsReducer(
      undefined,
      startMaintenanceWindowSubmission()
    );
    expect(submitting.submission).toEqual({
      ...initialWindowSubmission,
      status: WINDOW_SUBMISSION_SUBMITTING,
    });

    expect(
      maintenanceWindowsReducer(submitting, setMaintenanceWindowSubmitted())
        .submission
    ).toEqual({
      ...initialWindowSubmission,
      status: WINDOW_SUBMISSION_SUCCEEDED,
    });

    const failed = maintenanceWindowsReducer(
      submitting,
      setMaintenanceWindowSubmissionErrors({ errors })
    );
    expect(failed.submission).toEqual({
      ...initialWindowSubmission,
      status: WINDOW_SUBMISSION_FAILED,
      errors,
    });

    expect(
      maintenanceWindowsReducer(failed, resetMaintenanceWindowSubmission())
        .submission
    ).toEqual(initialWindowSubmission);
  });

  it('should ignore the result of a submission that was reset', () => {
    // The modal was closed while its request was running, and another one
    // opened: the late result must not close it or show its errors there
    expect(
      maintenanceWindowsReducer(undefined, setMaintenanceWindowSubmitted())
        .submission
    ).toEqual(initialWindowSubmission);
    expect(
      maintenanceWindowsReducer(
        undefined,
        setMaintenanceWindowSubmissionErrors({
          errors: [{ title: 'Forbidden', detail: 'Not allowed' }],
        })
      ).submission
    ).toEqual(initialWindowSubmission);
  });
});
