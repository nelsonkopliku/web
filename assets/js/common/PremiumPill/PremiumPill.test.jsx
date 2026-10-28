// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';

import PremiumPill from './PremiumPill';

describe('PremiumPill', () => {
  it('should mark a premium feature', () => {
    render(<PremiumPill />);

    expect(screen.getByText('Premium')).toBeVisible();
  });

  it('should add the given classes to its own', () => {
    render(<PremiumPill className="ml-3" />);

    expect(screen.getByText('Premium')).toHaveClass(
      'bg-jungle-green-500',
      'ml-3'
    );
  });
});
