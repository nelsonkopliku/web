// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import { APPLICATION_TYPE, DATABASE_TYPE } from '@lib/model/sapSystems';
import {
  CLUSTER_MAINTENANCE_CHANGE,
  DATABASE_START,
  HOST_REBOOT,
  SAP_INSTANCE_STOP,
  SAP_SYSTEM_STOP,
  waiveOperationDisclaimer,
} from '@lib/operations';
import { operationScheduleFactory } from '@lib/test-utils/factories';
import {
  initialScheduleSubmission,
  SUBMISSION_FAILED,
  SUBMISSION_SUBMITTING,
} from '@state/operationSchedules';

import EditOperationScheduleModal from './EditOperationScheduleModal';

const timing = {
  starts_at: '2099-11-20T03:00:00Z',
  timezone: 'Etc/UTC',
  recurrence: null,
};

const changedTiming = {
  starts_at: '2099-11-21T04:00:00.000Z',
  timezone: 'Etc/UTC',
  recurrence: null,
};

const changeStart = () => {
  fireEvent.change(screen.getByLabelText('Date'), {
    target: { value: '2099-11-21' },
  });
  fireEvent.change(screen.getByLabelText('Start Time'), {
    target: { value: '04:00' },
  });
};

describe('EditOperationScheduleModal', () => {
  beforeAll(() => waiveOperationDisclaimer());

  it('should change when a host reboot runs', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const schedule = operationScheduleFactory.build({
      operation: HOST_REBOOT,
      params: {},
      ...timing,
    });

    await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          descriptionResolverArgs={{ hostName: 'vmhana01' }}
          onSave={onSave}
        />
      )
    );

    expect(screen.getByText('Reboot host vmhana01')).toBeVisible();

    changeStart();
    await user.click(screen.getByRole('button', { name: 'Save Schedule' }));

    expect(onSave).toHaveBeenCalledWith({ params: {}, ...changedTiming });
  });

  it('should keep the options of a cluster maintenance', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const schedule = operationScheduleFactory.build({
      target_type: 'cluster',
      operation: CLUSTER_MAINTENANCE_CHANGE,
      params: { maintenance: true, resource_id: 'rsc_ip' },
      ...timing,
    });

    await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          onSave={onSave}
        />
      )
    );

    expect(screen.getByText(/on resource rsc_ip/)).toBeVisible();

    changeStart();
    await user.click(screen.getByRole('button', { name: 'Save Schedule' }));

    expect(onSave).toHaveBeenCalledWith({
      params: { maintenance: true, resource_id: 'rsc_ip' },
      ...changedTiming,
    });
  });

  it('should keep the instance of a SAP instance operation', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const schedule = operationScheduleFactory.build({
      target_type: 'sap_system',
      operation: SAP_INSTANCE_STOP,
      params: { host_id: 'host-id', instance_number: '01' },
      ...timing,
    });

    await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          sid="HA1"
          onSave={onSave}
        />
      )
    );

    expect(
      screen.getByText('Stop SAP instance with instance number 01 in HA1')
    ).toBeVisible();

    await user.click(screen.getByRole('button', { name: 'Save Schedule' }));

    expect(onSave).toHaveBeenCalledWith({
      params: { host_id: 'host-id', instance_number: '01' },
      starts_at: '2099-11-20T03:00:00.000Z',
      timezone: 'Etc/UTC',
      recurrence: null,
    });
  });

  it('should change the options of a SAP system stop', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const schedule = operationScheduleFactory.build({
      target_type: 'sap_system',
      operation: SAP_SYSTEM_STOP,
      params: { instance_type: 'abap', timeout: 300 },
      ...timing,
    });

    await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          sid="HA1"
          type={APPLICATION_TYPE}
          onSave={onSave}
        />
      )
    );

    await user.click(screen.getByText('ABAP instances'));
    await user.click(screen.getByRole('option', { name: 'J2EE instances' }));
    await user.click(screen.getByRole('button', { name: 'Save Schedule' }));

    expect(onSave).toHaveBeenCalledWith({
      params: { instance_type: 'j2ee', timeout: 300 },
      starts_at: '2099-11-20T03:00:00.000Z',
      timezone: 'Etc/UTC',
      recurrence: null,
    });
  });

  it('should keep the site of a database start', async () => {
    const user = userEvent.setup();
    const onSave = jest.fn();
    const schedule = operationScheduleFactory.build({
      target_type: 'database',
      operation: DATABASE_START,
      params: { site: 'NBG', timeout: 600 },
      ...timing,
    });

    await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          sid="PRD"
          type={DATABASE_TYPE}
          onSave={onSave}
        />
      )
    );

    expect(screen.getByText('Start database PRD on NBG site')).toBeVisible();

    await user.click(screen.getByRole('button', { name: 'Save Schedule' }));

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({ params: { site: 'NBG', timeout: 600 } })
    );
  });

  it('should cancel the schedule after a confirmation', async () => {
    const user = userEvent.setup();
    const onCancelSchedule = jest.fn();
    const schedule = operationScheduleFactory.build({
      operation: HOST_REBOOT,
      ...timing,
    });

    await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          onCancelSchedule={onCancelSchedule}
        />
      )
    );

    await user.click(screen.getByRole('button', { name: 'Cancel Schedule' }));
    await user.click(
      screen.getByRole('button', { name: 'Yes, Cancel Schedule' })
    );

    expect(onCancelSchedule).toHaveBeenCalled();
  });

  it('should follow the submission of the change', async () => {
    const schedule = operationScheduleFactory.build({
      operation: HOST_REBOOT,
      ...timing,
    });

    const { rerender } = await act(() =>
      render(
        <EditOperationScheduleModal
          isOpen
          schedule={schedule}
          submission={{
            ...initialScheduleSubmission,
            status: SUBMISSION_SUBMITTING,
          }}
        />
      )
    );

    expect(
      screen.getByRole('button', { name: 'Save Schedule' })
    ).toBeDisabled();

    rerender(
      <EditOperationScheduleModal
        isOpen
        schedule={schedule}
        submission={{
          ...initialScheduleSubmission,
          status: SUBMISSION_FAILED,
          errors: [{ title: 'Not Found', detail: 'The schedule is gone.' }],
        }}
      />
    );

    expect(screen.getByText('The schedule is gone.')).toBeVisible();
  });

  it('should render nothing without a schedule', async () => {
    const { container } = await act(() =>
      render(<EditOperationScheduleModal isOpen={false} schedule={null} />)
    );

    expect(container).toBeEmptyDOMElement();
  });
});
