// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { APPLICATION_TYPE, DATABASE_TYPE } from '@lib/model/sapSystems';
import {
  DATABASE_START,
  SAP_SYSTEM_START,
  SAP_SYSTEM_STOP,
} from '@lib/operations';
import {
  operationScheduleFactory,
  sapSystemFactory,
} from '@lib/test-utils/factories';
import { action } from 'storybook/actions';

import SapStartStopOperationModal from './SapStartStopOperationModal';

export default {
  title: 'Components/SapStartStopOperationModal',
  component: SapStartStopOperationModal,
  argTypes: {
    operation: {
      description: 'Operation to request',
      control: { type: 'object' },
    },
    type: {
      description: 'System type',
      control: { type: 'radio' },
      options: [APPLICATION_TYPE, DATABASE_TYPE],
    },
    sid: {
      description: 'SAP system or database sid',
      control: { type: 'text' },
    },
    site: {
      description: 'System replication site. Only applicable for database type',
      control: { type: 'text' },
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
      description: 'Existing schedule to change, with its params',
      control: { type: 'object' },
    },
    onRequest: {
      description:
        'Request start/stop operation, with the params and the schedule, null to request now',
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

const { sid } = sapSystemFactory.build();

export const Default = {
  args: {
    operation: SAP_SYSTEM_START,
    type: APPLICATION_TYPE,
    sid,
    isOpen: true,
    onRequest: action('onRequest'),
    onCancel: action('onCancel'),
  },
};

export const SapSystem = {
  args: {
    ...Default.args,
    operation: SAP_SYSTEM_START,
    type: APPLICATION_TYPE,
    sid,
    isOpen: true,
    onRequest: action('onRequest'),
    onCancel: action('onCancel'),
  },
};

export const Database = {
  args: {
    ...Default.args,
    operation: DATABASE_START,
    type: DATABASE_TYPE,
    sid,
    isOpen: true,
    onRequest: action('onRequest'),
    onCancel: action('onCancel'),
  },
};

export const Schedulable = {
  args: {
    ...Default.args,
    schedulable: true,
    timezone: 'Europe/Berlin',
  },
};

export const ChangeSchedule = {
  args: {
    ...Schedulable.args,
    operation: SAP_SYSTEM_STOP,
    initialSchedule: operationScheduleFactory.build({
      target_type: 'sap_system',
      operation: SAP_SYSTEM_STOP,
      params: { instance_type: 'abap', timeout: 600 },
    }),
    onCancelSchedule: action('onCancelSchedule'),
  },
};
