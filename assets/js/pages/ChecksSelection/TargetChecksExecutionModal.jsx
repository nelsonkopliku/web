// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { lowerFirst, noop, upperFirst } from 'lodash';

import Button from '@common/Button';
import ChecksFrequencyInput from '@common/ChecksFrequencyInput';
import Label from '@common/Label';
import Modal from '@common/Modal';

import { getError, getGlobalError } from '@lib/api/validationErrors';
import { describeFrequency } from '@lib/model/checksSchedule';

const defaultErrors = [];

function ErrorMessage({ text }) {
  return text ? <p className="text-red-500 mt-1">{upperFirst(text)}</p> : null;
}

/**
 * Modal to edit the checks execution frequency of a host or a cluster
 */
function TargetChecksExecutionModal({
  open = false,
  loading = false,
  schedule,
  errors = defaultErrors,
  onSave = noop,
  onCancel = noop,
}) {
  const [interval, setInterval] = useState(schedule.interval);

  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title="Check Execution Settings"
      open={open}
      onClose={onCancel}
    >
      <div className="text-gray-500">
        Configure how often the checks are executed, or follow the system
        setting.
      </div>
      <div className="grid grid-cols-6 my-5 gap-6 items-center">
        <Label className="col-span-2">Frequency</Label>
        <div className="col-span-4">
          <ChecksFrequencyInput
            value={interval}
            allowSystemSetting
            onChange={setInterval}
          />
          <p className="text-gray-500 text-sm mt-1">
            The system setting is{' '}
            {lowerFirst(describeFrequency(schedule.global_interval))}.
          </p>
          <ErrorMessage text={getError('interval', errors)} />
        </div>
      </div>
      <div className="flex flex-row w-80 space-x-2">
        <Button disabled={loading} onClick={() => onSave({ interval })}>
          Save Settings
        </Button>
        <Button type="primary-white" onClick={onCancel}>
          Cancel
        </Button>
      </div>
      <ErrorMessage text={getGlobalError(errors)} />
    </Modal>
  );
}

export default TargetChecksExecutionModal;
