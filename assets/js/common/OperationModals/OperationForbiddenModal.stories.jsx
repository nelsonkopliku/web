// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { MemoryRouter } from 'react-router';
import { action } from 'storybook/actions';

import OperationForbiddenModal from './OperationForbiddenModal';

export default {
  title: 'Components/OperationForbiddenModal',
  component: OperationForbiddenModal,
  argTypes: {
    operation: {
      description: 'Operation name',
      control: { type: 'text' },
    },
    errors: {
      description: 'Authorization errors as string',
      control: { type: 'object' },
    },
    isOpen: {
      description: 'Modal is open',
      control: { type: 'boolean' },
    },
    onCancel: {
      description: 'Closes the modal',
      action: 'onCancel',
    },
  },
  args: {
    operation: 'My operation',
    errors: ['Authorization error 1', 'Authorization error 2'],
    isOpen: true,
    onCancel: action('onCancel'),
  },
};

export const Default = {
  args: {
    operation: 'Clean up resource',
    errors: [],
    isOpen: false,
    onCancel: action('onCancel'),
  },
};

export const DuringMaintenanceWindow = {
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: {
    operation: 'Reboot host',
    errors: [
      {
        detail:
          'Operations are not allowed during the maintenance window of {0}, until 2026-11-20 10:00 UTC',
        metadata: [
          {
            id: 'b2e3c1a9-6f3e-4c55-9e1b-0d6a3f0b7c42',
            label: 'hana_cluster',
            type: 'cluster',
          },
        ],
      },
    ],
    isOpen: true,
    onCancel: action('onCancel'),
  },
};
