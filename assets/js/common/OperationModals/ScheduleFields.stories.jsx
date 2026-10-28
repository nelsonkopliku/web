// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { action } from 'storybook/actions';

import ScheduleFields, { initialScheduleForm } from './ScheduleFields';

function ControlledScheduleFields({ form: initialForm, onChange, ...props }) {
  const [form, setForm] = useState(initialForm);

  return (
    <ScheduleFields
      {...props}
      form={form}
      onChange={(newForm) => {
        setForm(newForm);
        onChange(newForm);
      }}
    />
  );
}

const form = initialScheduleForm('Europe/Berlin');

export default {
  title: 'Components/ScheduleFields',
  component: ScheduleFields,
  render: (args) => <ControlledScheduleFields {...args} />,
  argTypes: {
    form: {
      description: 'The schedule as edited in the form',
      control: { type: 'object' },
    },
    timezone: {
      description: 'Timezone of the schedule',
      control: { type: 'text' },
    },
    allowNow: {
      description: 'Whether the operation can be requested now',
      control: { type: 'boolean' },
    },
    errors: {
      description: 'Errors of a refused schedule, in the format of the API',
      control: { type: 'object' },
    },
    onChange: {
      description: 'Callback with the changed form',
      action: 'onChange',
    },
  },
};

export const Now = {
  args: {
    form,
    timezone: 'Europe/Berlin',
    allowNow: true,
    errors: [],
    onChange: action('onChange'),
  },
};

export const OneTime = {
  args: {
    ...Now.args,
    form: { ...form, type: 'one_time' },
  },
};

export const PeriodicWithEnd = {
  args: {
    ...Now.args,
    form: {
      ...form,
      type: 'periodic',
      repeatValue: '2',
      repeatUnit: 'weeks',
      weekdays: [6, 7],
      ends: 'after',
      maxOccurrences: '5',
    },
  },
};

export const InThePast = {
  args: {
    ...Now.args,
    form: { ...form, type: 'one_time', date: '2020-01-01' },
  },
};

export const RefusedByTheServer = {
  args: {
    ...OneTime.args,
    errors: [
      {
        title: 'Invalid value',
        detail: 'must be in the future',
        source: { pointer: '/starts_at' },
      },
    ],
  },
};
