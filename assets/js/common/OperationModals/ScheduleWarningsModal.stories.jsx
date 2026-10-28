// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { MemoryRouter } from 'react-router';
import { action } from 'storybook/actions';

import { hostFactory, policyWarningFactory } from '@lib/test-utils/factories';

import ScheduleWarningsModal from './ScheduleWarningsModal';

const host = hostFactory.build();

export default {
  title: 'Components/ScheduleWarningsModal',
  component: ScheduleWarningsModal,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  argTypes: {
    isOpen: {
      description: 'Whether the dialog is open or not',
      control: { type: 'boolean' },
    },
    operation: {
      description: 'Label of the scheduled operation',
      control: { type: 'text' },
    },
    warnings: {
      description:
        'Policies that would not pass now: message, metadata of its {n} resources and, for bulk schedules, targetName',
      control: { type: 'object' },
    },
    onClose: {
      description: 'Callback when the dialog is closed',
      action: 'onClose',
    },
  },
};

export const Default = {
  args: {
    isOpen: true,
    operation: 'Reboot host',
    warnings: [
      policyWarningFactory.build({
        message: 'Trento agent is not currently running in the host {0}',
        metadata: [{ id: host.id, label: host.hostname, type: 'host' }],
      }),
    ],
    onClose: action('onClose'),
  },
};

export const Bulk = {
  args: {
    ...Default.args,
    warnings: hostFactory.buildList(3).map(({ hostname }) => ({
      ...policyWarningFactory.build(),
      targetName: hostname,
    })),
  },
};
