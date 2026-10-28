// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { lowerFirst, noop } from 'lodash';

import Button from '@common/Button';
import DisabledGuard from '@common/DisabledGuard';
import PremiumPill from '@common/PremiumPill';
import { describeFrequency } from '@lib/model/checksSchedule';

export const checkFrequencyPermittedFor = ['all:check_frequency'];

const describeOrigin = ({ interval, global_interval: globalInterval }) =>
  interval
    ? `(overrides the system setting: ${lowerFirst(describeFrequency(globalInterval))})`
    : '(system setting)';

/**
 * Checks execution frequency of a host or a cluster: its own one, or the
 * system setting. Editing is done in TargetChecksExecutionModal.
 */
function TargetChecksExecution({
  targetType,
  schedule,
  userAbilities,
  onEditClick = noop,
}) {
  return (
    <div className="mt-4 mb-4 p-4 sm:p-6 lg:p-8 bg-white dark:bg-gray-800 rounded-lg shadow">
      <div>
        <h2 className="text-2xl font-bold inline-block">Check Execution</h2>
        <PremiumPill className="ml-3 align-middle" />
        <span className="float-right">
          <DisabledGuard
            userAbilities={userAbilities}
            permitted={checkFrequencyPermittedFor}
          >
            <Button type="primary-white-fit" size="small" onClick={onEditClick}>
              Edit Settings
            </Button>
          </DisabledGuard>
        </span>
      </div>
      <p className="mt-3 mb-5 text-gray-500">
        Configure how often the checks of this {targetType} are executed.
      </p>

      <div className="grid grid-cols-6 items-center">
        <div className="font-bold">Check Execution Frequency</div>
        <div
          aria-label="checks-execution-frequency"
          className="col-span-5 text-gray-500"
        >
          {describeFrequency(schedule.effective_interval)}{' '}
          {describeOrigin(schedule)}
        </div>
      </div>
    </div>
  );
}

export default TargetChecksExecution;
