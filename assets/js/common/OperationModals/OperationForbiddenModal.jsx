// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { noop } from 'lodash';

import Modal from '@common/Modal';
import Button from '@common/Button';
import Banner from '@common/Banners';

import PolicyMessage from './PolicyMessage';

function OperationForbiddenModal({
  operation,
  errors,
  isOpen = false,
  onCancel = noop,
}) {
  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title="Operation Forbidden"
      open={isOpen}
      onClose={onCancel}
    >
      <Banner type="error">
        Unable to run {operation} operation. Some pre-requisites are not met.
      </Banner>
      <p className="text-sm mb-1">
        Some of the following pre-requisites are not met:
      </p>
      <ul className="list-disc list-inside space-y-1 mb-1">
        {errors.map(({ detail, metadata }) => (
          <li key={detail} className="text-sm">
            <PolicyMessage
              message={detail}
              metadata={metadata}
              onLinkClick={onCancel}
            />
          </li>
        ))}
      </ul>
      <div className="flex justify-start gap-2 mt-4">
        <Button
          type="primary-white-fit"
          className="inline-block mx-0.5 border-green-500 border"
          size="small"
          onClick={onCancel}
        >
          Close
        </Button>
      </div>
    </Modal>
  );
}

export default OperationForbiddenModal;
