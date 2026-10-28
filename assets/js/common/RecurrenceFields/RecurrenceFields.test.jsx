// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';

import RecurrenceFields from './RecurrenceFields';

const form = {
  date: '2026-11-20',
  time: '03:00',
  repeatValue: '1',
  repeatUnit: 'days',
  weekdays: [],
};

const renderInGrid = (ui) =>
  render(<div className="grid grid-cols-6">{ui}</div>);

describe('RecurrenceFields', () => {
  it('should edit the date and the start time', () => {
    const onChange = jest.fn();

    renderInGrid(<RecurrenceFields form={form} onChange={onChange} />);

    expect(screen.getByLabelText('Date')).toHaveValue('2026-11-20');
    expect(screen.getByLabelText('Start Time')).toHaveValue('03:00');
    expect(screen.queryByLabelText('Repeat every')).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('Date'), {
      target: { value: '2026-11-21' },
    });
    expect(onChange).toHaveBeenLastCalledWith({ date: '2026-11-21' });

    fireEvent.change(screen.getByLabelText('Start Time'), {
      target: { value: '04:30' },
    });
    expect(onChange).toHaveBeenLastCalledWith({ time: '04:30' });
  });

  it('should edit how a periodic schedule repeats', async () => {
    const user = userEvent.setup();
    const onChange = jest.fn();

    renderInGrid(<RecurrenceFields form={form} periodic onChange={onChange} />);

    expect(screen.getByLabelText('Repeat every')).toHaveValue('1');
    expect(screen.queryByLabelText('Days of the week')).not.toBeInTheDocument();

    await user.click(screen.getByText('Days'));
    await user.click(screen.getByRole('option', { name: 'Weeks' }));

    expect(onChange).toHaveBeenLastCalledWith({
      repeatValue: '1',
      repeatUnit: 'weeks',
    });
  });

  it('should choose the days of a weekly schedule', async () => {
    const user = userEvent.setup();
    const onChange = jest.fn();

    renderInGrid(
      <RecurrenceFields
        form={{ ...form, repeatUnit: 'weeks', weekdays: [5] }}
        periodic
        onChange={onChange}
      />
    );

    expect(screen.getByText('Friday')).toBeVisible();

    await user.click(screen.getByText('Friday'));
    await user.click(screen.getByRole('option', { name: 'Monday' }));

    expect(onChange).toHaveBeenLastCalledWith({ weekdays: [1, 5] });
  });

  it('should render the field after the start time and the errors of the fields', () => {
    renderInGrid(
      <RecurrenceFields
        form={form}
        periodic
        afterTime={<div>Duration field</div>}
        errors={{
          start: 'Pick a date and time in the future',
          repeat: 'Must be greater than or equal to 1',
        }}
      />
    );

    expect(screen.getByText('Duration field')).toBeVisible();
    expect(
      screen.getByText('Pick a date and time in the future')
    ).toBeVisible();
    expect(
      screen.getByText('Must be greater than or equal to 1')
    ).toBeVisible();
  });
});
