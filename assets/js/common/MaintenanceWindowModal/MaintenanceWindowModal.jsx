// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useState } from 'react';
import { noop, upperFirst } from 'lodash';

import Button from '@common/Button';
import Input, { Checkbox } from '@common/Input';
import Label from '@common/Label';
import Modal from '@common/Modal';
import RecurrenceFields, {
  FieldError,
  FieldRow,
  ValueAndUnit,
  optionOf,
} from '@common/RecurrenceFields';
import Select from '@common/Select';

import { getError, getGlobalError } from '@lib/api/validationErrors';
import {
  FORBIDS,
  describeMaintenanceWindow,
  formToMaintenanceWindow,
  maintenanceWindowFormErrors,
  maintenanceWindowToForm,
} from '@lib/model/maintenanceWindows';
import { recurrenceToForm } from '@lib/model/recurrence';
import { DEFAULT_TIMEZONE } from '@lib/timezones';

const defaultErrors = [];

const TYPES = [
  { value: 'one_time', label: 'One Time' },
  { value: 'periodic', label: 'Periodic' },
];

const DURATION_UNITS = [
  { value: 'minutes', label: 'Minutes' },
  { value: 'hours', label: 'Hours' },
];

const ENDS = [
  { value: 'never', label: 'Never' },
  { value: 'on', label: 'On date' },
];

// Fields of a refused window shown next to their field of the form, by the
// pointers of their errors: the request validation points into recurrence,
// the window validation names the fields
const ERROR_POINTERS = {
  forbids: ['forbids'],
  start: ['starts_at'],
  duration: ['duration_minutes'],
  repeat: ['recurrence/interval', 'interval'],
  weekdays: ['recurrence/weekdays', 'weekdays'],
  ends: ['recurrence/ends_on', 'ends_on'],
};

const MAPPED_POINTERS = Object.values(ERROR_POINTERS)
  .flat()
  .map((pointer) => `/${pointer}`);

const errorAt = (field, errors) =>
  ERROR_POINTERS[field]
    .map((pointer) => getError(pointer, errors))
    .find(Boolean);

// Errors of a refused window that have no field in the form
const otherFieldErrors = (errors) =>
  errors.filter(
    ({ source }) => source?.pointer && !MAPPED_POINTERS.includes(source.pointer)
  );

// The start of an existing window, kept as it is when it is in the past
const startOf = (window) => {
  if (!window) return null;

  const { date, time } = recurrenceToForm(window, window.timezone);
  return { date, time };
};

/**
 * Modal to schedule a maintenance window, or to change an existing one: what
 * it forbids, when it starts, how long it lasts, and how it repeats. A new
 * window uses the user timezone, an existing one keeps its own.
 * `targetLabel` names what the window is for, like "host vmhana01".
 */
function MaintenanceWindowModal({
  isOpen = false,
  window = null,
  targetLabel,
  timezone = DEFAULT_TIMEZONE,
  loading = false,
  errors = defaultErrors,
  onSave = noop,
  onCancel = noop,
}) {
  const windowTimezone = window?.timezone ?? timezone;
  const [form, setForm] = useState(() =>
    maintenanceWindowToForm(window, timezone)
  );
  const set = (changes) => setForm({ ...form, ...changes });

  const toggleForbid = (forbid) =>
    set({
      forbids: form.forbids.includes(forbid)
        ? form.forbids.filter((value) => value !== forbid)
        : [...form.forbids, forbid],
    });

  const formErrors = maintenanceWindowFormErrors(form, windowTimezone, {
    unchangedStart: startOf(window),
  });
  const valid = Object.keys(formErrors).length === 0;
  const request = formToMaintenanceWindow(form, windowTimezone);

  const fieldErrors = Object.fromEntries(
    Object.keys(ERROR_POINTERS).map((field) => [
      field,
      formErrors[field] || errorAt(field, errors),
    ])
  );
  const globalError = getGlobalError(errors);

  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title={window ? 'Change Maintenance Window' : 'Schedule Maintenance'}
      open={isOpen}
      onClose={onCancel}
    >
      <p className="text-gray-500">
        During the window, Trento does not execute the forbidden actions on{' '}
        {targetLabel} and on the targets it covers.
      </p>
      <p className="text-gray-500">Times are in {windowTimezone}.</p>
      <div className="grid grid-cols-6 my-5 gap-6 items-center">
        <Label className="col-span-2">Forbids</Label>
        <div className="col-span-4">
          <div className="flex space-x-6">
            {FORBIDS.map(({ value, label }) => (
              <Label key={value} className="cursor-pointer">
                <Checkbox
                  className="mr-2"
                  aria-label={label}
                  checked={form.forbids.includes(value)}
                  onChange={() => toggleForbid(value)}
                />
                {label}
              </Label>
            ))}
          </div>
          <FieldError text={fieldErrors.forbids} />
        </div>

        <FieldRow label="Type">
          <Select
            aria-label="Window type"
            options={TYPES}
            value={optionOf(TYPES, form.type)}
            onChange={(type) => set({ type })}
          />
        </FieldRow>

        <RecurrenceFields
          form={form}
          periodic={form.type === 'periodic'}
          errors={fieldErrors}
          onChange={set}
          afterTime={
            <FieldRow label="Duration" error={fieldErrors.duration}>
              <ValueAndUnit
                label="Duration"
                value={form.durationValue}
                unit={form.durationUnit}
                units={DURATION_UNITS}
                error={Boolean(fieldErrors.duration)}
                onChange={({ value, unit }) =>
                  set({ durationValue: value, durationUnit: unit })
                }
              />
            </FieldRow>
          }
        />

        {form.type === 'periodic' && (
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
            </div>
          </FieldRow>
        )}

        {valid && (
          <FieldRow label="Window">
            <span aria-label="window-summary" className="text-gray-500">
              {describeMaintenanceWindow(request)}
            </span>
          </FieldRow>
        )}
      </div>

      <div className="flex flex-row w-80 space-x-2">
        <Button disabled={loading || !valid} onClick={() => onSave(request)}>
          {window ? 'Save Changes' : 'Schedule'}
        </Button>
        <Button type="primary-white" onClick={onCancel}>
          Cancel
        </Button>
      </div>
      <div className="text-red-500 mt-2">
        {otherFieldErrors(errors).map(({ detail, source: { pointer } }) => (
          <p key={`${pointer}-${detail}`}>
            {upperFirst(`${pointer.slice(1)}: ${detail}`)}
          </p>
        ))}
        {globalError && <p>{upperFirst(globalError)}</p>}
      </div>
    </Modal>
  );
}

export default MaintenanceWindowModal;
