// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import userEvent from '@testing-library/user-event';
import { faker } from '@faker-js/faker';
import {
  resetOperationDisclaimer,
  waiveOperationDisclaimer,
} from '@lib/operations';
import { operationScheduleFactory } from '@lib/test-utils/factories';
import OperationModal from './OperationModal';

const setDateAndTime = (date, time) => {
  fireEvent.change(screen.getByLabelText('Date'), { target: { value: date } });
  fireEvent.change(screen.getByLabelText('Start Time'), {
    target: { value: time },
  });
};

const chooseScheduleType = async (user, type) => {
  await user.click(screen.getByText('Now'));
  await user.click(screen.getByRole('option', { name: type }));
};

describe('OperationModal', () => {
  beforeEach(() => resetOperationDisclaimer());

  it('should show disclaimer', async () => {
    const operationTitle = faker.lorem.sentence();
    const operationDescription = faker.lorem.paragraph();
    const operationText = faker.lorem.word();
    await act(() =>
      render(
        <OperationModal
          title={operationTitle}
          description={operationDescription}
          operationText={operationText}
          isOpen
        />
      )
    );

    const pattern = `By proceeding I confirm to be aware of the impact that executing operation "${operationText}" will have in my environment`;

    expect(screen.getByText('Disclaimer')).toBeInTheDocument();
    expect(screen.getByText(new RegExp(pattern))).toBeInTheDocument();
    expect(screen.getByText("Don't show this again")).toBeInTheDocument();
    expect(screen.getByRole('checkbox')).not.toBeChecked();
    expect(screen.getByText('Proceed')).toBeEnabled();
    expect(screen.getByText('Cancel')).toBeEnabled();

    expect(screen.queryByText(operationTitle)).not.toBeInTheDocument();
    expect(screen.queryByText(operationDescription)).not.toBeInTheDocument();
  });

  it('should allow requesting operation after disclaimer step', async () => {
    const user = userEvent.setup();

    const operationTitle = faker.lorem.sentence();
    const operationDescription = faker.lorem.paragraph();
    const operationText = faker.lorem.word();
    const specificOperationModalContent = faker.person.fullName();
    const mockOnRequest = jest.fn();

    await act(() =>
      render(
        <OperationModal
          title={operationTitle}
          description={operationDescription}
          operationText={operationText}
          isOpen
          onRequest={mockOnRequest}
        >
          {specificOperationModalContent}
        </OperationModal>
      )
    );

    await user.click(screen.getByText('Proceed'));
    expect(mockOnRequest).not.toHaveBeenCalled();

    const pattern = `By proceeding I confirm to be aware of the impact that executing operation "${operationText}" will have in my environment`;

    expect(screen.queryByText('Disclaimer')).not.toBeInTheDocument();
    expect(screen.queryByText(new RegExp(pattern))).not.toBeInTheDocument();
    expect(screen.queryByText("Don't show this again")).not.toBeInTheDocument();
    expect(screen.queryByText('Proceed')).not.toBeInTheDocument();
    expect(screen.getByText('Cancel')).toBeEnabled();

    expect(screen.getByText(operationTitle)).toBeInTheDocument();
    expect(screen.getByText(operationDescription)).toBeInTheDocument();
    expect(screen.getByText(specificOperationModalContent)).toBeInTheDocument();

    expect(screen.getByText('Request')).toBeEnabled();
    await user.click(screen.getByText('Request'));

    expect(mockOnRequest).toHaveBeenCalled();
  });

  it(`should not waive disclaimer by just clicking the "Don't show this again" checkbox`, async () => {
    const user = userEvent.setup();

    const { rerender } = await act(() => render(<OperationModal isOpen />));

    await user.click(screen.getByRole('checkbox'));
    expect(screen.getByRole('checkbox')).toBeChecked();

    rerender(<OperationModal isOpen />);

    expect(screen.getByText('Disclaimer')).toBeInTheDocument();
  });

  it(`should waive disclaimer by clicking the "Don't show this again" checkbox and proceeding to operation`, async () => {
    const user = userEvent.setup();

    const operationTitle = faker.lorem.sentence();
    const operationDescription = faker.lorem.paragraph();
    const operationText = faker.lorem.word();
    const specificOperationModalContent = faker.person.fullName();

    const { rerender } = await act(() =>
      render(
        <OperationModal
          title={operationTitle}
          description={operationDescription}
          operationText={operationText}
          isOpen
        >
          {specificOperationModalContent}
        </OperationModal>
      )
    );

    await user.click(screen.getByRole('checkbox'));
    expect(screen.getByRole('checkbox')).toBeChecked();
    await user.click(screen.getByText('Proceed'));

    rerender(
      <OperationModal
        title={operationTitle}
        description={operationDescription}
        operationText={operationText}
        isOpen
      >
        {specificOperationModalContent}
      </OperationModal>
    );

    expect(screen.queryByText('Disclaimer')).not.toBeInTheDocument();
    expect(screen.getByText(operationTitle)).toBeInTheDocument();
    expect(screen.getByText(operationDescription)).toBeInTheDocument();
    expect(screen.getByText(specificOperationModalContent)).toBeInTheDocument();
  });

  it('should be possible to disable requesting operation after disclaimer step', async () => {
    const user = userEvent.setup();

    await act(() => render(<OperationModal isOpen requestDisabled />));

    await user.click(screen.getByText('Proceed'));

    expect(screen.getByText('Request')).toBeDisabled();
  });
  describe('scheduling', () => {
    beforeEach(() => waiveOperationDisclaimer());

    it('should request the operation now by default', async () => {
      const user = userEvent.setup();
      const onRequest = jest.fn();

      render(
        <OperationModal
          title="Reboot"
          operationText="Reboot host"
          isOpen
          schedulable
          onRequest={onRequest}
        />
      );

      expect(screen.getByText('Schedule')).toBeVisible();
      expect(screen.getByText('Premium')).toBeVisible();

      await user.click(screen.getByRole('button', { name: 'Request' }));
      expect(onRequest).toHaveBeenCalledWith(null);
    });

    it('should not offer scheduling when the operation is not schedulable', async () => {
      await act(() => render(<OperationModal title="Apply" isOpen />));

      expect(screen.queryByLabelText('Schedule type')).not.toBeInTheDocument();
      expect(screen.queryByText('Premium')).not.toBeInTheDocument();
    });

    it('should schedule a one-time operation in the user timezone', async () => {
      const user = userEvent.setup();
      const onRequest = jest.fn();

      render(
        <OperationModal
          title="Reboot"
          isOpen
          schedulable
          timezone="Europe/Berlin"
          onRequest={onRequest}
        />
      );

      await chooseScheduleType(user, 'One Time');
      setDateAndTime('2099-11-20', '03:00');

      expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();
      expect(screen.getByLabelText('schedule-summary')).toHaveTextContent(
        '20 Nov 2099 at 03:00'
      );

      await user.click(screen.getByRole('button', { name: 'Schedule' }));

      expect(onRequest).toHaveBeenCalledWith({
        starts_at: '2099-11-20T02:00:00.000Z',
        timezone: 'Europe/Berlin',
        recurrence: null,
      });
    });

    it('should schedule a periodic operation with its end', async () => {
      const user = userEvent.setup();
      const onRequest = jest.fn();

      render(
        <OperationModal
          title="Reboot"
          isOpen
          schedulable
          timezone="Etc/UTC"
          onRequest={onRequest}
        />
      );

      await chooseScheduleType(user, 'Periodic');
      setDateAndTime('2099-11-20', '03:00');

      await user.click(screen.getByText('Days'));
      await user.click(screen.getByRole('option', { name: 'Weeks' }));
      await user.click(screen.getByText('Day of the start'));
      await user.click(screen.getByRole('option', { name: 'Saturday' }));

      await user.click(screen.getByText('Never'));
      await user.click(screen.getByRole('option', { name: 'After' }));
      await user.clear(screen.getByLabelText('Occurrences'));
      await user.type(screen.getByLabelText('Occurrences'), '5');

      await user.click(screen.getByRole('button', { name: 'Schedule' }));

      expect(onRequest).toHaveBeenCalledWith({
        starts_at: '2099-11-20T03:00:00.000Z',
        timezone: 'Etc/UTC',
        recurrence: {
          frequency: 'weekly',
          interval: 1,
          weekdays: [6],
          ends_on: null,
          max_occurrences: 5,
        },
      });
    });

    it('should not schedule an operation in the past', async () => {
      const user = userEvent.setup();
      const onRequest = jest.fn();

      render(
        <OperationModal
          title="Reboot"
          isOpen
          schedulable
          timezone="Etc/UTC"
          onRequest={onRequest}
        />
      );

      await chooseScheduleType(user, 'One Time');
      setDateAndTime('2020-11-20', '03:00');

      expect(
        screen.getByText('Pick a date and time in the future')
      ).toBeVisible();
      expect(screen.getByRole('button', { name: 'Schedule' })).toBeDisabled();
    });

    it('should not request twice while a request is ongoing', async () => {
      await act(() =>
        render(<OperationModal title="Reboot" isOpen schedulable loading />)
      );

      expect(screen.getByRole('button', { name: 'Request' })).toBeDisabled();
    });

    it('should show the errors of a refused schedule', async () => {
      const user = userEvent.setup();

      render(
        <OperationModal
          title="Reboot"
          isOpen
          schedulable
          timezone="Etc/UTC"
          errors={[
            {
              title: 'Invalid value',
              detail: 'must be in the future',
              source: { pointer: '/starts_at' },
            },
            {
              title: 'Invalid value',
              detail: 'must be greater than or equal to 1',
              source: { pointer: '/params/timeout' },
            },
            { title: 'Forbidden', detail: 'You can not perform this action.' },
          ]}
        />
      );

      await chooseScheduleType(user, 'One Time');

      expect(screen.getByText('Must be in the future')).toBeVisible();
      expect(
        screen.getByText('Params/timeout: must be greater than or equal to 1')
      ).toBeVisible();
      expect(
        screen.getByText('You can not perform this action.')
      ).toBeVisible();
    });

    describe('an existing schedule', () => {
      const schedule = operationScheduleFactory.build({
        starts_at: '2099-11-20T02:00:00Z',
        timezone: 'Europe/Berlin',
        recurrence: { frequency: 'daily', interval: 2, ends_on: '2100-01-01' },
      });

      it('should change it in its own timezone', async () => {
        const user = userEvent.setup();
        const onRequest = jest.fn();

        render(
          <OperationModal
            title="Reboot"
            isOpen
            schedulable
            timezone="Etc/UTC"
            initialSchedule={schedule}
            onRequest={onRequest}
          />
        );

        expect(screen.queryByText('Now')).not.toBeInTheDocument();
        expect(screen.getByText('Times are in Europe/Berlin.')).toBeVisible();
        expect(screen.getByLabelText('Date')).toHaveValue('2099-11-20');
        expect(screen.getByLabelText('Start Time')).toHaveValue('03:00');
        expect(screen.getByLabelText('Repeat every')).toHaveValue('2');
        expect(screen.getByLabelText('End date')).toHaveValue('2100-01-01');

        setDateAndTime('2099-11-21', '04:00');
        await user.click(screen.getByRole('button', { name: 'Save Schedule' }));

        expect(onRequest).toHaveBeenCalledWith({
          starts_at: '2099-11-21T03:00:00.000Z',
          timezone: 'Europe/Berlin',
          recurrence: {
            frequency: 'daily',
            interval: 2,
            weekdays: [],
            ends_on: '2100-01-01',
            max_occurrences: null,
          },
        });
      });

      it('should keep the past start of an ongoing periodic schedule', async () => {
        await act(() =>
          render(
            <OperationModal
              title="Reboot"
              isOpen
              schedulable
              initialSchedule={{
                ...schedule,
                starts_at: '2020-11-20T02:00:00Z',
                recurrence: { frequency: 'daily', interval: 1 },
              }}
            />
          )
        );

        expect(
          screen.getByRole('button', { name: 'Save Schedule' })
        ).toBeEnabled();
      });

      it('should cancel it after a confirmation', async () => {
        const user = userEvent.setup();
        const onCancelSchedule = jest.fn();

        render(
          <OperationModal
            title="Reboot"
            operationText="Reboot host"
            isOpen
            schedulable
            initialSchedule={schedule}
            onCancelSchedule={onCancelSchedule}
          />
        );

        await user.click(
          screen.getByRole('button', { name: 'Cancel Schedule' })
        );
        expect(onCancelSchedule).not.toHaveBeenCalled();
        expect(
          screen.getByText(
            'Cancel this schedule of Reboot host? The operation will not be requested anymore.'
          )
        ).toBeVisible();

        await user.click(screen.getByRole('button', { name: 'Keep Schedule' }));
        expect(screen.getByLabelText('Date')).toBeVisible();

        await user.click(
          screen.getByRole('button', { name: 'Cancel Schedule' })
        );
        await user.click(
          screen.getByRole('button', { name: 'Yes, Cancel Schedule' })
        );
        expect(onCancelSchedule).toHaveBeenCalled();
      });
    });

    describe('already scheduled', () => {
      const existingSchedules = [
        operationScheduleFactory.build({
          starts_at: '2099-11-20T03:00:00Z',
          timezone: 'Etc/UTC',
          recurrence: null,
        }),
      ];

      it('should warn before scheduling the operation again', async () => {
        const user = userEvent.setup();
        const onRequest = jest.fn();

        render(
          <OperationModal
            title="Reboot"
            operationText="Reboot host"
            isOpen
            schedulable
            timezone="Etc/UTC"
            existingSchedules={existingSchedules}
            onRequest={onRequest}
          />
        );

        await chooseScheduleType(user, 'One Time');
        setDateAndTime('2099-12-20', '03:00');
        await user.click(screen.getByRole('button', { name: 'Schedule' }));

        expect(onRequest).not.toHaveBeenCalled();
        expect(
          screen.getByText('Reboot host is already scheduled for this target:')
        ).toBeVisible();
        expect(
          screen.getByText('20 Nov 2099 at 03:00 (Etc/UTC)')
        ).toBeVisible();

        await user.click(screen.getByRole('button', { name: 'Continue' }));

        expect(onRequest).toHaveBeenCalledWith({
          starts_at: '2099-12-20T03:00:00.000Z',
          timezone: 'Etc/UTC',
          recurrence: null,
        });
      });

      it('should not schedule the operation again when cancelled', async () => {
        const user = userEvent.setup();
        const onRequest = jest.fn();
        const onCancel = jest.fn();

        render(
          <OperationModal
            title="Reboot"
            operationText="Reboot host"
            isOpen
            schedulable
            existingSchedules={existingSchedules}
            onRequest={onRequest}
            onCancel={onCancel}
          />
        );

        await chooseScheduleType(user, 'One Time');
        setDateAndTime('2099-12-20', '03:00');
        await user.click(screen.getByRole('button', { name: 'Schedule' }));
        await user.click(screen.getByRole('button', { name: 'Cancel' }));

        expect(onRequest).not.toHaveBeenCalled();
        expect(onCancel).toHaveBeenCalled();
      });

      it('should request the operation now without warning', async () => {
        const user = userEvent.setup();
        const onRequest = jest.fn();

        render(
          <OperationModal
            title="Reboot"
            isOpen
            schedulable
            existingSchedules={existingSchedules}
            onRequest={onRequest}
          />
        );

        await user.click(screen.getByRole('button', { name: 'Request' }));

        expect(onRequest).toHaveBeenCalledWith(null);
      });
    });
  });
});
