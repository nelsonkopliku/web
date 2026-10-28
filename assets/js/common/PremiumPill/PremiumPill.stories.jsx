// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import PremiumPill from './PremiumPill';

export default {
  title: 'Components/PremiumPill',
  component: PremiumPill,
  argTypes: {
    className: {
      description: 'Additional CSS classes, for example to space it',
      control: { type: 'text' },
    },
  },
};

export const Default = {
  args: {},
};

export const Spaced = {
  args: {
    className: 'ml-3',
  },
};
