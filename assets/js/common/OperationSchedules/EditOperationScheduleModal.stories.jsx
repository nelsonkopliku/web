// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import { APPLICATION_TYPE } from '@lib/model/sapSystems';
import { operationScheduleFactory } from '@lib/test-utils/factories';

import EditOperationScheduleModal from './EditOperationScheduleModal';

export default {
  title: 'Components/EditOperationScheduleModal',
  component: EditOperationScheduleModal,
  argTypes: {
    schedule: {
      description: 'The schedule to change or cancel',
      control: { type: 'object' },
    },
    isOpen: {
      description: 'Whether the modal is open',
      control: { type: 'boolean' },
    },
    sid: {
      description: 'SID of the SAP system or database of the schedule',
      control: { type: 'text' },
    },
    type: {
      description: 'Type of the SAP system or database of the schedule',
      control: { type: 'text' },
    },
    descriptionResolverArgs: {
      description: 'Arguments of the description of the operation',
      control: { type: 'object' },
    },
    submission: {
      description: 'Submission of the change: status and errors',
      control: { type: 'object' },
    },
    onSave: {
      description: 'Callback with the changed params and timing',
      action: 'onSave',
    },
    onCancelSchedule: {
      description: 'Cancels the schedule',
      action: 'onCancelSchedule',
    },
    onCancel: {
      description: 'Closes the modal',
      action: 'onCancel',
    },
  },
};

export const HostReboot = {
  args: {
    schedule: operationScheduleFactory.build({ operation: 'reboot' }),
    isOpen: true,
    descriptionResolverArgs: { hostName: 'vmhana01' },
    onSave: action('onSave'),
    onCancelSchedule: action('onCancelSchedule'),
    onCancel: action('onCancel'),
  },
};

export const SapSystemStop = {
  args: {
    ...HostReboot.args,
    schedule: operationScheduleFactory.build({
      target_type: 'sap_system',
      operation: 'sap_system_stop',
      params: { instance_type: 'abap', timeout: 600 },
    }),
    sid: 'HA1',
    type: APPLICATION_TYPE,
    descriptionResolverArgs: {},
  },
};
