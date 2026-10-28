// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useEffect, useState } from 'react';
import { isEmpty, noop, upperFirst } from 'lodash';
import { parseISO } from 'date-fns';

import Button from '@common/Button';
import DisabledGuard from '@common/DisabledGuard';
import Modal from '@common/Modal';
import Table from '@common/Table';
import { getGlobalError } from '@lib/api/validationErrors';
import { describeOccurrences } from '@lib/model/recurrence';
import {
  describeOperationParams,
  getOperationLabel,
  getOperationPermittedFor,
} from '@lib/operations';
import { DEFAULT_TIMEZONE, formatDateTime } from '@lib/timezones';
import {
  initialScheduleSubmission,
  isScheduleSubmitted,
  isSubmittingSchedule,
} from '@state/operationSchedules';

const formatNextRun = ({ next_run_at: nextRunAt }, timezone) =>
  formatDateTime(parseISO(nextRunAt), timezone);

// Schedules are described in their own timezone, told when it is not the
// one of the user
const describeSchedule = (schedule, timezone) => {
  const description = describeOccurrences(schedule, schedule.timezone);

  return schedule.timezone === timezone
    ? description
    : `${description} (${schedule.timezone})`;
};

const scheduleLabel = (schedule, timezone) =>
  `the schedule of ${getOperationLabel(schedule.operation)}, next run ${formatNextRun(schedule, timezone)}`;

const tableConfig = ({ timezone, userAbilities, onEdit, onAskCancel }) => ({
  usePadding: false,
  columns: [
    {
      title: 'Operation',
      key: 'operation',
      render: (operation) => getOperationLabel(operation),
    },
    {
      title: 'Options',
      key: 'params',
      render: (params) => describeOperationParams(params),
    },
    {
      title: 'Next Run',
      key: 'next_run_at',
      render: (_nextRunAt, schedule) => formatNextRun(schedule, timezone),
    },
    {
      title: 'Schedule',
      key: 'recurrence',
      render: (_recurrence, schedule) => describeSchedule(schedule, timezone),
    },
    {
      title: '',
      key: 'id',
      className: 'text-right',
      render: (_id, schedule) => (
        <div className="flex justify-end space-x-2">
          <DisabledGuard
            userAbilities={userAbilities}
            permitted={getOperationPermittedFor(schedule.operation)}
          >
            <Button
              type="primary-white-fit"
              size="small"
              aria-label={`Edit ${scheduleLabel(schedule, timezone)}`}
              onClick={() => onEdit(schedule)}
            >
              Edit
            </Button>
          </DisabledGuard>
          <DisabledGuard
            userAbilities={userAbilities}
            permitted={getOperationPermittedFor(schedule.operation)}
          >
            <Button
              type="danger"
              size="small"
              aria-label={`Cancel ${scheduleLabel(schedule, timezone)}`}
              onClick={() => onAskCancel(schedule)}
            >
              Cancel
            </Button>
          </DisabledGuard>
        </div>
      ),
    },
  ],
});

function CancelScheduleModal({ schedule, submission, onCancel, onClose }) {
  const globalError = getGlobalError(submission.errors);

  return (
    <Modal title="Cancel Schedule" open={!!schedule} onClose={onClose}>
      <p className="text-gray-500">
        {schedule &&
          `Cancel this schedule of ${getOperationLabel(schedule.operation)}? The operation will not be requested anymore.`}
      </p>
      <div className="flex justify-start gap-2 mt-4">
        <Button
          type="danger"
          size="small"
          disabled={isSubmittingSchedule(submission)}
          onClick={() => onCancel(schedule)}
        >
          Yes, Cancel Schedule
        </Button>
        <Button type="primary-white-fit" size="small" onClick={onClose}>
          Keep Schedule
        </Button>
      </div>
      {globalError && (
        <p className="text-red-500 text-sm mt-2">{upperFirst(globalError)}</p>
      )}
    </Modal>
  );
}

/**
 * Scheduled operations of a target, the next one first. Changing or
 * cancelling one needs the abilities of its operation. `submission` follows
 * the cancellation of a schedule, forgotten with `onResetSubmission` when a
 * cancellation starts.
 */
function OperationSchedules({
  schedules = [],
  error = false,
  timezone = DEFAULT_TIMEZONE,
  userAbilities = [],
  submission = initialScheduleSubmission,
  onEdit = noop,
  onCancel = noop,
  onRetry = noop,
  onResetSubmission = noop,
}) {
  const [cancelling, setCancelling] = useState(null);

  const cancelled = isScheduleSubmitted(submission);
  useEffect(() => {
    if (cancelled) setCancelling(null);
  }, [cancelled]);

  if (!error && isEmpty(schedules)) return null;

  return (
    <div className="mt-8">
      <h2 id="scheduled-operations" className="text-2xl font-bold">
        Scheduled Operations
      </h2>
      {error ? (
        <div className="flex items-center space-x-4 mt-4">
          <p className="text-gray-500">
            Unable to load the scheduled operations.
          </p>
          <Button type="primary-white-fit" size="small" onClick={onRetry}>
            Retry
          </Button>
        </div>
      ) : (
        <Table
          className="pt-2"
          config={tableConfig({
            timezone,
            userAbilities,
            onEdit,
            onAskCancel: (schedule) => {
              onResetSubmission();
              setCancelling(schedule);
            },
          })}
          data={schedules}
          ariaLabelledBy="scheduled-operations"
        />
      )}
      <CancelScheduleModal
        schedule={cancelling}
        submission={submission}
        onCancel={onCancel}
        onClose={() => setCancelling(null)}
      />
    </div>
  );
}

export default OperationSchedules;
