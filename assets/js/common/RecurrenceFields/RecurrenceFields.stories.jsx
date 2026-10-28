// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { action } from 'storybook/actions';

import RecurrenceFields from './RecurrenceFields';

function ControlledRecurrenceFields({ form: initialForm, onChange, ...props }) {
  const [form, setForm] = useState(initialForm);

  return (
    <div className="grid grid-cols-6 gap-6 items-center">
      <RecurrenceFields
        {...props}
        form={form}
        onChange={(changes) => {
          setForm({ ...form, ...changes });
          onChange(changes);
        }}
      />
    </div>
  );
}

export default {
  title: 'Components/RecurrenceFields',
  component: RecurrenceFields,
  render: (args) => <ControlledRecurrenceFields {...args} />,
  argTypes: {
    form: {
      description:
        'Date, start time, repeat value and unit, and weekdays of the schedule',
      control: { type: 'object' },
    },
    periodic: {
      description: 'Whether the schedule repeats',
      control: { type: 'boolean' },
    },
    errors: {
      description: 'Messages of the start, repeat and weekdays fields',
      control: { type: 'object' },
    },
    onChange: {
      description: 'Callback with the changed fields',
      action: 'onChange',
    },
  },
};

export const OneTime = {
  args: {
    form: {
      date: '2026-11-20',
      time: '03:00',
      repeatValue: '1',
      repeatUnit: 'days',
      weekdays: [],
    },
    periodic: false,
    errors: {},
    onChange: action('onChange'),
  },
};

export const Weekly = {
  args: {
    ...OneTime.args,
    form: { ...OneTime.args.form, repeatUnit: 'weeks', weekdays: [6, 7] },
    periodic: true,
  },
};

export const WithErrors = {
  args: {
    ...OneTime.args,
    periodic: true,
    errors: {
      start: 'Pick a date and time in the future',
      repeat: 'Repeat at least every 1',
    },
  },
};
