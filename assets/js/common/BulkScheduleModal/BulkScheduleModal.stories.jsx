// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import { HOST_REBOOT } from '@lib/operations';
import {
  hostFactory,
  operationScheduleFactory,
} from '@lib/test-utils/factories';

import BulkScheduleModal from './BulkScheduleModal';

const [host1, host2] = hostFactory.buildList(2);

export default {
  title: 'Components/BulkScheduleModal',
  component: BulkScheduleModal,
  argTypes: {
    isOpen: {
      description: 'Whether the modal is open',
      control: { type: 'boolean' },
    },
    operation: {
      description: 'Operation to schedule on every target',
      control: { type: 'text' },
    },
    targetType: {
      description: 'Type of the targets',
      control: { type: 'text' },
    },
    targetsCount: {
      description: 'Number of selected targets',
      control: { type: 'number' },
    },
    timezone: {
      description: 'Timezone of the user',
      control: { type: 'text' },
    },
    targetNames: {
      description: 'Names of the targets by id, to name the conflicts',
      control: { type: 'object' },
    },
    submission: {
      description:
        'Submission of the bulk schedule: status, errors and conflicts',
      control: { type: 'object' },
    },
    onSchedule: {
      description: 'Callback with the schedule and whether it is confirmed',
      action: 'onSchedule',
    },
    onCancel: {
      description: 'Closes the modal',
      action: 'onCancel',
    },
  },
};

export const Default = {
  args: {
    isOpen: true,
    operation: HOST_REBOOT,
    targetType: 'host',
    targetsCount: 2,
    timezone: 'Europe/Berlin',
    targetNames: { [host1.id]: host1.hostname, [host2.id]: host2.hostname },
    onSchedule: action('onSchedule'),
    onCancel: action('onCancel'),
  },
};

export const AlreadyScheduled = {
  args: {
    ...Default.args,
    submission: {
      status: 'conflicts',
      operation: null,
      errors: [],
      warnings: [],
      conflicts: [
        operationScheduleFactory.build({
          target_id: host2.id,
          operation: HOST_REBOOT,
        }),
      ],
    },
  },
};

export const Refused = {
  args: {
    ...Default.args,
    submission: {
      status: 'failed',
      operation: null,
      errors: [
        { title: 'Forbidden', detail: 'You can not perform this action.' },
      ],
      warnings: [],
      conflicts: [],
    },
  },
};
