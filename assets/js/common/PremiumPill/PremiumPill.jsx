// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import classNames from 'classnames';

import Pill from '@common/Pill';

/**
 * Marks a feature that may become premium. It does not restrict anything.
 */
function PremiumPill({ className }) {
  return (
    <Pill
      size="xs"
      className={classNames('bg-jungle-green-500 text-white', className)}
    >
      Premium
    </Pill>
  );
}

export default PremiumPill;
