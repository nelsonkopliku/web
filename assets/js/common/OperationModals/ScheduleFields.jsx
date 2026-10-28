// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { isEmpty, noop, upperFirst } from 'lodash';

import Input, { InputNumber } from '@common/Input';
import PremiumPill from '@common/PremiumPill';
import RecurrenceFields, {
  FieldError,
  FieldRow,
  optionOf,
} from '@common/RecurrenceFields';
import Select from '@common/Select';
import { getError, getGlobalError } from '@lib/api/validationErrors';
import {
  describeOccurrences,
  formToRecurrence,
  nextFullHourIn,
  recurrenceToForm,
  startsInThePast,
} from '@lib/model/recurrence';

const NOW = { value: 'now', label: 'Now' };

const SCHEDULED_TYPES = [
  { value: 'one_time', label: 'One Time' },
  { value: 'periodic', label: 'Periodic' },
];

const ENDS = [
  { value: 'never', label: 'Never' },
  { value: 'on', label: 'On date' },
  { value: 'after', label: 'After' },
];

const defaultErrors = [];

export const initialScheduleForm = (timezone, now = new Date()) => ({
  type: 'now',
  ...nextFullHourIn(timezone, now),
  repeatValue: '1',
  repeatUnit: 'days',
  weekdays: [],
  ends: 'never',
  endsOn: '',
  maxOccurrences: '1',
});

// Form of an existing schedule, to change it, in the timezone of the schedule
export const scheduleToForm = (schedule) => {
  const { recurrence, timezone } = schedule;
  let ends = 'never';
  if (recurrence?.ends_on) ends = 'on';
  if (recurrence?.max_occurrences) ends = 'after';

  return {
    ...initialScheduleForm(timezone),
    ...recurrenceToForm(schedule, timezone),
    type: recurrence ? 'periodic' : 'one_time',
    ends,
    endsOn: recurrence?.ends_on || '',
    maxOccurrences: String(recurrence?.max_occurrences || 1),
  };
};

// Schedule of the request, or null to request the operation now
export const toScheduleRequest = (form, timezone) => {
  if (form.type === 'now') return null;

  const periodic = form.type === 'periodic';
  const { recurrence, ...starts } = formToRecurrence(form, timezone, periodic);

  if (!periodic) return { ...starts, recurrence: null };

  return {
    ...starts,
    recurrence: {
      ...recurrence,
      ends_on: form.ends === 'on' ? form.endsOn : null,
      max_occurrences:
        form.ends === 'after' ? Number(form.maxOccurrences) : null,
    },
  };
};

const isUnchangedStart = (form, unchangedStart) =>
  form.type === 'periodic' &&
  unchangedStart?.date === form.date &&
  unchangedStart?.time === form.time;

const startError = (form, timezone, { now, unchangedStart }) => {
  if (!form.date || !form.time) return 'Pick a date and a start time';
  if (isUnchangedStart(form, unchangedStart)) return null;
  return startsInThePast(form, timezone, now)
    ? 'Pick a date and time in the future'
    : null;
};

const endsError = (form) => {
  if (form.ends === 'on' && !form.endsOn) return 'Pick the end date';
  if (form.ends === 'on' && form.endsOn <= form.date) {
    return 'The end date must be after the start date';
  }
  if (form.ends === 'after' && !(Number(form.maxOccurrences) >= 1)) {
    return 'Run at least once';
  }
  return null;
};

/**
 * Reasons why a schedule form cannot be requested, by field: start, repeat
 * and ends. Empty when the form is valid. An ongoing periodic schedule keeps
 * its past start when `unchangedStart` matches the form.
 */
export const scheduleFormErrors = (
  form,
  timezone,
  { now = new Date(), unchangedStart = null } = {}
) => {
  if (form.type === 'now') return {};

  const errors = {
    start: startError(form, timezone, { now, unchangedStart }),
    repeat:
      form.type === 'periodic' && !(Number(form.repeatValue) >= 1)
        ? 'Repeat at least every 1'
        : null,
    ends: form.type === 'periodic' ? endsError(form) : null,
  };

  return Object.fromEntries(
    Object.entries(errors).filter(([_field, error]) => error)
  );
};

export const isScheduleFormValid = (errors) => isEmpty(errors);

// Fields of a refused schedule shown next to their field of the form, by the
// pointers of their errors: the request validation points into recurrence,
// the schedule validation names the fields
const ERROR_POINTERS = {
  start: ['starts_at'],
  timezone: ['timezone'],
  repeat: ['recurrence/interval', 'interval'],
  weekdays: ['recurrence/weekdays', 'weekdays'],
  ends: [
    'recurrence/ends_on',
    'ends_on',
    'recurrence/max_occurrences',
    'max_occurrences',
  ],
};

