// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

// Checks execution intervals of the scheduling contract: a value and a unit
// suffix, like 15m, 6h or 2w, or disabled.

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
