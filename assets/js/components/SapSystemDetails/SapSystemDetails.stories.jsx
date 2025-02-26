import React from 'react';
import { MemoryRouter } from 'react-router-dom';

import {
  clusterFactory,
  hostFactory,
  sapSystemApplicationInstanceFactory,
  sapSystemFactory,
} from '@lib/test-utils/factories';
import { APPLICATION_TYPE } from '@lib/model';
import { keysToCamel } from '@lib/serialization';

import { GenericSystemDetails } from './GenericSystemDetails';

const system = {
  ...keysToCamel(
    sapSystemFactory.build({
      instances: sapSystemApplicationInstanceFactory.buildList(2),
    })
  ),
  hosts: hostFactory.buildList(2, { cluster: clusterFactory.build() }),
};

function ContainerWrapper({ children }) {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8">{children}</div>
  );
}

export default {
  title: 'SapSystemDetails',
  components: GenericSystemDetails,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  render: (args) => (
    <ContainerWrapper>
      <GenericSystemDetails {...args} />
    </ContainerWrapper>
  ),
};

export const SapSystem = {
  args: {
    title: 'SAP System Details',
    type: APPLICATION_TYPE,
    system,
  },
};
