// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

// Checks execution intervals of the scheduling contract: a value and a unit
// suffix, like 15m, 6h or 2w, or disabled.

import {
  describeOccurrences,
  formToRecurrence,
  nextFullHourIn,
  occurrenceAround,
  recurrenceToForm,
  startsInThePast,
} from './recurrence';

export const DISABLED = 'disabled';

// Selectable checks execution intervals, grouped by unit
export const FREQUENCY_UNITS = {
  minutes: {
    label: 'Minutes',
    singular: 'minute',
    suffix: 'm',
    values: [5, 15, 30],
  },
  hours: {
    label: 'Hours',
    singular: 'hour',
    suffix: 'h',
    values: [1, 6, 12, 24],
  },
  weeks: { label: 'Weeks', singular: 'week', suffix: 'w', values: [1, 2, 4] },
};

export const toFrequency = (interval) => {
  if (interval === DISABLED) return { value: null, unit: DISABLED };

  const [unit] = Object.entries(FREQUENCY_UNITS).find(([_unit, { suffix }]) =>
    interval.endsWith(suffix)
  );

  return { value: parseInt(interval, 10), unit };
};

export const toInterval = ({ value, unit }) =>
  unit === DISABLED ? DISABLED : `${value}${FREQUENCY_UNITS[unit].suffix}`;

export const frequencyLabel = (interval) => {
  if (interval === DISABLED) return 'Disabled';

  const { value, unit } = toFrequency(interval);
  const { singular } = FREQUENCY_UNITS[unit];
  return `${value} ${value === 1 ? singular : `${singular}s`}`;
};

// How often the checks are executed, for example "Every 15 minutes"
export const describeFrequency = (interval) => {
  if (interval === DISABLED) return 'Disabled';

  const { value, unit } = toFrequency(interval);
  return value === 1
    ? `Every ${FREQUENCY_UNITS[unit].singular}`
    : `Every ${frequencyLabel(interval)}`;
};

// Exception windows: when the checks of a host or a cluster are not
// executed, once or periodically, for some minutes

// Human readable summary of an exception window, in its own timezone
export const describeWindow = (window) =>
  window
    ? `${describeOccurrences(window, window.timezone, {
        duration: window.duration_minutes,
      })} (${window.timezone})`
    : 'None';

/**
 * Exception window as edited in the settings modal: an existing one in its
 * own timezone, a new one in the given timezone, starting at the next full
 * hour and lasting one hour
 */
export const windowToForm = (window, timezone, now = new Date()) => {
  if (!window) {
    return {
      type: 'none',
      ...nextFullHourIn(timezone, now),
      durationValue: '1',
      durationUnit: 'hours',
      repeatValue: '1',
      repeatUnit: 'days',
      weekdays: [],
    };
  }

  const inHours = window.duration_minutes % 60 === 0;

  return {
    type: window.recurrence ? 'periodic' : 'one_time',
    ...recurrenceToForm(window, window.timezone),
    durationValue: String(
      inHours ? window.duration_minutes / 60 : window.duration_minutes
    ),
    durationUnit: inHours ? 'hours' : 'minutes',
  };
};

export const formToWindow = (form, timezone) => {
  if (form.type === 'none') return null;

  const { starts_at: startsAt, recurrence } = formToRecurrence(
    form,
    timezone,
    form.type === 'periodic'
  );

  return {
    starts_at: startsAt,
    timezone,
    duration_minutes:
      Number(form.durationValue) * (form.durationUnit === 'hours' ? 60 : 1),
    recurrence,
  };
};

// When the exception window starts or ends next, null when it is over
export const nextWindowBoundary = (window, now = new Date()) => {
  if (!window) return null;

  const occurrence = occurrenceAround(window, window.duration_minutes, now);
  if (!occurrence) return null;

  return occurrence.startsAt > now ? occurrence.startsAt : occurrence.endsAt;
};

const windowStartError = (form, timezone, { now, unchangedStart }) => {
  if (!form.date || !form.time) return 'Pick a date and a start time';
  // A window keeps its start when changed, even when it is already active
  if (unchangedStart?.date === form.date && unchangedStart?.time === form.time)
    return null;
  return startsInThePast(form, timezone, now)
    ? 'Pick a date and time in the future'
    : null;
};

/**
 * Reasons why an exception window form cannot be saved, by field: start,
 * duration and repeat. Empty when the form is valid.
 */
export const windowFormErrors = (
  form,
  timezone,
  { now = new Date(), unchangedStart = null } = {}
) => {
  if (form.type === 'none') return {};

  const errors = {
    start: windowStartError(form, timezone, { now, unchangedStart }),
    duration: Number(form.durationValue) >= 1 ? null : 'Last at least 1 minute',
    repeat:
      form.type === 'periodic' && !(Number(form.repeatValue) >= 1)
        ? 'Repeat at least every 1'
        : null,
  };

  return Object.fromEntries(
    Object.entries(errors).filter(([_field, error]) => error)
  );
};

export const EXCEPTION_WINDOW_BLOCKS_EXECUTION =
  'Checks cannot be executed during exception window';

// Why the checks of a target cannot be executed now, null when they can
export const executionBlockedReason = (schedule) =>
  schedule?.in_exception_window ? EXCEPTION_WINDOW_BLOCKS_EXECUTION : null;
