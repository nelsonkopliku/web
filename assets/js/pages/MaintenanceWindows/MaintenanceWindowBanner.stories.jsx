// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { MemoryRouter } from 'react-router';

import { maintenanceWindowFactory } from '@lib/test-utils/factories';

import MaintenanceWindowBanner from './MaintenanceWindowBanner';

const now = Date.now();
const hour = 60 * 60 * 1000;

const activeOccurrence = {
  starts_at: new Date(now - hour).toISOString(),
  ends_at: new Date(now + hour).toISOString(),
};

export default {
  title: 'Components/MaintenanceWindowBanner',
  component: MaintenanceWindowBanner,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  argTypes: {
    windows: {
      description: 'Windows that cover the target; only the active ones show',
      control: { type: 'object' },
    },
    timezone: {
      description: 'Timezone of the user',
      control: { type: 'text' },
    },
  },
};

export const OwnWindow = {
  args: {
    windows: [
      maintenanceWindowFactory.build({
        active: true,
        forbids: ['checks_execution', 'operations'],
        current_occurrence: activeOccurrence,
      }),
    ],
    timezone: 'Etc/UTC',
  },
};

export const InheritedWindow = {
  args: {
    ...OwnWindow.args,
    windows: [
      maintenanceWindowFactory.build({
        active: true,
        inherited: true,
        target_type: 'cluster',
        target_name: 'hana_cluster',
        forbids: ['operations'],
        current_occurrence: activeOccurrence,
      }),
    ],
  },
};
