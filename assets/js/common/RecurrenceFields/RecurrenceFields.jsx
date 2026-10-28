// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { noop, upperFirst } from 'lodash';

import Input, { InputNumber } from '@common/Input';
import Label from '@common/Label';
import Select from '@common/Select';
import { REPEAT_UNITS, WEEKDAYS } from '@lib/model/recurrence';

export const optionOf = (options, value) =>
  options.find((option) => option.value === value);

export function FieldError({ text }) {
  return text ? (
    <p className="text-red-500 text-sm mt-1">{upperFirst(text)}</p>
  ) : null;
}

// Label and field of a form laid out in a six columns grid
export function FieldRow({ label, error, children }) {
  return (
    <>
      <Label className="col-span-2">{label}</Label>
      <div className="col-span-4">
        {children}
        <FieldError text={error} />
      </div>
    </>
  );
}

export function ValueAndUnit({
  label,
  value,
  unit,
  units,
  error = false,
  onChange = noop,
}) {
  return (
    <div className="flex items-center space-x-4">
      <div className="w-32">
        <InputNumber
          aria-label={label}
          className="!h-9"
          min="1"
          value={value}
          error={error}
          onChange={(newValue) =>
            onChange({ value: String(newValue ?? ''), unit })
          }
        />
      </div>
      <div className="w-40">
        <Select
          aria-label={`${label} unit`}
          options={units}
          value={optionOf(units, unit)}
          onChange={(newUnit) => onChange({ value, unit: newUnit })}
        />
      </div>
    </div>
  );
}

/**
 * Rows of a one-time or periodic schedule, to be placed in a six columns
 * grid: date and start time, then repeat every and days of the week when
 * periodic. `afterTime` is rendered right after the start time. `errors`
 * holds the messages of the start, repeat and weekdays fields.
 */
function RecurrenceFields({
  form,
  periodic = false,
  afterTime = null,
  errors = {},
  onChange = noop,
}) {
  return (
    <>
      <FieldRow label="Date">
        <Input
          type="date"
          aria-label="Date"
          value={form.date}
          error={Boolean(errors.start)}
          onChange={({ target: { value } }) => onChange({ date: value })}
        />
      </FieldRow>
      <FieldRow label="Start Time" error={errors.start}>
        <Input
          type="time"
          aria-label="Start Time"
          value={form.time}
          error={Boolean(errors.start)}
          onChange={({ target: { value } }) => onChange({ time: value })}
        />
      </FieldRow>

      {afterTime}

      {periodic && (
        <FieldRow label="Repeat every" error={errors.repeat}>
          <ValueAndUnit
            label="Repeat every"
            value={form.repeatValue}
            unit={form.repeatUnit}
            units={REPEAT_UNITS}
            error={Boolean(errors.repeat)}
            onChange={({ value, unit }) =>
              onChange({ repeatValue: value, repeatUnit: unit })
            }
          />
        </FieldRow>
      )}

      {periodic && form.repeatUnit === 'weeks' && (
        <FieldRow label="Days" error={errors.weekdays}>
          <Select
            aria-label="Days of the week"
            isMulti
            closeMenuOnSelect={false}
            placeholder="Day of the start"
            options={WEEKDAYS}
            initialValues={WEEKDAYS.filter(({ value }) =>
              form.weekdays.includes(value)
            )}
            getOptionValue={(option) => option.value.toString()}
            onChange={(weekdays) =>
              onChange({ weekdays: [...weekdays].sort((a, b) => a - b) })
            }
          />
        </FieldRow>
      )}
    </>
  );
}

export default RecurrenceFields;
