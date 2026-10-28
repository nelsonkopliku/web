// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';

import SettingsLoader, {
  calculateStatus as calculateSettingsLoaderStatus,
} from '@common/SettingsLoader';

import { useChecksSchedule } from './hooks';
import TargetChecksExecution from './TargetChecksExecution';
import TargetChecksExecutionModal from './TargetChecksExecutionModal';

/**
 * Check execution settings of a host or a cluster, in its check settings view
 */
function TargetChecksExecutionSection({ targetType, targetID, userAbilities }) {
  const {
    schedule,
    fetchLoading,
    fetchError,
    submitLoading,
    submitErrors,
    fetchSchedule,
    saveSchedule,
    clearSubmitErrors,
  } = useChecksSchedule(targetType, targetID);

  const [modalOpen, setModalOpen] = useState(false);

  const save = async (changes) => {
    if (await saveSchedule(changes)) setModalOpen(false);
  };

  return (
    <SettingsLoader
      sectionName="Check Execution"
      status={calculateSettingsLoaderStatus(fetchLoading, fetchError)}
      onRetry={fetchSchedule}
    >
      {schedule && (
        <>
          <TargetChecksExecution
            targetType={targetType}
            schedule={schedule}
            userAbilities={userAbilities}
            onEditClick={() => {
              clearSubmitErrors();
              setModalOpen(true);
            }}
          />
          <TargetChecksExecutionModal
            key={`checks-execution-${modalOpen}`}
            open={modalOpen}
            loading={submitLoading}
            errors={submitErrors}
            schedule={schedule}
            onSave={save}
            onCancel={() => setModalOpen(false)}
          />
        </>
      )}
    </SettingsLoader>
  );
}

export default TargetChecksExecutionSection;
