// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { noop } from 'lodash';

import Modal from '@common/Modal';
import Button from '@common/Button';
import Banner from '@common/Banners';

/**
 * Refuses a request now while another operation runs for the target. The
 * operations menus stay open in that case, so that the operation can be
 * scheduled.
 */
function OperationAlreadyRunningModal({
  isOpen = false,
  operation,
  onClose = noop,
}) {
  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title="Operation Already Running"
      open={isOpen}
      onClose={onClose}
    >
      <Banner type="error" truncate={false}>
        Unable to run {operation} operation now. Another operation is already
        running for this target.
      </Banner>
      <p className="text-sm mb-1">
        Request it again once the running operation completes, or schedule it.
      </p>
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

export default OperationAlreadyRunningModal;
