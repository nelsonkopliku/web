// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { Provider } from 'react-redux';
import { configureStore, createSlice } from '@reduxjs/toolkit';
import MockAdapter from 'axios-mock-adapter';
import { faker } from '@faker-js/faker';

import { networkClient } from '@lib/network';
import {
  abilityFactory,
  checksScheduleFactory,
} from '@lib/test-utils/factories';

import TargetChecksExecutionSection from './TargetChecksExecutionSection';

const hostID = faker.string.uuid();

const lastExecutionsSlice = createSlice({
  name: 'lastExecutions',
  initialState: {},
  reducers: {},
});

export default {
  title: 'Components/TargetChecksExecutionSection',
  component: TargetChecksExecutionSection,
  decorators: [
    (Story) => {
      const axiosMock = new MockAdapter(networkClient, {
        delayResponse: 500,
      });
      axiosMock.onGet(`/hosts/${hostID}/checks/schedule`).reply(
        200,
        checksScheduleFactory.build({
          interval: null,
          effective_interval: '15m',
          global_interval: '15m',
        })
      );
      axiosMock.onPut(`/hosts/${hostID}/checks/schedule`).reply(({ data }) => {
        const { interval, exception_window: exceptionWindow } =
          JSON.parse(data);
        return [
          200,
          checksScheduleFactory.build({
            interval,
            effective_interval: interval ?? '15m',
            global_interval: '15m',
            exception_window: exceptionWindow,
          }),
        ];
      });

      const store = configureStore({
        reducer: { lastExecutions: lastExecutionsSlice.reducer },
      });

      return (
        <Provider store={store}>
          <Story />
        </Provider>
      );
    },
  ],
  argTypes: {
    targetType: {
      description: 'Type of the target',
      control: { type: 'radio' },
      options: ['host', 'cluster'],
    },
    targetID: {
      description: 'Identifier of the target',
      control: { type: 'text' },
    },
    timezone: {
      description: 'Timezone of the user, for a new exception window',
      control: { type: 'text' },
    },
    userAbilities: {
      description: 'Abilities of the user, editing needs all:check_frequency',
      control: { type: 'object' },
    },
  },
};

export const Default = {
  args: {
    targetType: 'host',
    targetID: hostID,
    timezone: 'Europe/Berlin',
    userAbilities: [abilityFactory.build({ name: 'all', resource: 'all' })],
  },
};
