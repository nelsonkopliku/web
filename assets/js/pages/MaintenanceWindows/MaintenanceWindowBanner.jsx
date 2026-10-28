// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { isEmpty, lowerFirst } from 'lodash';

import Banner from '@common/Banners';
import { activeWindows, describeForbids } from '@lib/model/maintenanceWindows';
import { DEFAULT_TIMEZONE, formatDateTime } from '@lib/timezones';

import OwnerLink from './ownerLink';

/**
 * Tells the maintenance windows in progress on a target: what they forbid,
 * until when, and the target they come from when inherited
 */
function MaintenanceWindowBanner({
  windows = [],
  timezone = DEFAULT_TIMEZONE,
}) {
  const active = activeWindows(windows);

  if (isEmpty(active)) return null;

  return (
    <div className="mb-4">
      {active.map((window) => (
        <Banner key={window.id} type="warning" truncate={false}>
          <span>
            Maintenance window in progress:{' '}
            {lowerFirst(describeForbids(window.forbids))} forbidden until{' '}
            {formatDateTime(window.current_occurrence.ends_at, timezone)}
            {window.inherited && (
              <>
                , from{' '}
                <OwnerLink window={window}>{window.target_name}</OwnerLink>
              </>
            )}
            .
          </span>
        </Banner>
      ))}
    </div>
  );
}

export default MaintenanceWindowBanner;
