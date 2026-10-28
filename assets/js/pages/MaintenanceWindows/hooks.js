// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';

import { nextWindowsBoundary } from '@lib/model/maintenanceWindows';
import {
  deleteMaintenanceWindow,
  fetchMaintenanceWindows,
  forgetMaintenanceWindows,
  resetMaintenanceWindowSubmission,
  scheduleMaintenanceWindow,
  updateMaintenanceWindow,
} from '@state/maintenanceWindows';
import {
  getMaintenanceWindowSubmission,
  getMaintenanceWindows,
} from '@state/selectors/maintenanceWindows';

// setTimeout takes at most about 24 days: far boundaries are looked at again
// every day
const MAX_BOUNDARY_DELAY = 24 * 60 * 60 * 1000;

// The server may still be on the other side of the boundary for a moment
const BOUNDARY_MARGIN = 1000;

/**
 * Maintenance windows that cover a displayed target, its own and the
 * inherited ones. They are fetched again when one of them starts or ends, so
 * that the view follows the active ones, and forgotten when the target is not
 * displayed anymore.
 */
export const useMaintenanceWindows = (targetType, targetID) => {
  const dispatch = useDispatch();
  const { windows, loading, error } = useSelector(
    getMaintenanceWindows(targetID)
  );
  const submission = useSelector(getMaintenanceWindowSubmission);

  const fetchWindows = () =>
    dispatch(fetchMaintenanceWindows({ targetType, targetID }));

  useEffect(() => {
    if (!targetID) return undefined;

    dispatch(fetchMaintenanceWindows({ targetType, targetID }));

    return () => {
      dispatch(forgetMaintenanceWindows({ targetID }));
      dispatch(resetMaintenanceWindowSubmission());
    };
  }, [dispatch, targetType, targetID]);

  useEffect(() => {
    const boundary = nextWindowsBoundary(windows);
    if (!boundary) return undefined;

    const timer = setTimeout(
      fetchWindows,
      Math.min(boundary - Date.now() + BOUNDARY_MARGIN, MAX_BOUNDARY_DELAY)
    );

    return () => clearTimeout(timer);
  }, [windows]);

  // Named after the props of MaintenanceWindowsSection
  return {
    windows,
    loading,
    error,
    submission,
    onSchedule: (window) =>
      dispatch(
        scheduleMaintenanceWindow({
          request: { target_type: targetType, target_id: targetID, ...window },
        })
      ),
    onUpdate: (window, changes) =>
      dispatch(updateMaintenanceWindow({ window, changes })),
    onDelete: (window) => dispatch(deleteMaintenanceWindow({ window })),
    onRetry: fetchWindows,
    onResetSubmission: () => dispatch(resetMaintenanceWindowSubmission()),
  };
};
