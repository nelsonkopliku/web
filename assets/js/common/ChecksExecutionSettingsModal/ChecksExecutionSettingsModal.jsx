// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { noop, upperFirst } from 'lodash';

import Button from '@common/Button';
import ChecksFrequencyInput from '@common/ChecksFrequencyInput';
import Label from '@common/Label';
import Modal from '@common/Modal';

import { getError, getGlobalError } from '@lib/api/validationErrors';

const defaultErrors = [];

function ErrorMessage({ text }) {
  return text ? <p className="text-red-500 mt-1">{upperFirst(text)}</p> : null;
}

/**
 * Modal to edit the global checks execution frequency
 */
function ChecksExecutionSettingsModal({
  open = false,
  loading = false,
  initialInterval,
  errors = defaultErrors,
  onSave = noop,
  onCancel = noop,
}) {
  const [interval, setInterval] = useState(initialInterval);

  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title="Check Execution Settings"
      open={open}
      onClose={onCancel}
    >
      <div className="text-gray-500">
        Configure how often the checks of hosts and clusters are executed. Hosts
        and clusters with their own frequency keep it.
      </div>
      <div className="grid grid-cols-6 my-5 gap-6 items-center">
        <Label className="col-span-2">Frequency</Label>
        <div className="col-span-4">
          <ChecksFrequencyInput value={interval} onChange={setInterval} />
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

export default ChecksExecutionSettingsModal;
