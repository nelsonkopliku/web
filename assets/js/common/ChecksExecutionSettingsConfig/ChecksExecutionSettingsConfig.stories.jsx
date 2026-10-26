// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import {
  abilityFactory,
  checksExecutionSettingsFactory,
} from '@lib/test-utils/factories';

import ChecksExecutionSettingsConfig from './ChecksExecutionSettingsConfig';

const allAbility = abilityFactory.build({ name: 'all', resource: 'all' });

export default {
  title: 'Components/ChecksExecutionSettingsConfig',
  component: ChecksExecutionSettingsConfig,
  argTypes: {
    settings: {
      description:
        'Global checks execution settings: `interval` (for example `15m`, `6h`, `1w` or `disabled`) and `enforced_from_env`',
      control: { type: 'object' },
    },
    userAbilities: {
      description:
        'Abilities of the user, editing needs all:checks_execution_settings',
      control: { type: 'object' },
    },
    onEditClick: {
      description: 'Callback when the Edit Settings button is clicked',
      action: 'onEditClick',
    },
  },
};

export const Default = {
  args: {
    settings: checksExecutionSettingsFactory.build({ interval: '15m' }),
    userAbilities: [allAbility],
    onEditClick: action('onEditClick'),
  },
};

export const Disabled = {
  args: {
    ...Default.args,
    settings: checksExecutionSettingsFactory.build({ interval: 'disabled' }),
  },
};

export const EnforcedFromEnv = {
  args: {
    ...Default.args,
    settings: checksExecutionSettingsFactory.build({
      interval: '1h',
      enforced_from_env: true,
    }),
  },
};

export const EditUnauthorized = {
  args: {
    ...Default.args,
    userAbilities: [],
  },
};
