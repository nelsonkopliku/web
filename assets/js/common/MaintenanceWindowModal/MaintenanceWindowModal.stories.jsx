// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import { maintenanceWindowFactory } from '@lib/test-utils/factories';

import MaintenanceWindowModal from './MaintenanceWindowModal';

export default {
  title: 'Components/MaintenanceWindowModal',
  component: MaintenanceWindowModal,
  argTypes: {
    isOpen: {
      description: 'Whether the modal is open',
      control: { type: 'boolean' },
    },
    window: {
      description: 'Existing window to change, null to schedule a new one',
      control: { type: 'object' },
    },
    targetLabel: {
      description: 'What the window is for, like "host vmhana01"',
      control: { type: 'text' },
    },
    timezone: {
      description: 'Timezone of the user, for a new window',
      control: { type: 'text' },
    },
    loading: {
      description: 'Whether the window is being saved',
      control: { type: 'boolean' },
    },
    errors: {
      description: 'Errors of a refused window, in the format of the API',
      control: { type: 'object' },
    },
    onSave: {
      description: 'Callback with the window request',
      action: 'onSave',
    },
    onCancel: {
      description: 'Closes the modal',
      action: 'onCancel',
    },
  },
};

export const ScheduleMaintenance = {
  args: {
    isOpen: true,
    window: null,
    targetLabel: 'host vmhana01',
    timezone: 'Europe/Berlin',
    loading: false,
    errors: [],
    onSave: action('onSave'),
    onCancel: action('onCancel'),
  },
};

export const ChangeWindow = {
  args: {
    ...ScheduleMaintenance.args,
    window: maintenanceWindowFactory.build({
      timezone: 'Europe/Berlin',
      duration_minutes: 90,
      recurrence: {
        frequency: 'weekly',
        interval: 1,
        weekdays: [6],
        ends_on: null,
      },
      forbids: ['operations'],
    }),
  },
};

export const Refused = {
  args: {
    ...ScheduleMaintenance.args,
    errors: [
      {
        title: 'Invalid value',
        detail: 'must be less than or equal to 44640',
        source: { pointer: '/duration_minutes' },
      },
    ],
  },
};
