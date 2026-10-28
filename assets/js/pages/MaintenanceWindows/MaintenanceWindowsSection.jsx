// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useEffect, useState } from 'react';
import { noop, upperFirst } from 'lodash';

import Button from '@common/Button';
import DisabledGuard from '@common/DisabledGuard';
import MaintenanceWindowModal from '@common/MaintenanceWindowModal';
import Modal from '@common/Modal';
import PremiumPill from '@common/PremiumPill';
import Table from '@common/Table';
import { getGlobalError } from '@lib/api/validationErrors';
import {
  describeForbids,
  describeMaintenanceWindow,
} from '@lib/model/maintenanceWindows';
import { describeOccurrences } from '@lib/model/recurrence';
import { DEFAULT_TIMEZONE, formatDateTime } from '@lib/timezones';
import {
  initialWindowSubmission,
  isSubmittingWindow,
  isWindowSubmitted,
} from '@state/maintenanceWindows';

import OwnerLink from './ownerLink';

export const maintenanceWindowsPermittedFor = ['all:maintenance_windows'];

const describeStatus = (window, timezone) => {
  if (window.active && window.current_occurrence) {
    return `Active until ${formatDateTime(window.current_occurrence.ends_at, timezone)}`;
  }

  return window.next_occurrence
    ? `Next on ${formatDateTime(window.next_occurrence.starts_at, timezone)}`
    : '';
};

// Short and unique enough to tell the windows apart in the actions labels
const windowLabel = (window) =>
  `the maintenance window of ${describeOccurrences(window, window.timezone, {
    duration: window.duration_minutes,
  })}`;

const tableConfig = ({ timezone, userAbilities, onEdit, onAskDelete }) => ({
  usePadding: false,
  columns: [
    {
      title: 'Window',
      key: 'starts_at',
      render: (_startsAt, window) => describeMaintenanceWindow(window),
    },
    {
      title: 'Forbids',
      key: 'forbids',
      render: (forbids) => describeForbids(forbids),
    },
    {
      title: 'Status',
      key: 'active',
      render: (_active, window) => describeStatus(window, timezone),
    },
    {
      title: '',
      key: 'id',
      className: 'text-right',
      render: (_id, window) =>
        window.inherited ? (
          <OwnerLink window={window}>From {window.target_name}</OwnerLink>
        ) : (
          <div className="flex justify-end space-x-2">
            <DisabledGuard
              userAbilities={userAbilities}
              permitted={maintenanceWindowsPermittedFor}
            >
              <Button
                type="primary-white-fit"
                size="small"
                aria-label={`Edit ${windowLabel(window)}`}
                onClick={() => onEdit(window)}
              >
                Edit
              </Button>
            </DisabledGuard>
            <DisabledGuard
              userAbilities={userAbilities}
              permitted={maintenanceWindowsPermittedFor}
            >
              <Button
                type="danger"
                size="small"
                aria-label={`Delete ${windowLabel(window)}`}
                onClick={() => onAskDelete(window)}
              >
                Delete
              </Button>
            </DisabledGuard>
          </div>
        ),
    },
  ],
});

function DeleteWindowModal({ window, submission, onDelete, onClose }) {
  const globalError = getGlobalError(submission.errors);

  return (
    <Modal title="Delete Maintenance Window" open={!!window} onClose={onClose}>
      <p className="text-gray-500">
        {window &&
          `Delete the maintenance window of ${describeMaintenanceWindow(window)}?`}
      </p>
      <div className="flex justify-start gap-2 mt-4">
        <Button
          type="danger"
          size="small"
          disabled={isSubmittingWindow(submission)}
          onClick={() => onDelete(window)}
        >
          Yes, Delete
        </Button>
        <Button type="primary-white-fit" size="small" onClick={onClose}>
          Keep It
        </Button>
      </div>
      {globalError && (
        <p className="text-red-500 text-sm mt-2">{upperFirst(globalError)}</p>
      )}
    </Modal>
  );
}

/**
 * Maintenance windows that cover a target: its own ones, that can be changed
 * and deleted, and the ones inherited from the targets that cover it, read
 * only here. `submission` follows the window being saved.
 */
function MaintenanceWindowsSection({
  windows = [],
  error = false,
  timezone = DEFAULT_TIMEZONE,
  targetLabel,
  userAbilities = [],
  submission = initialWindowSubmission,
  onSchedule = noop,
  onUpdate = noop,
  onDelete = noop,
  onRetry = noop,
  onResetSubmission = noop,
}) {
  // null: closed, {}: a new window, {window}: an existing one
  const [editing, setEditing] = useState(null);
  const [deleting, setDeleting] = useState(null);

  const submitted = isWindowSubmitted(submission);
  useEffect(() => {
    if (submitted) {
      setEditing(null);
      setDeleting(null);
    }
  }, [submitted]);

  const openModal = (state) => {
    onResetSubmission();
    setEditing(state);
  };

  return (
    <div className="mt-8">
      <div className="flex items-center justify-between">
        <h2 id="maintenance-windows" className="text-2xl font-bold">
          Maintenance Windows
        </h2>
        <DisabledGuard
          userAbilities={userAbilities}
          permitted={maintenanceWindowsPermittedFor}
        >
          <Button
            type="primary-white-fit"
            size="small"
            onClick={() => openModal({})}
          >
            Schedule Maintenance
            <PremiumPill className="ml-2" />
          </Button>
        </DisabledGuard>
      </div>

      {error && (
        <div className="flex items-center space-x-4 mt-4">
          <p className="text-gray-500">
            Unable to load the maintenance windows.
          </p>
          <Button type="primary-white-fit" size="small" onClick={onRetry}>
            Retry
          </Button>
        </div>
      )}
      {!error && windows.length === 0 && (
        <p className="text-gray-500 mt-4">
          No maintenance windows are scheduled.
        </p>
      )}
      {!error && windows.length > 0 && (
        <Table
          className="pt-2"
          config={tableConfig({
            timezone,
            userAbilities,
            onEdit: (window) => openModal({ window }),
            onAskDelete: (window) => {
              onResetSubmission();
              setDeleting(window);
            },
          })}
          data={windows}
          ariaLabelledBy="maintenance-windows"
        />
      )}

      {editing && (
        <MaintenanceWindowModal
          key={editing.window?.id ?? 'new'}
          isOpen
          window={editing.window}
          targetLabel={targetLabel}
          timezone={timezone}
          loading={isSubmittingWindow(submission)}
          errors={submission.errors}
          onSave={(request) =>
            editing.window
              ? onUpdate(editing.window, request)
              : onSchedule(request)
          }
          onCancel={() => setEditing(null)}
        />
      )}
      <DeleteWindowModal
        window={deleting}
        submission={submission}
        onDelete={onDelete}
        onClose={() => setDeleting(null)}
      />
    </div>
  );
}

export default MaintenanceWindowsSection;
