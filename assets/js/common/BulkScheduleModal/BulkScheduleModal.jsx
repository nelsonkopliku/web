// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { noop, uniq } from 'lodash';

import Banner from '@common/Banners';
import Button from '@common/Button';
import Modal from '@common/Modal';
import ScheduleFields, {
  ScheduleRequestErrors,
  initialScheduleForm,
  isScheduleFormValid,
  scheduleFormErrors,
  toScheduleRequest,
} from '@common/OperationModals/ScheduleFields';
import { describeOccurrences } from '@lib/model/recurrence';
import {
  countTargets,
  getOperationLabel,
  getOperationTitle,
} from '@lib/operations';
import { DEFAULT_TIMEZONE } from '@lib/timezones';
import {
  initialScheduleSubmission,
  isSubmittingSchedule,
  SUBMISSION_CONFLICTS,
} from '@state/operationSchedules';

const defaultTargetNames = {};

function Conflicts({ operation, targetType, conflicts, targetNames }) {
  const targetsCount = uniq(conflicts.map(({ target_id: id }) => id)).length;

  return (
    <>
      <Banner type="warning" truncate={false}>
        {getOperationLabel(operation)} is already scheduled for{' '}
        {countTargets(targetsCount, targetType)} of the selection:
      </Banner>
      <ul className="list-disc list-inside space-y-1 my-2 text-sm">
        {conflicts.map((schedule) => (
          <li key={schedule.id}>
            {targetNames[schedule.target_id] ?? schedule.target_id}:{' '}
            {describeOccurrences(schedule, schedule.timezone)} (
            {schedule.timezone})
          </li>
        ))}
      </ul>
      <p className="text-sm">Schedule it once more?</p>
    </>
  );
}

/**
 * Schedules the same operation on several targets. Requesting it now on all
 * of them is a bulk operation, not a schedule. `submission` follows the
 * request: when some targets already have a schedule of the operation, the
 * modal asks whether to continue, and `onSchedule` is called again with
 * `confirmed`. The parent remounts the modal, with a `key`, to start again.
 */
function BulkScheduleModal({
  isOpen = false,
  operation,
  targetType,
  targetsCount = 0,
  timezone = DEFAULT_TIMEZONE,
  targetNames = defaultTargetNames,
  submission = initialScheduleSubmission,
  onSchedule = noop,
  onCancel = noop,
}) {
  const [form, setForm] = useState(() => ({
    ...initialScheduleForm(timezone),
    type: 'one_time',
  }));

  const schedule = toScheduleRequest(form, timezone);
  const valid = isScheduleFormValid(scheduleFormErrors(form, timezone));
  const submittable = targetsCount > 0 && !isSubmittingSchedule(submission);

  const cancelButton = (
    <Button type="primary-white-fit" size="small" onClick={onCancel}>
      Cancel
    </Button>
  );

  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title={`Schedule ${getOperationTitle(operation)}`}
      open={isOpen}
      onClose={onCancel}
    >
      {submission.status === SUBMISSION_CONFLICTS ? (
        <>
          <Conflicts
            operation={operation}
            targetType={targetType}
            conflicts={submission.conflicts}
            targetNames={targetNames}
          />
          <div className="flex justify-start gap-2 mt-4">
            <Button
              type="default-fit"
              size="small"
              disabled={!submittable}
              onClick={() => onSchedule(schedule, { confirmed: true })}
            >
              Continue
            </Button>
            {cancelButton}
          </div>
        </>
      ) : (
        <>
          <p className="text-gray-500 text-sm">
            {getOperationLabel(operation)} on{' '}
            {countTargets(targetsCount, targetType)}. Each one gets its own
            schedule, that can be changed and cancelled on its own.
          </p>
          <ScheduleFields
            form={form}
            timezone={timezone}
            allowNow={false}
            errors={submission.errors}
            onChange={setForm}
          />
          <div className="flex justify-start gap-2 mt-4">
            <Button
              type="default-fit"
              size="small"
              disabled={!valid || !submittable}
              onClick={() => onSchedule(schedule, { confirmed: false })}
            >
              Schedule
            </Button>
            {cancelButton}
          </div>
          <ScheduleRequestErrors errors={submission.errors} />
        </>
      )}
    </Modal>
  );
}

export default BulkScheduleModal;
