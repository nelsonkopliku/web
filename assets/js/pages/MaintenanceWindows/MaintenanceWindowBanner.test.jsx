// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { faker } from '@faker-js/faker';

import { renderWithRouter } from '@lib/test-utils';
import { maintenanceWindowFactory } from '@lib/test-utils/factories';

import MaintenanceWindowBanner from './MaintenanceWindowBanner';

describe('MaintenanceWindowBanner', () => {
  it('should tell the active windows, what they forbid, until when and from where', () => {
    const clusterID = faker.string.uuid();

    renderWithRouter(
      <MaintenanceWindowBanner
        timezone="Europe/Berlin"
        windows={[
          maintenanceWindowFactory.build({
            active: true,
            inherited: false,
            forbids: ['checks_execution'],
            current_occurrence: {
              starts_at: '2026-11-20T08:00:00Z',
              ends_at: '2026-11-20T10:00:00Z',
            },
          }),
          maintenanceWindowFactory.build({
            active: true,
            inherited: true,
            target_type: 'cluster',
            target_id: clusterID,
            target_name: 'hana_cluster',
            forbids: ['checks_execution', 'operations'],
            current_occurrence: {
              starts_at: '2026-11-20T08:00:00Z',
              ends_at: '2026-11-20T12:00:00Z',
            },
          }),
          maintenanceWindowFactory.build({ active: false }),
        ]}
      />
    );

    expect(
      screen.getByText(
        'Maintenance window in progress: check execution forbidden until 20 Nov 2026, 11:00:00.'
      )
    ).toBeVisible();
    expect(
      screen.getByText(
        /check execution and operations forbidden until 20 Nov 2026, 13:00:00, from/
      )
    ).toBeVisible();
    expect(screen.getByRole('link', { name: 'hana_cluster' })).toHaveAttribute(
      'href',
      `/clusters/${clusterID}`
    );
  });

  it('should render nothing without active windows', () => {
    const { container } = renderWithRouter(
      <MaintenanceWindowBanner
        windows={[maintenanceWindowFactory.build({ active: false })]}
      />
    );

    expect(container).toBeEmptyDOMElement();
  });
});
