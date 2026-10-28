// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import {
  abilityFactory,
  operationScheduleFactory,
} from '@lib/test-utils/factories';

import OperationSchedules from './OperationSchedules';

export default {
  title: 'Components/OperationSchedules',
  component: OperationSchedules,
  argTypes: {
    schedules: {
      description: 'Scheduled operations of the target, the next one first',
      control: { type: 'object' },
    },
    error: {
      description: 'Whether the scheduled operations could not be loaded',
      control: { type: 'boolean' },
    },
    timezone: {
      description: 'Timezone of the user',
      control: { type: 'text' },
    },
    userAbilities: {
      description:
        'Abilities of the user, changing a schedule needs the abilities of its operation',
      control: { type: 'object' },
    },
    submission: {
      description: 'Submission of a cancellation: status and errors',
      control: { type: 'object' },
    },
    onEdit: { description: 'Opens a schedule to change it', action: 'onEdit' },
    onCancel: {
      description: 'Cancels a schedule, after a confirmation',
      action: 'onCancel',
    },
    onRetry: {
      description: 'Loads the scheduled operations again',
      action: 'onRetry',
    },
    onResetSubmission: {
      description: 'Forgets the last submission when a cancellation starts',
      action: 'onResetSubmission',
    },
  },
};

export const Default = {
  args: {
    schedules: [
      operationScheduleFactory.build({
        operation: 'reboot',
        timezone: 'Etc/UTC',
      }),
      operationScheduleFactory.build({
        target_type: 'sap_system',
        operation: 'sap_system_stop',
        params: { instance_type: 'abap', timeout: 300 },
        timezone: 'Europe/Berlin',
        recurrence: {
          frequency: 'weekly',
          interval: 2,
          weekdays: [6, 7],
          ends_on: null,
          max_occurrences: 5,
        },
      }),
    ],
    error: false,
    timezone: 'Etc/UTC',
    userAbilities: [abilityFactory.build({ name: 'all', resource: 'all' })],
    onEdit: action('onEdit'),
    onCancel: action('onCancel'),
    onRetry: action('onRetry'),
    onResetSubmission: action('onResetSubmission'),
  },
};

export const ChangeUnauthorized = {
  args: {
    ...Default.args,
    userAbilities: [],
  },
};

export const LoadingFailed = {
  args: {
    ...Default.args,
    schedules: [],
    error: true,
  },
};
