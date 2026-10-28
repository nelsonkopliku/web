// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { operationScheduleFactory } from '@lib/test-utils/factories';

import {
  getOperationScheduleSubmission,
  getOperationSchedules,
} from './operationSchedules';

describe('operation schedules selectors', () => {
  it('should get the schedules of a target', () => {
    const schedules = operationScheduleFactory.buildList(2);
    const state = {
      operationSchedules: {
        byTarget: { target: { loading: false, error: false, schedules } },
      },
    };

    expect(getOperationSchedules('target')(state)).toEqual({
      loading: false,
      error: false,
      schedules,
    });
  });

  it('should get no schedules for a target never loaded', () => {
    expect(
      getOperationSchedules('unknown')({ operationSchedules: { byTarget: {} } })
    ).toEqual({ loading: false, error: false, schedules: [] });
  });

  it('should get the submission of a schedule', () => {
    const submission = { status: 'failed', errors: [], warnings: [] };

    expect(
      getOperationScheduleSubmission({
        operationSchedules: { byTarget: {}, submission },
      })
    ).toEqual(submission);
  });
});
