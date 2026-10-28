// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

// One-time and periodic schedules. A schedule has starts_at, timezone and a
// recurrence, null for a one-time schedule. Occurrences keep their local time
// in the timezone of the schedule. See Trento.Scheduling.Recurrence for the
// rules.

import { TZDate, tz } from '@date-fns/tz';
import {
  addDays,
  addHours,
  addMinutes,
  addMonths,
  addWeeks,
  addYears,
  format,
  getISODay,
  isAfter,
  parse,
  parseISO,
  set,
  startOfHour,
  startOfISOWeek,
} from 'date-fns';

import { parseDateTimeLocalToUtc } from '@lib/timezones';

const WEEKDAY_NAMES = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

export const WEEKDAYS = WEEKDAY_NAMES.map((label, index) => ({
  value: index + 1,
  label,
}));

export const REPEAT_UNITS = [
  { value: 'days', label: 'Days', frequency: 'daily' },
  { value: 'weeks', label: 'Weeks', frequency: 'weekly' },
  { value: 'months', label: 'Months', frequency: 'monthly' },
  { value: 'years', label: 'Years', frequency: 'yearly' },
];

const PERIODS = {
  daily: 'day',
  weekly: 'week',
  monthly: 'month',
  yearly: 'year',
};

const inTimezone = (date, formatStr, timezone) =>
  format(date, formatStr, { in: tz(timezone) });

// ends_on is a date without time: it is shown as it is, in no timezone
const formatPlainDate = (date) =>
  format(parse(date, 'yyyy-MM-dd', new Date()), 'dd MMM yyyy');

const endsSuffix = ({ ends_on: endsOn, max_occurrences: maxOccurrences }) => {
  if (endsOn) return `, until ${formatPlainDate(endsOn)} (excluded)`;
  if (maxOccurrences) return `, ${maxOccurrences} times`;
  return '';
};

/**
 * Human readable summary of a schedule, in the given timezone, for example
 * "Every 2 weeks on Saturdays, Sundays at 03:00, 5 times". With a duration in
 * minutes, each occurrence is shown as a time range.
 */
export const describeOccurrences = (schedule, timezone, { duration } = {}) => {
  const { starts_at: startsAt, recurrence } = schedule;

  const start = parseISO(startsAt);
  const startTime = inTimezone(start, 'HH:mm', timezone);
  const at = duration
    ? `, ${startTime} – ${inTimezone(addMinutes(start, duration), 'HH:mm', timezone)}`
    : ` at ${startTime}`;

  if (!recurrence) {
    return `${inTimezone(start, 'dd MMM yyyy', timezone)}${at}`;
  }

  const { frequency, interval = 1, weekdays = [] } = recurrence;
  const ends = endsSuffix(recurrence);
  const period = PERIODS[frequency];
  const every =
    interval === 1 ? `Every ${period}` : `Every ${interval} ${period}s`;

  switch (frequency) {
    case 'weekly': {
      const days = (
        weekdays.length > 0
          ? weekdays
          : [Number(inTimezone(start, 'i', timezone))]
      )
        .map((day) => `${WEEKDAY_NAMES[day - 1]}s`)
        .join(', ');
      return interval === 1
        ? `${days}${at}${ends}`
        : `${every} on ${days}${at}${ends}`;
    }
    case 'monthly':
      return `${every} on day ${inTimezone(start, 'd', timezone)}${at}${ends}`;
    case 'yearly':
      return `${every} on ${inTimezone(start, 'd MMM', timezone)}${at}${ends}`;
    default:
      return `${every}${at}${ends}`;
  }
};

// Date and time of the next full hour, as edited in the forms
export const nextFullHourIn = (timezone, now = new Date()) => {
  const nextHour = addHours(startOfHour(now, { in: tz(timezone) }), 1);

  return {
    date: inTimezone(nextHour, 'yyyy-MM-dd', timezone),
    time: inTimezone(nextHour, 'HH:mm', timezone),
  };
};

const toStartDate = ({ date, time }, timezone) =>
  parseDateTimeLocalToUtc(`${date}T${time}`, timezone);

// A schedule has to start in the future: now is already too late
export const startsInThePast = (form, timezone, now = new Date()) =>
  !isAfter(toStartDate(form, timezone), now);

// Start and repetition of a schedule, as edited in the forms
export const recurrenceToForm = (
  { starts_at: startsAt, recurrence },
  timezone
) => {
  const start = parseISO(startsAt);

  return {
    date: inTimezone(start, 'yyyy-MM-dd', timezone),
    time: inTimezone(start, 'HH:mm', timezone),
    repeatValue: String(recurrence?.interval || 1),
    repeatUnit:
      REPEAT_UNITS.find(({ frequency }) => frequency === recurrence?.frequency)
        ?.value || 'days',
    weekdays: recurrence?.weekdays || [],
  };
};

export const formToRecurrence = (form, timezone, periodic) => {
  const starts = {
    starts_at: toStartDate(form, timezone).toISOString(),
    timezone,
  };

  if (!periodic) return { ...starts, recurrence: null };

  const { frequency } = REPEAT_UNITS.find(
    ({ value }) => value === form.repeatUnit
  );

  return {
    ...starts,
    recurrence: {
      frequency,
      interval: Number(form.repeatValue),
      weekdays: frequency === 'weekly' ? form.weekdays : [],
    },
  };
};

// Occurrences are computed from the start, so that the shorter months move a
// monthly occurrence to their last day without moving the next ones
const STEPS = {
  daily: addDays,
  monthly: addMonths,
  yearly: addYears,
};

// Enough for a daily schedule started more than two centuries ago
const MAX_STEPS = 100000;

const weeklyStarts = (start, weeks, weekdays) => {
  const week = startOfISOWeek(addWeeks(start, weeks));
  const days = weekdays.length > 0 ? weekdays : [getISODay(start)];

  return days.map((day) =>
    set(addDays(week, day - 1), {
      hours: start.getHours(),
      minutes: start.getMinutes(),
    })
  );
};

function* occurrenceStarts({ starts_at: startsAt, timezone, recurrence }) {
  const start = new TZDate(parseISO(startsAt), timezone);

  if (!recurrence) {
    yield start;
    return;
  }

  const {
    frequency,
    interval = 1,
    weekdays = [],
    ends_on: endsOn,
    max_occurrences: maxOccurrences,
  } = recurrence;
  let count = 0;

  for (let step = 0; step < MAX_STEPS; step += 1) {
    const starts =
      frequency === 'weekly'
        ? weeklyStarts(start, step * interval, weekdays)
        : [STEPS[frequency](start, step * interval)];

    for (const occurrence of starts.filter((date) => date >= start)) {
      if (endsOn && format(occurrence, 'yyyy-MM-dd') >= endsOn) return;
      if (maxOccurrences && count >= maxOccurrences) return;

      count += 1;
      yield occurrence;
    }
  }
}

/**
 * The occurrence of a schedule lasting some minutes that is active at the
 * given time, or the next one: { startsAt, endsAt }, or null when there is
 * none. Occurrences keep their local time in the timezone of the schedule.
 */
export const occurrenceAround = (schedule, durationMinutes, now) => {
  for (const startsAt of occurrenceStarts(schedule)) {
    const endsAt = addMinutes(startsAt, durationMinutes);

    if (endsAt > now) {
      return {
        startsAt: new Date(startsAt.getTime()),
        endsAt: new Date(endsAt.getTime()),
      };
    }
  }

  return null;
};
