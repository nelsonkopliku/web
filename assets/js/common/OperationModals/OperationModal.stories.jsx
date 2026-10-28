// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import { operationScheduleFactory } from '@lib/test-utils/factories';

import OperationModal from './OperationModal';

export default {
  title: 'Components/OperationModal',
  component: OperationModal,
  argTypes: {
    dontShowAgainDisclaimerChecked: {
      description: 'Whether the dont show again disclaimer is checked',
      control: { type: 'boolean' },
    },
    setDontShowAgainDisclaimerChecked: {
      description:
        'Callback function invoked when dont show again disclaimer checked',
      action: 'setDontShowAgainDisclaimerChecked',
    },
    operationText: {
      description: 'Text label for the operation button',
      control: { type: 'text' },
    },
    title: {
      description: 'Title text for the component',
      control: { type: 'text' },
    },
    description: {
      description: 'Description text for the modal',
      control: { type: 'text' },
    },
    requestDisabled: {
      description: 'Whether the request button is disabled',
      control: { type: 'boolean' },
    },
    isOpen: {
      description: 'Whether the component is open or visible',
      control: { type: 'boolean' },
    },
    schedulable: {
      description: 'Whether the operation can be scheduled',
      control: { type: 'boolean' },
    },
    timezone: {
      description: 'Timezone of the user, for new schedules',
      control: { type: 'text' },
    },
    initialSchedule: {
      description: 'Existing schedule to change or cancel',
      control: { type: 'object' },
    },
    existingSchedules: {
      description:
        'Schedules of the same operation for the target, to warn before scheduling it again',
      control: { type: 'object' },
    },
    loading: {
      description: 'Whether a request is ongoing',
      control: { type: 'boolean' },
    },
    errors: {
      description: 'Errors of a refused schedule, in the format of the API',
      control: { type: 'object' },
    },
    onRequest: {
      description:
        'Callback function invoked when request, with the schedule or null to request now',
      action: 'onRequest',
    },
    onCancelSchedule: {
      description: 'Callback function invoked when the schedule is cancelled',
      action: 'onCancelSchedule',
    },
    onCancel: {
      description: 'Callback function invoked when cancel',
      action: 'onCancel',
    },
    children: {
      description: 'Content or text displayed inside the component',
      control: { type: 'text' },
    },
  },
};

export const Default = {
  args: {
    dontShowAgainDisclaimerChecked: false,
    operationText: 'Confirm',
    title: 'Confirm Operation',
    description: 'Are you sure you want to proceed?',
    requestDisabled: false,
    isOpen: true,
    children: 'Operation details will be displayed here',
    setDontShowAgainDisclaimerChecked: action(
      'setDontShowAgainDisclaimerChecked'
    ),
    onRequest: action('onRequest'),
    onCancel: action('onCancel'),
  },
};

export const Schedulable = {
  args: {
    ...Default.args,
    schedulable: true,
    timezone: 'Europe/Berlin',
  },
};

export const ChangeSchedule = {
  args: {
    ...Schedulable.args,
    initialSchedule: operationScheduleFactory.build({
      recurrence: {
        frequency: 'weekly',
        interval: 1,
        weekdays: [6],
        ends_on: null,
        max_occurrences: null,
      },
    }),
    onCancelSchedule: action('onCancelSchedule'),
  },
};

export const AlreadyScheduled = {
  args: {
    ...Schedulable.args,
    existingSchedules: operationScheduleFactory.buildList(2),
  },
};

export const RefusedSchedule = {
  args: {
    ...Schedulable.args,
    errors: [
      {
        title: 'Invalid value',
        detail: 'must be greater than or equal to 1',
        source: { pointer: '/params/timeout' },
      },
      { title: 'Forbidden', detail: 'You can not perform this action.' },
    ],
  },
};

export const Requesting = {
  args: {
    ...Schedulable.args,
    loading: true,
  },
};
