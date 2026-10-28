// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useEffect } from 'react';
import { useParams } from 'react-router';
import { useSelector, useDispatch } from 'react-redux';

import { getFromConfig } from '@lib/config';
import { APPLICATION_TYPE } from '@lib/model/sapSystems';
import { getEnrichedSapSystemDetails } from '@state/selectors/sapSystem';
import { getRunningOperationsList } from '@state/selectors/runningOperations';
import {
  getOperationScheduleSubmission,
  getOperationSchedules,
} from '@state/selectors/operationSchedules';
import { getUserProfile } from '@state/selectors/user';
import { deregisterApplicationInstance } from '@state/sapSystems';
import {
  operationRequested,
  updateRunningOperations,
  removeRunningOperation,
} from '@state/runningOperations';
import {
  cancelOperationSchedule,
  fetchOperationSchedules,
  forgetOperationSchedules,
  resetOperationScheduleSubmission,
  scheduleOperation,
  updateOperationSchedule,
} from '@state/operationSchedules';

import BackButton from '@common/BackButton';
import { GenericSystemDetails } from '@pages/SapSystemDetails';

import {
  getSapSystemOperations,
  getSapInstanceOperations,
} from './sapOperations';

const operationsEnabled = getFromConfig('operationsEnabled');

function SapSystemDetails() {
  const { id } = useParams();
  const sapSystem = useSelector((state) =>
    getEnrichedSapSystemDetails(state, id)
  );
  const { abilities, timezone } = useSelector(getUserProfile);
  const dispatch = useDispatch();

  const runningOperations = useSelector(getRunningOperationsList);

  const { schedules: operationSchedules, error: operationSchedulesError } =
    useSelector(getOperationSchedules(id));
  const scheduleSubmission = useSelector(getOperationScheduleSubmission);

  useEffect(() => {
    operationsEnabled && dispatch(updateRunningOperations());
  }, [dispatch]);

  useEffect(() => {
    operationsEnabled && dispatch(fetchOperationSchedules({ targetID: id }));

    return () => {
      dispatch(resetOperationScheduleSubmission());
      dispatch(forgetOperationSchedules({ targetID: id }));
    };
  }, [dispatch, id]);

  if (!sapSystem) {
    return <div>Not Found</div>;
  }

  return (
    <>
      <BackButton url="/sap_systems">Back to SAP Systems</BackButton>
      <GenericSystemDetails
        title="SAP System Details"
        type={APPLICATION_TYPE}
        system={sapSystem}
        userAbilities={abilities}
        userTimezone={timezone}
        cleanUpPermittedFor={['cleanup:application_instance']}
        operationsEnabled={operationsEnabled}
        runningOperations={runningOperations}
        getInstanceOperations={getSapInstanceOperations}
        getSystemOperations={getSapSystemOperations}
        onInstanceCleanUp={(instance) => {
          dispatch(deregisterApplicationInstance(instance));
        }}
        onRequestOperation={(payload) => dispatch(operationRequested(payload))}
        operationSchedules={operationSchedules}
        scheduleSubmission={scheduleSubmission}
        onScheduleOperation={(request) => dispatch(scheduleOperation(request))}
        operationSchedulesError={operationSchedulesError}
        onUpdateSchedule={(schedule, changes) =>
          dispatch(updateOperationSchedule({ schedule, changes }))
        }
        onCancelSchedule={(schedule) =>
          dispatch(cancelOperationSchedule({ schedule }))
        }
        onRetryOperationSchedules={() =>
          dispatch(fetchOperationSchedules({ targetID: id }))
        }
        onResetScheduleSubmission={() =>
          dispatch(resetOperationScheduleSubmission())
        }
        onCleanForbiddenOperation={(groupID) =>
          dispatch(removeRunningOperation({ groupID }))
        }
      />
    </>
  );
}

export default SapSystemDetails;
