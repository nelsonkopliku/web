// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useEffect } from 'react';

import { adminUser, hostFactory } from '@lib/test-utils/factories';
import { MemoryRouter } from 'react-router';
import { faker } from '@faker-js/faker';

import HostsList from './HostsList';

const admin = adminUser.build();
const hosts = hostFactory.buildList(3);

// The selection and the bulk schedule show when operations are enabled in the
// configuration of the deployment
function OperationsEnabled({ children }) {
  // eslint-disable-next-line no-undef
  config.operationsEnabled = true;

  useEffect(
    () => () => {
      // eslint-disable-next-line no-undef
      delete config.operationsEnabled;
    },
    []
  );

  return children;
}

function ContainerWrapper({ children }) {
  return (
    <MemoryRouter>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8">{children}</div>
    </MemoryRouter>
  );
}

export default {
  title: 'Layouts/HostsList',
  components: HostsList,
  render: (args) => (
    <ContainerWrapper>
      <HostsList {...args} />
    </ContainerWrapper>
  ),
};

export const Default = {
  parameters: {
    storeState: {
      user: admin,
      hostsList: { hosts },
    },
  },
};

export const WithStaleHost = {
  parameters: {
    storeState: {
      user: admin,
      hostsList: {
        hosts: hosts.map((host, idx) =>
          idx === 1
            ? {
                ...host,
                stale_at: faker.date.past(),
                heartbeat: 'critical',
              }
            : host
        ),
      },
    },
  },
};

export const WithBulkScheduling = {
  decorators: [
    (Story) => (
      <OperationsEnabled>
        <Story />
      </OperationsEnabled>
    ),
  ],
  parameters: {
    storeState: {
      user: admin,
      hostsList: { hosts },
    },
  },
};
