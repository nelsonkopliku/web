// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { faker } from '@faker-js/faker';
import { Factory } from 'fishery';

// Schedules start at a full hour
const futureDate = () => {
  const date = faker.date.soon({ days: 30 });
  date.setUTCMinutes(0, 0, 0);
  return date.toISOString();
};

export const checksExecutionSettingsFactory = Factory.define(() => ({
  interval: '5m',
  enforced_from_env: false,
}));

export const checksScheduleFactory = Factory.define(() => ({
  interval: null,
  effective_interval: '5m',
  global_interval: '5m',
  last_requested_at: faker.date.recent().toISOString(),
  next_execution_at: futureDate(),
}));

export const recurrenceFactory = Factory.define(() => ({
  frequency: 'weekly',
  interval: 1,
  weekdays: [6],
  ends_on: null,
  max_occurrences: null,
}));

export const policyWarningFactory = Factory.define(() => ({
  message: 'Trento agent is not currently running in the host',
  metadata: [],
}));

export const operationScheduleFactory = Factory.define(({ params }) => {
  const startsAt = params.starts_at ?? futureDate();
  const createdAt = faker.date.recent().toISOString();

  return {
    id: faker.string.uuid(),
    target_type: 'host',
    target_id: faker.string.uuid(),
    operation: 'reboot',
    params: {},
    starts_at: startsAt,
    timezone: 'Etc/UTC',
    recurrence: null,
    next_run_at: startsAt,
    occurrences: 0,
    bulk_id: null,
    created_by: faker.internet.username(),
    inserted_at: createdAt,
    updated_at: createdAt,
  };
});