const SCHEDULE_ERROR_POINTERS = Object.values(ERROR_POINTERS)
  .flat()
  .map((pointer) => `/${pointer}`);

const errorAt = (pointers, errors) =>
  pointers.map((pointer) => getError(pointer, errors)).find(Boolean);

// Errors of a refused schedule, by field of the form
const apiErrorsByField = (errors) =>
  Object.fromEntries(
    Object.entries(ERROR_POINTERS).map(([field, pointers]) => [
      field,
      errorAt(pointers, errors),
    ])
  );

/**
 * Errors of a refused schedule that ScheduleFields does not show next to a
 * field, like the ones of the operation params, and the global error
 */
export function ScheduleRequestErrors({ errors }) {
  const fieldErrors = errors.filter(
    ({ source }) =>
      source?.pointer && !SCHEDULE_ERROR_POINTERS.includes(source.pointer)
  );
  const globalError = getGlobalError(errors);

  return (
    <div className="text-red-500 text-sm mt-2">
      {fieldErrors.map(({ detail, source: { pointer } }) => (
        <p key={`${pointer}-${detail}`}>
          {upperFirst(`${pointer.slice(1)}: ${detail}`)}
        </p>
      ))}
      {globalError && <p>{upperFirst(globalError)}</p>}
    </div>
  );
}

/**
 * Schedule section of the operation modal: now, once or periodically, in
 * the given timezone. `errors` are the errors of a refused schedule.
 */
function ScheduleFields({
  form,
  timezone,
  allowNow = true,
  unchangedStart = null,
  errors = defaultErrors,
  onChange = noop,
}) {
  const set = (changes) => onChange({ ...form, ...changes });
  const periodic = form.type === 'periodic';
  const types = allowNow ? [NOW, ...SCHEDULED_TYPES] : SCHEDULED_TYPES;

  const formErrors = scheduleFormErrors(form, timezone, { unchangedStart });
  const apiErrors = apiErrorsByField(errors);
  const fieldErrors = {
    start: formErrors.start || apiErrors.start,
    repeat: formErrors.repeat || apiErrors.repeat,
    weekdays: apiErrors.weekdays,
    ends: formErrors.ends || apiErrors.ends,
  };
  const schedule = toScheduleRequest(form, timezone);

  return (
    <div className="mt-6 border-t pt-6">
      <h3 className="text-lg font-bold">
        Schedule
        <PremiumPill className="ml-3 align-middle" />
      </h3>
      <p className="text-gray-500">
        Request the operation now, or at a later date and time.
      </p>
      {form.type !== 'now' && (
        <p className="text-gray-500">Times are in {timezone}.</p>
      )}
      <FieldError text={apiErrors.timezone} />
      <div className="grid grid-cols-6 my-5 gap-6 items-center">
        <FieldRow label="Type">
          <Select
            aria-label="Schedule type"
            options={types}
            value={optionOf(types, form.type)}
            onChange={(type) => set({ type })}
          />
        </FieldRow>

        {form.type !== 'now' && (
          <RecurrenceFields
            form={form}
            periodic={periodic}
            errors={fieldErrors}
            onChange={set}
          />
        )}

        {periodic && (
          <FieldRow label="Ends" error={fieldErrors.ends}>
            <div className="flex items-center space-x-4">
              <div className="w-40">
                <Select
                  aria-label="Ends"
                  options={ENDS}
                  value={optionOf(ENDS, form.ends)}
                  onChange={(ends) => set({ ends })}
                />
              </div>
              {form.ends === 'on' && (
                <Input
                  type="date"
                  aria-label="End date"
                  value={form.endsOn}
                  error={Boolean(fieldErrors.ends)}
                  onChange={({ target: { value } }) => set({ endsOn: value })}
                />
              )}
              {form.ends === 'after' && (
                <>
                  <div className="w-32">
                    <InputNumber
                      aria-label="Occurrences"
                      className="!h-9"
                      min="1"
                      value={form.maxOccurrences}
                      error={Boolean(fieldErrors.ends)}
                      onChange={(value) =>
                        set({ maxOccurrences: String(value ?? '') })
                      }
                    />
                  </div>
                  <span className="text-gray-500">occurrences</span>
                </>
              )}
            </div>
          </FieldRow>
        )}

        {schedule && isScheduleFormValid(formErrors) && (
          <FieldRow label="Runs">
            <span aria-label="schedule-summary" className="text-gray-500">
              {describeOccurrences(schedule, timezone)}
            </span>
          </FieldRow>
        )}
      </div>
    </div>
  );
}

export default ScheduleFields;
