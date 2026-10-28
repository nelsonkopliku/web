// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { noop } from 'lodash';

import Modal from '@common/Modal';
import Button from '@common/Button';
import Banner from '@common/Banners';

import PolicyMessage from './PolicyMessage';

const defaultWarnings = [];

/**
 * Tells the policies that a just scheduled operation would not pass now.
 * The schedule is saved anyway: they are checked again when it runs. The
 * warnings of a bulk schedule tell their target with `targetName`.
 */
function ScheduleWarningsModal({
  isOpen = false,
  operation,
  warnings = defaultWarnings,
  onClose = noop,
}) {
  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title="Operation Scheduled"
      open={isOpen}
      onClose={onClose}
    >
      <Banner type="warning" truncate={false}>
        {operation} is scheduled, but it could not run now. These pre-requisites
        are checked again when it runs:
      </Banner>
      <ul className="list-disc list-inside space-y-1 mb-1">
        {warnings.map(({ message, metadata, targetName }) => (
          <li
            key={`${targetName}-${message}-${JSON.stringify(metadata)}`}
            className="text-sm"
          >
            {targetName && `${targetName}: `}
            <PolicyMessage
              message={message}
              metadata={metadata}
              onLinkClick={onClose}
            />
          </li>
        ))}
      </ul>
      <div className="flex justify-start gap-2 mt-4">
        <Button
          type="primary-white-fit"
          className="inline-block mx-0.5 border-green-500 border"
          size="small"
          onClick={onClose}
        >
          Close
        </Button>
      </div>
    </Modal>
  );
}

export default ScheduleWarningsModal;
