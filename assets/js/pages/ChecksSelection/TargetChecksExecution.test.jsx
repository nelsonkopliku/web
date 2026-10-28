// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { checksScheduleFactory } from '@lib/test-utils/factories';

import TargetChecksExecution from './TargetChecksExecution';

const abilities = [{ name: 'all', resource: 'all' }];

describe('TargetChecksExecution', () => {
  it('should show a host following the system setting', () => {
    render(
      <TargetChecksExecution
        targetType="host"
        schedule={checksScheduleFactory.build({
          interval: null,
          effective_interval: '15m',
          global_interval: '15m',
        })}
        userAbilities={abilities}
      />
    );

    expect(screen.getByText('Check Execution')).toBeVisible();
    expect(screen.getByText('Premium')).toBeVisible();
    expect(
      screen.getByText(
        'Configure how often the checks of this host are executed.'
      )
    ).toBeVisible();
    expect(
      screen.getByLabelText('checks-execution-frequency')
    ).toHaveTextContent('Every 15 minutes (system setting)');
  });

  it('should show a cluster frequency overriding the system setting', () => {
    render(
      <TargetChecksExecution
        targetType="cluster"
        schedule={checksScheduleFactory.build({
          interval: '6h',
          effective_interval: '6h',
          global_interval: '15m',
        })}
        userAbilities={abilities}
      />
    );

    expect(
      screen.getByText(
        'Configure how often the checks of this cluster are executed.'
      )
    ).toBeVisible();
    expect(
      screen.getByLabelText('checks-execution-frequency')
    ).toHaveTextContent(
      'Every 6 hours (overrides the system setting: every 15 minutes)'
    );
  });

  it('should show disabled periodic executions of the target', () => {
    render(
      <TargetChecksExecution
        targetType="host"
        schedule={checksScheduleFactory.build({
          interval: 'disabled',
          effective_interval: 'disabled',
          global_interval: '1h',
        })}
        userAbilities={abilities}
      />
    );

    expect(
      screen.getByLabelText('checks-execution-frequency')
    ).toHaveTextContent('Disabled (overrides the system setting: every hour)');
  });

  it('should open the edition with the check frequency ability', async () => {
    const user = userEvent.setup();
    const onEditClick = jest.fn();

    render(
      <TargetChecksExecution
        targetType="host"
        schedule={checksScheduleFactory.build()}
        userAbilities={[{ name: 'all', resource: 'check_frequency' }]}
        onEditClick={onEditClick}
      />
    );

    await user.click(screen.getByRole('button', { name: 'Edit Settings' }));
    expect(onEditClick).toHaveBeenCalled();
  });

  it('should not allow changes without the check frequency ability', () => {
    render(
      <TargetChecksExecution
        targetType="host"
        schedule={checksScheduleFactory.build()}
        userAbilities={[{ name: 'all', resource: 'host_checks_selection' }]}
      />
    );

    expect(
      screen.getByRole('button', { name: 'Edit Settings' })
    ).toBeDisabled();
  });
});
