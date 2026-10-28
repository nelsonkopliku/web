// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { lowerFirst, noop, upperFirst } from 'lodash';

import Button from '@common/Button';
import ChecksFrequencyInput from '@common/ChecksFrequencyInput';
import Label from '@common/Label';
import Modal from '@common/Modal';
import RecurrenceFields, {
  FieldRow,
  ValueAndUnit,
  optionOf,
} from '@common/RecurrenceFields';
import Select from '@common/Select';

import { getError, getGlobalError } from '@lib/api/validationErrors';
import {
  describeFrequency,
  formToWindow,
  windowFormErrors,
  windowToForm,
} from '@lib/model/checksSchedule';
import { describeOccurrences, recurrenceToForm } from '@lib/model/recurrence';
import { DEFAULT_TIMEZONE } from '@lib/timezones';

const defaultErrors = [];

const WINDOW_TYPES = [
  { value: 'none', label: 'None' },
  { value: 'one_time', label: 'One Time' },
  { value: 'periodic', label: 'Periodic' },
];

const DURATION_UNITS = [
  { value: 'minutes', label: 'Minutes' },
  { value: 'hours', label: 'Hours' },
];

// Fields of a refused window shown next to their field of the form, by the
// pointers of their errors: the request validation points into
// exception_window, the window validation prefixes the fields with window_
const ERROR_POINTERS = {
  start: ['exception_window/starts_at', 'window_starts_at'],
  duration: ['exception_window/duration_minutes', 'window_duration_minutes'],
  repeat: [
    'exception_window/recurrence/interval',
    'window_interval',
    'window_frequency',
  ],
  weekdays: ['exception_window/recurrence/weekdays', 'window_weekdays'],
};

const MAPPED_POINTERS = [
  '/interval',
  ...Object.values(ERROR_POINTERS)
    .flat()
    .map((pointer) => `/${pointer}`),
];

const errorAt = (field, errors) =>
  ERROR_POINTERS[field]
    .map((pointer) => getError(pointer, errors))
    .find(Boolean);

// Errors of a refused change that have no field in the form
function OtherErrors({ errors }) {
  return errors
    .filter(
      ({ source }) =>
        source?.pointer && !MAPPED_POINTERS.includes(source.pointer)
    )
    .map(({ detail, source: { pointer } }) => (
      <p key={`${pointer}-${detail}`} className="text-red-500 mt-1">
        {upperFirst(`${pointer.slice(1)}: ${detail}`)}
      </p>
    ));
}

function ErrorMessage({ text }) {
  return text ? <p className="text-red-500 mt-1">{upperFirst(text)}</p> : null;
}

// The start of an existing window, kept as it is when it is in the past
const startOf = (window) => {
  if (!window) return null;

  const { date, time } = recurrenceToForm(window, window.timezone);
  return { date, time };
};

/**
 * Modal to edit the checks execution frequency of a host or a cluster, and
 * its exception window. A new window uses the user timezone, an existing one
 * keeps its own.
 */
function TargetChecksExecutionModal({
  open = false,
  loading = false,
  schedule,
  timezone = DEFAULT_TIMEZONE,
  errors = defaultErrors,
  onSave = noop,
  onCancel = noop,
}) {
  const existingWindow = schedule.exception_window;
  const windowTimezone = existingWindow?.timezone ?? timezone;

  const [interval, setInterval] = useState(schedule.interval);
  const [form, setForm] = useState(() =>
    windowToForm(existingWindow, timezone)
  );
  const set = (changes) => setForm({ ...form, ...changes });

  const formErrors = windowFormErrors(form, windowTimezone, {
    unchangedStart: startOf(existingWindow),
  });
  const fieldErrors = {
    start: formErrors.start || errorAt('start', errors),
    repeat: formErrors.repeat || errorAt('repeat', errors),
    weekdays: errorAt('weekdays', errors),
  };
  const durationError = formErrors.duration || errorAt('duration', errors);
  const window = formToWindow(form, windowTimezone);
  const valid = Object.keys(formErrors).length === 0;

  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title="Check Execution Settings"
      open={open}
      onClose={onCancel}
    >
      <div className="text-gray-500">
        Configure how often the checks are executed, or follow the system
        setting.
      </div>
      <div className="grid grid-cols-6 my-5 gap-6 items-center">
        <Label className="col-span-2">Frequency</Label>
        <div className="col-span-4">
          <ChecksFrequencyInput
            value={interval}
            allowSystemSetting
            onChange={setInterval}
          />
          <p className="text-gray-500 text-sm mt-1">
            The system setting is{' '}
            {lowerFirst(describeFrequency(schedule.global_interval))}.
          </p>
          <ErrorMessage text={getError('interval', errors)} />
        </div>
      </div>

      <hr className="my-6" />

      <h3 className="text-lg font-bold">Exception Window</h3>
      <p className="text-gray-500">
        Configure when checks <span className="font-bold">should not</span> be
        run.
      </p>
      {form.type !== 'none' && (
        <p className="text-gray-500">Times are in {windowTimezone}.</p>
      )}
      <div className="grid grid-cols-6 my-5 gap-6 items-center">
        <FieldRow label="Type">
          <Select
            aria-label="Exception window type"
            options={WINDOW_TYPES}
            value={optionOf(WINDOW_TYPES, form.type)}
            onChange={(type) => set({ type })}
          />
        </FieldRow>

        {form.type !== 'none' && (
          <RecurrenceFields
            form={form}
            periodic={form.type === 'periodic'}
            errors={fieldErrors}
            onChange={set}
            afterTime={
              <FieldRow label="Duration" error={durationError}>
                <ValueAndUnit
                  label="Duration"
                  value={form.durationValue}
                  unit={form.durationUnit}
                  units={DURATION_UNITS}
                  error={Boolean(durationError)}
                  onChange={({ value, unit }) =>
                    set({ durationValue: value, durationUnit: unit })
                  }
                />
              </FieldRow>
            }
          />
        )}

        {window && valid && (
          <FieldRow label="Window">
            <span aria-label="window-summary" className="text-gray-500">
              {describeOccurrences(window, windowTimezone, {
                duration: window.duration_minutes,
              })}
            </span>
          </FieldRow>
        )}
      </div>

      <div className="flex flex-row w-80 space-x-2">
        <Button
          disabled={loading || !valid}
          onClick={() => onSave({ interval, exception_window: window })}
        >
          Save Settings
        </Button>
        <Button type="primary-white" onClick={onCancel}>
          Cancel
        </Button>
      </div>
      <OtherErrors errors={errors} />
      <ErrorMessage text={getGlobalError(errors)} />
    </Modal>
  );
}

export default TargetChecksExecutionModal;
