// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { action } from 'storybook/actions';

import ChecksFrequencyInput from './ChecksFrequencyInput';

function ControlledChecksFrequencyInput({ value: initialValue, ...props }) {
  const [value, setValue] = useState(initialValue);

  return (
    <ChecksFrequencyInput
      {...props}
      value={value}
      onChange={(newValue) => {
        setValue(newValue);
        props.onChange(newValue);
      }}
    />
  );
}

export default {
  title: 'Components/ChecksFrequencyInput',
  component: ChecksFrequencyInput,
  render: (args) => <ControlledChecksFrequencyInput {...args} />,
  argTypes: {
    value: {
      description:
        'Interval, for example `15m`, `6h`, `1w` or `disabled`. With `allowSystemSetting`, null follows the global interval',
      control: { type: 'text' },
    },
    allowSystemSetting: {
      description: 'Whether the system setting can be chosen',
      control: { type: 'boolean' },
    },
    disabled: {
      description: 'Whether the input is disabled',
      control: { type: 'boolean' },
    },
    onChange: {
      description: 'Callback with the new interval',
      action: 'onChange',
    },
  },
};

export const Default = {
  args: {
    value: '15m',
    allowSystemSetting: false,
    disabled: false,
    onChange: action('onChange'),
  },
};

export const PeriodicExecutionsDisabled = {
  args: {
    ...Default.args,
    value: 'disabled',
  },
};

export const SystemSetting = {
  args: {
    ...Default.args,
    value: null,
    allowSystemSetting: true,
  },
};

export const Disabled = {
  args: {
    ...Default.args,
    disabled: true,
  },
};
