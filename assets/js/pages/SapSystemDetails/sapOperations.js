// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { curry, every, get, flow } from 'lodash';

import {
  SAP_INSTANCE_START,
  SAP_INSTANCE_STOP,
  SAP_SYSTEM_START,
  SAP_SYSTEM_STOP,
} from '@lib/operations';

import {
  isOperationRunning,
  getLocalOrTargetParams,
} from '@state/selectors/runningOperations';

const matchesInstanceNumber =
  (instanceNumber) =>
  ({ metadata }) =>
    flow(
      (meta) => getLocalOrTargetParams(meta),
      (params) =>
        get(params, 'instance_number', metadata?.instanceNumber) ===
        instanceNumber
    )(metadata);

export const getSapInstanceOperations = curry(
  (
    runningOperations,
    setOperationModelOpen,
    setCurrentOperationInstance,
    instance
  ) => [
    {
      value: 'Start instance',
      running: isOperationRunning(
        runningOperations,
        instance.host_id,
        SAP_INSTANCE_START,
        matchesInstanceNumber(instance.instance_number)
      ),
      disabled: instance.status === 'green',
      permitted: ['start:application_instance'],
      onClick: () => {
        setCurrentOperationInstance(instance);
        setOperationModelOpen({ open: true, operation: SAP_INSTANCE_START });
      },
    },
    {
      value: 'Stop instance',
      running: isOperationRunning(
        runningOperations,
        instance.host_id,
        SAP_INSTANCE_STOP,
        matchesInstanceNumber(instance.instance_number)
      ),
      disabled: instance.status === 'gray',
      permitted: ['stop:application_instance'],
      onClick: () => {
        setCurrentOperationInstance(instance);
        setOperationModelOpen({ open: true, operation: SAP_INSTANCE_STOP });
      },
    },
  ]
);

// The entries stay available while an operation runs, so that they can be
// scheduled. Only the status of the instances disables them.
export const getSapSystemOperations = (
  sapSystem,
  runningOperations,
  setOperationModelOpen
) => [
  {
    value: 'Start system',
    running: isOperationRunning(
      runningOperations,
      sapSystem.id,
      SAP_SYSTEM_START
    ),
    disabled: every(sapSystem.instances, { status: 'green' }),
    permitted: ['start:sap_system'],
    onClick: () => {
      setOperationModelOpen({ open: true, operation: SAP_SYSTEM_START });
    },
  },
  {
    value: 'Stop system',
    running: isOperationRunning(
      runningOperations,
      sapSystem.id,
      SAP_SYSTEM_STOP
    ),
    disabled: every(sapSystem.instances, { status: 'gray' }),
    permitted: ['stop:sap_system'],
    onClick: () => {
      setOperationModelOpen({ open: true, operation: SAP_SYSTEM_STOP });
    },
  },
];
