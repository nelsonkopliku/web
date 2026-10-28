// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import {
  CLUSTER_HOST_START,
  CLUSTER_HOST_STOP,
  CLUSTER_MAINTENANCE_CHANGE,
  CLUSTER_RESOURCE_REFRESH,
  PACEMAKER_DISABLE,
  PACEMAKER_ENABLE,
  SAP_INSTANCE_START,
  SAP_INSTANCE_STOP,
} from '@lib/operations';
import {
  hostFactory,
  operationScheduleFactory,
  sapSystemApplicationInstanceFactory,
} from '@lib/test-utils/factories';
import { action } from 'storybook/actions';

import SimpleAcceptanceOperationModal from './SimpleAcceptanceOperationModal';

export default {
  title: 'Components/SimpleAcceptanceOperationModal',
  component: SimpleAcceptanceOperationModal,
  argTypes: {
    operation: {
      description: 'Operation to apply that requires confirmation',
      control: { type: 'radio' },
      options: [
        SAP_INSTANCE_START,
        SAP_INSTANCE_STOP,
        PACEMAKER_ENABLE,
        PACEMAKER_DISABLE,
        CLUSTER_HOST_START,
        CLUSTER_HOST_STOP,
        CLUSTER_MAINTENANCE_CHANGE,
        CLUSTER_RESOURCE_REFRESH,
      ],
    },
    descriptionResolverArgs: {
      description:
        'Arguments for the description resolver function to generate the operation description',
      control: { type: 'object' },
    },
    isOpen: {
      description: 'Modal is open',
      control: { type: 'boolean' },
    },
    schedulable: {
      description: 'Whether the operation can be scheduled',
      control: { type: 'boolean' },
    },
    timezone: {
      description: 'Timezone of the user, for new schedules',
      control: { type: 'text' },
    },
    initialSchedule: {
      description: 'Existing schedule to change',
      control: { type: 'object' },
    },
    existingSchedules: {
      description:
        'Schedules of the same operation for the target, to warn before scheduling it again',
      control: { type: 'object' },
    },
    onRequest: {
      description:
        'Request the operation, with its params and the schedule, null to request now',
      action: 'onRequest',
    },
    onCancelSchedule: {
      description: 'Cancels the existing schedule',
      action: 'onCancelSchedule',
    },
    onCancel: {
      description: 'Closes the modal',
      action: 'onCancel',
    },
  },
};

const { instance_number: instanceNumber, sid } =
  sapSystemApplicationInstanceFactory.build();

const { hostname: hostName } = hostFactory.build();

export const Default = {
  args: {
    operation: SAP_INSTANCE_START,
    descriptionResolverArgs: { instanceNumber, sid },
    isOpen: true,
    onRequest: action('onRequest'),
    onCancel: action('onCancel'),
  },
};

export const StartInstance = {
  args: {
    ...Default.args,
    operation: SAP_INSTANCE_START,
    descriptionResolverArgs: { instanceNumber, sid },
  },
};

export const StopInstance = {
  args: {
    ...Default.args,
    operation: SAP_INSTANCE_STOP,
    descriptionResolverArgs: { instanceNumber, sid },
  },
};

export const EnablePacemaker = {
  args: {
    ...Default.args,
    operation: PACEMAKER_ENABLE,
    descriptionResolverArgs: { hostName },
  },
};

export const DisablePacemaker = {
  args: {
    ...Default.args,
    operation: PACEMAKER_DISABLE,
    descriptionResolverArgs: { hostName },
  },
};

export const ClusterHostStart = {
  args: {
    ...Default.args,
    operation: CLUSTER_HOST_START,
    descriptionResolverArgs: { hostName },
  },
};

export const ClusterHostStop = {
  args: {
    ...Default.args,
    operation: CLUSTER_HOST_STOP,
    descriptionResolverArgs: { hostName },
  },
};

export const ClusterMaintenanceChange = {
  args: {
    ...Default.args,
    operation: CLUSTER_MAINTENANCE_CHANGE,
    descriptionResolverArgs: { maintenance: true },
  },
};

export const NodeMaintenanceChange = {
  args: {
    ...Default.args,
    operation: CLUSTER_MAINTENANCE_CHANGE,
    descriptionResolverArgs: { maintenance: true, node_id: hostName },
  },
};

export const ResourceMaintenanceChange = {
  args: {
    ...Default.args,
    operation: CLUSTER_MAINTENANCE_CHANGE,
    descriptionResolverArgs: {
      maintenance: true,
      resource_id: 'rsc_ip_PRD_HDB00',
    },
  },
};

export const ClusterResourcesRefresh = {
  args: {
    ...Default.args,
    operation: CLUSTER_RESOURCE_REFRESH,
    descriptionResolverArgs: {},
  },
};

export const ResourceRefresh = {
  args: {
    ...Default.args,
    operation: CLUSTER_RESOURCE_REFRESH,
    descriptionResolverArgs: {
      resource_id: 'rsc_ip_PRD_HDB00',
    },
  },
};

export const RebootHost = {
  args: {
    ...Default.args,
    operation: 'reboot',
    descriptionResolverArgs: { hostName },
  },
};

export const ScheduleInstanceStart = {
  args: {
    ...Default.args,
    schedulable: true,
    timezone: 'Europe/Berlin',
  },
};

export const InstanceStartAlreadyScheduled = {
  args: {
    ...ScheduleInstanceStart.args,
    existingSchedules: [
      operationScheduleFactory.build({
        target_type: 'sap_system',
        operation: SAP_INSTANCE_START,
        params: { instance_number: instanceNumber },
      }),
    ],
  },
};

export const ChangeInstanceStartSchedule = {
  args: {
    ...ScheduleInstanceStart.args,
    initialSchedule: operationScheduleFactory.build({
      target_type: 'sap_system',
      operation: SAP_INSTANCE_START,
      params: { instance_number: instanceNumber },
    }),
    onCancelSchedule: action('onCancelSchedule'),
  },
};
