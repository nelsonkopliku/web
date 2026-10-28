// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { MemoryRouter } from 'react-router';
import { action } from 'storybook/actions';

import {
  abilityFactory,
  maintenanceWindowFactory,
} from '@lib/test-utils/factories';

import MaintenanceWindowsSection from './MaintenanceWindowsSection';

const now = Date.now();
const hour = 60 * 60 * 1000;

export default {
  title: 'Components/MaintenanceWindowsSection',
  component: MaintenanceWindowsSection,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  argTypes: {
    windows: {
      description: 'Windows that cover the target, own and inherited',
      control: { type: 'object' },
    },
    error: {
      description: 'Whether the windows could not be loaded',
      control: { type: 'boolean' },
    },
    timezone: {
      description: 'Timezone of the user',
      control: { type: 'text' },
    },
    targetLabel: {
      description: 'What the windows are for, like "host vmhana01"',
      control: { type: 'text' },
    },
    userAbilities: {
      description:
        'Abilities of the user, changes need all:maintenance_windows',
      control: { type: 'object' },
    },
    submission: {
      description: 'Submission of the window being saved: status and errors',
      control: { type: 'object' },
    },
    onSchedule: { description: 'Schedules a window', action: 'onSchedule' },
    onUpdate: { description: 'Changes a window', action: 'onUpdate' },
    onDelete: { description: 'Deletes a window', action: 'onDelete' },
    onRetry: { description: 'Loads the windows again', action: 'onRetry' },
    onResetSubmission: {
      description: 'Forgets the last submission',
      action: 'onResetSubmission',
    },
  },
};

export const Default = {
  args: {
    windows: [
      maintenanceWindowFactory.build({
        target_type: 'cluster',
        target_name: 'hana_cluster',
        inherited: true,
        active: true,
        forbids: ['operations'],
        current_occurrence: {
          starts_at: new Date(now - hour).toISOString(),
          ends_at: new Date(now + hour).toISOString(),
        },
      }),
      maintenanceWindowFactory.build({
        target_name: 'vmhana01',
        timezone: 'Europe/Berlin',
        recurrence: {
          frequency: 'weekly',
          interval: 1,
          weekdays: [6],
          ends_on: null,
        },
      }),
    ],
    error: false,
    timezone: 'Etc/UTC',
    targetLabel: 'host vmhana01',
    userAbilities: [abilityFactory.build({ name: 'all', resource: 'all' })],
    onSchedule: action('onSchedule'),
    onUpdate: action('onUpdate'),
    onDelete: action('onDelete'),
    onRetry: action('onRetry'),
    onResetSubmission: action('onResetSubmission'),
  },
};

export const Empty = {
  args: {
    ...Default.args,
    windows: [],
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
    windows: [],
    error: true,
  },
};
