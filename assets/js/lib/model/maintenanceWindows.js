// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

// Maintenance windows: time windows, once or periodically, where Trento does
// not execute checks or operations on a target and on the targets it covers.

import { filter, find, isEmpty } from 'lodash';

import {
  describeOccurrences,
  formToRecurrence,
  nextFullHourIn,
  recurrenceToForm,
  startsInThePast,
} from './recurrence';

export const CHECKS_EXECUTION = 'checks_execution';
export const OPERATIONS = 'operations';

export const FORBIDS = [
  { value: CHECKS_EXECUTION, label: 'Check execution' },
  { value: OPERATIONS, label: 'Operations' },
];

// 31 days, the longest window the server accepts
const MAX_DURATION_MINUTES = 44640;

export const CHECKS_EXECUTION_BLOCKED =
  'Checks cannot be executed during a maintenance window';

export const describeForbids = (forbids = []) => {
  const checks = forbids.includes(CHECKS_EXECUTION);
  const operations = forbids.includes(OPERATIONS);

  if (checks && operations) return 'Check execution and operations';
  return checks ? 'Check execution' : 'Operations';
};

// Human readable summary of a window, in its own timezone
export const describeMaintenanceWindow = (window) =>
  `${describeOccurrences(window, window.timezone, {
    duration: window.duration_minutes,
  })} (${window.timezone})`;

/**
 * Maintenance window as edited in the modal: an existing one in its own
 * timezone, a new one in the given timezone, starting at the next full hour,
 * lasting one hour and forbidding everything
 */
export const maintenanceWindowToForm = (window, timezone, now = new Date()) => {
  if (!window) {
    return {
      forbids: [CHECKS_EXECUTION, OPERATIONS],
      type: 'one_time',
      ...nextFullHourIn(timezone, now),
      durationValue: '1',
      durationUnit: 'hours',
      repeatValue: '1',
      repeatUnit: 'days',
      weekdays: [],
      ends: 'never',
      endsOn: '',
    };
  }

  const inHours = window.duration_minutes % 60 === 0;
  const endsOn = window.recurrence?.ends_on;

  return {
    forbids: window.forbids,
    type: window.recurrence ? 'periodic' : 'one_time',
    ...recurrenceToForm(window, window.timezone),
    durationValue: String(
      inHours ? window.duration_minutes / 60 : window.duration_minutes
    ),
    durationUnit: inHours ? 'hours' : 'minutes',
    ends: endsOn ? 'on' : 'never',
    endsOn: endsOn || '',
  };
};

const durationMinutes = ({ durationValue, durationUnit }) =>
  Number(durationValue) * (durationUnit === 'hours' ? 60 : 1);

export const formToMaintenanceWindow = (form, timezone) => {
  const periodic = form.type === 'periodic';
  const { starts_at: startsAt, recurrence } = formToRecurrence(
    form,
    timezone,
    periodic
  );

  return {
    starts_at: startsAt,
    timezone,
    duration_minutes: durationMinutes(form),
    recurrence: periodic
      ? { ...recurrence, ends_on: form.ends === 'on' ? form.endsOn : null }
      : null,
    forbids: form.forbids,
  };
};

const startError = (form, timezone, { now, unchangedStart }) => {
  if (!form.date || !form.time) return 'Pick a date and a start time';
  // A window keeps its start when changed, even when it is already active
  if (unchangedStart?.date === form.date && unchangedStart?.time === form.time)
    return null;
  return startsInThePast(form, timezone, now)
    ? 'Pick a date and time in the future'
    : null;
};

const durationError = (form) => {
  const minutes = durationMinutes(form);

  if (!(minutes >= 1)) return 'Last at least 1 minute';
  return minutes > MAX_DURATION_MINUTES ? 'Last at most 31 days' : null;
};

const endsError = (form) => {
  if (form.type !== 'periodic' || form.ends !== 'on') return null;
  if (!form.endsOn) return 'Pick the end date';
  return form.endsOn <= form.date
    ? 'The end date must be after the start date'
    : null;
};

/**
 * Reasons why a maintenance window form cannot be saved, by field: forbids,
 * start, duration, repeat and ends. Empty when the form is valid.
 */
export const maintenanceWindowFormErrors = (
  form,
  timezone,
  { now = new Date(), unchangedStart = null } = {}
) => {
  const errors = {
    forbids: isEmpty(form.forbids)
      ? 'Forbid check execution, operations or both'
      : null,
    start: startError(form, timezone, { now, unchangedStart }),
    duration: durationError(form),
    repeat:
      form.type === 'periodic' && !(Number(form.repeatValue) >= 1)
        ? 'Repeat at least every 1'
        : null,
    ends: endsError(form),
  };

  return Object.fromEntries(
    Object.entries(errors).filter(([_field, error]) => error)
  );
};

export const activeWindows = (windows) => filter(windows, { active: true });

// The active window that forbids executing the checks of the target, if any
export const checksExecutionBlockedBy = (windows) =>
  find(
    windows,
    ({ active, forbids }) => active && forbids.includes(CHECKS_EXECUTION)
  );

// When a window starts or ends next, null when no window is active or
// upcoming
export const nextWindowsBoundary = (windows, now = new Date()) => {
  const boundaries = windows
    .flatMap(({ current_occurrence: current, next_occurrence: next }) => [
      current?.ends_at,
      next?.starts_at,
    ])
    .filter(Boolean)
    .map((date) => new Date(date))
    .filter((date) => date > now)
    .sort((a, b) => a - b);

  return boundaries[0] ?? null;
};
