// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import { checksScheduleFactory } from '@lib/test-utils/factories';

import TargetChecksExecutionModal from './TargetChecksExecutionModal';

export default {
  title: 'Components/TargetChecksExecutionModal',
  component: TargetChecksExecutionModal,
  argTypes: {
    open: {
      description: 'Whether the dialog is open or not',
      control: { type: 'boolean' },
    },
    loading: {
      description: 'Whether the settings are being saved',
      control: { type: 'boolean' },
    },
    schedule: {
      description: 'Checks schedule of the target',
      control: { type: 'object' },
    },
    errors: {
      description: 'Errors of a refused change, in the format of the API',
      control: { type: 'object' },
    },
    onSave: {
      description:
        'Callback with the new interval, null for the system setting',
      action: 'onSave',
    },
    onCancel: {
      description: 'Callback when the modal is closed without saving',
      action: 'onCancel',
    },
  },
};

export const SystemSetting = {
  args: {
    open: true,
    loading: false,
    schedule: checksScheduleFactory.build({
      interval: null,
      effective_interval: '15m',
      global_interval: '15m',
    }),
    errors: [],
    onSave: action('onSave'),
    onCancel: action('onCancel'),
  },
};

export const OwnFrequency = {
  args: {
    ...SystemSetting.args,
    schedule: checksScheduleFactory.build({
      interval: '1w',
      effective_interval: '1w',
      global_interval: '15m',
    }),
  },
};

export const Saving = {
  args: {
    ...SystemSetting.args,
    loading: true,
  },
};

export const WithErrors = {
  args: {
    ...SystemSetting.args,
    errors: [
      {
        detail: 'is invalid',
        source: { pointer: '/interval' },
        title: 'Invalid value',
      },
    ],
  },
};
