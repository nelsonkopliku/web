// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import ChecksExecutionSettingsModal from './ChecksExecutionSettingsModal';

export default {
  title: 'Components/ChecksExecutionSettingsModal',
  component: ChecksExecutionSettingsModal,
  argTypes: {
    open: {
      description: 'Whether the dialog is open or not',
      control: { type: 'boolean' },
    },
    loading: {
      description: 'Whether the settings are being saved',
      control: { type: 'boolean' },
    },
    initialInterval: {
      description:
        'Current interval, for example `15m`, `6h`, `1w` or `disabled`',
      control: { type: 'text' },
    },
    errors: {
      description: 'Errors of a refused change, in the format of the API',
      control: { type: 'object' },
    },
    onSave: {
      description: 'Callback with the new settings',
      action: 'onSave',
    },
    onCancel: {
      description: 'Callback when the modal is closed without saving',
      action: 'onCancel',
    },
  },
};

export const Default = {
  args: {
    open: true,
    loading: false,
    initialInterval: '15m',
    errors: [],
    onSave: action('onSave'),
    onCancel: action('onCancel'),
  },
};

export const Saving = {
  args: {
    ...Default.args,
    loading: true,
  },
};

export const WithFieldError = {
  args: {
    ...Default.args,
    errors: [
      {
        detail: 'is invalid',
        source: { pointer: '/interval' },
        title: 'Invalid value',
      },
    ],
  },
};

export const EnforcedFromEnvError = {
  args: {
    ...Default.args,
    errors: [
      {
        detail:
          'The checks execution frequency is enforced by the CHECKS_INTERVAL environment variable',
        title: 'Conflict',
      },
    ],
  },
};
