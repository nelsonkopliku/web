// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { noop } from 'lodash';

import {
  SapStartStopOperationModal,
  SimpleAcceptanceOperationModal,
} from '@common/OperationModals';
import {
  DATABASE_START,
  DATABASE_STOP,
  SAP_SYSTEM_START,
  SAP_SYSTEM_STOP,
} from '@lib/operations';
import {
  initialScheduleSubmission,
  isSubmittingSchedule,
} from '@state/operationSchedules';

const START_STOP_OPERATIONS = [
  SAP_SYSTEM_START,
  SAP_SYSTEM_STOP,
  DATABASE_START,
  DATABASE_STOP,
];

/**
 * Modal of the operation of an existing schedule, to change when it runs and
 * its options, or to cancel it. Operations without options in their modal
 * keep the params of the schedule.
 */
function EditOperationScheduleModal({
  schedule,
  isOpen = false,
  sid,
  type,
  descriptionResolverArgs = {},
  submission = initialScheduleSubmission,
  onSave = noop,
  onCancelSchedule = noop,
  onCancel = noop,
}) {
  if (!schedule) return null;

  const { operation, params = {} } = schedule;

  const commonProps = {
    operation,
    isOpen,
    schedulable: true,
    initialSchedule: schedule,
    loading: isSubmittingSchedule(submission),
    errors: submission.errors,
    onCancel,
    onCancelSchedule,
  };

  if (START_STOP_OPERATIONS.includes(operation)) {
    return (
      <SapStartStopOperationModal
        {...commonProps}
        sid={sid}
        type={type}
        site={params.site || null}
        onRequest={(newParams, newSchedule) =>
          onSave({ params: newParams, ...newSchedule })
        }
      />
    );
  }

  return (
    <SimpleAcceptanceOperationModal
      {...commonProps}
      descriptionResolverArgs={{
        ...params,
        instanceNumber: params.instance_number,
        sid,
        ...descriptionResolverArgs,
      }}
      onRequest={(_params, newSchedule) => onSave({ params, ...newSchedule })}
    />
  );
}

export default EditOperationScheduleModal;
