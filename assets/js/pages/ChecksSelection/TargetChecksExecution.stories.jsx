// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import {
  abilityFactory,
  checksScheduleFactory,
} from '@lib/test-utils/factories';

import TargetChecksExecution from './TargetChecksExecution';

export default {
  title: 'Components/TargetChecksExecution',
  component: TargetChecksExecution,
  argTypes: {
    targetType: {
      description: 'Type of the target',
      control: { type: 'radio' },
      options: ['host', 'cluster'],
    },
    schedule: {
      description:
        'Checks schedule of the target: `interval` (null for the system setting), `effective_interval` and `global_interval`',
      control: { type: 'object' },
    },
    userAbilities: {
      description: 'Abilities of the user, editing needs all:check_frequency',
      control: { type: 'object' },
    },
    onEditClick: {
      description: 'Callback when the Edit Settings button is clicked',
      action: 'onEditClick',
    },
  },
};

export const SystemSetting = {
  args: {
    targetType: 'host',
    schedule: checksScheduleFactory.build({
      interval: null,
      effective_interval: '15m',
      global_interval: '15m',
    }),
    userAbilities: [abilityFactory.build({ name: 'all', resource: 'all' })],
    onEditClick: action('onEditClick'),
  },
};

export const OwnFrequency = {
  args: {
    ...SystemSetting.args,
    targetType: 'cluster',
    schedule: checksScheduleFactory.build({
      interval: '6h',
      effective_interval: '6h',
      global_interval: '15m',
    }),
  },
};

export const PeriodicExecutionsDisabled = {
  args: {
    ...SystemSetting.args,
    schedule: checksScheduleFactory.build({
      interval: 'disabled',
      effective_interval: 'disabled',
      global_interval: '15m',
    }),
  },
};

export const EditUnauthorized = {
  args: {
    ...SystemSetting.args,
    userAbilities: [],
  },
};
