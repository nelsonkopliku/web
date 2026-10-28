// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';

import { get } from 'lodash';
import { pipe, map, omit } from 'lodash/fp';

import { notify } from '@state/notifications';

import {
  getChecksSelection,
  resetCheckCustomization,
  saveCheckCustomization,
} from '@lib/api/checks';
import {
  getChecksSchedule,
  updateChecksSchedule,
} from '@lib/api/checksSchedule';
import { defaultGlobalError } from '@lib/api/validationErrors';

const setCheckCustomized = (customized) => (check) => ({
  ...check,
  customized,
});

const applyValueCustomization = ({ value, customization }) =>
  customization ? { ...value, custom_value: customization.value } : value;

const findValueCustomization = (customValues) => (value) => ({
  value,
  customization: customValues.find(({ name }) => name === value.name),
});

const saveValuesCustomizations = (customValues) => (check) => ({
  ...check,
  values: map(
    pipe(findValueCustomization(customValues), applyValueCustomization)
  )(check.values),
});

const resetValuesCustomizations = (check) => ({
  ...check,
  values: map(omit('custom_value'))(check.values),
});

const saveCheck = (checkID, customValues) => (check) =>
  check.id === checkID
    ? pipe(
        setCheckCustomized(true),
        saveValuesCustomizations(customValues)
      )(check)
    : check;

const resetCheck = (checkId) => (check) =>
  check.id === checkId
    ? pipe(setCheckCustomized(false), resetValuesCustomizations)(check)
    : check;

export const READY = 'ready';
export const ONGOING = 'ongoing';
export const INVALID_VALUES = 'invalid_values';
export const GENERIC_FAILURE = 'generic_failure';

export const CUSTOMIZATION_STATUSES = [
  READY,
  ONGOING,
  INVALID_VALUES,
  GENERIC_FAILURE,
];

export const isReady = (status) => status === READY;
export const isOngoing = (status) => status === ONGOING;
export const isFailed = (status) =>
  [GENERIC_FAILURE, INVALID_VALUES].includes(status);
export const isInvalidValues = (status) => status === INVALID_VALUES;
export const isGenericFailure = (status) => status === GENERIC_FAILURE;

export const useChecksSelection = () => {
  const dispatch = useDispatch();
  const [loading, setLoading] = useState(false);
  const [checksSelection, setChecksSelection] = useState([]);
  const [fetchError, setFetchError] = useState(null);
  const [customizationStatus, setCustomizationStatus] = useState(READY);

  const notifySuccess = (successMsg) =>
    pipe(() => ({ text: successMsg, icon: '✅' }), notify, dispatch);

  const notifyError = (errorMsg) =>
    pipe(() => ({ text: errorMsg, icon: '❌' }), notify, dispatch)();

  const fetchChecksSelection = async (groupId, env) => {
    setLoading(true);
    setFetchError(null);
    try {
      const {
        data: { items },
      } = await getChecksSelection(groupId, env);
      setChecksSelection(items);
    } catch (error) {
      setFetchError(error.message);
    } finally {
      setLoading(false);
    }
  };

  const saveChecksCustomization = async (checkID, groupID, customValues) => {
    setCustomizationStatus(ONGOING);
    try {
      const {
        data: { values },
      } = await saveCheckCustomization(checkID, groupID, customValues);
      pipe(
        map(saveCheck(checkID, values)),
        setChecksSelection,
        notifySuccess('Check was customized successfully')
      )(checksSelection);
      setCustomizationStatus(READY);
    } catch ({ response: { status } }) {
      notifyError('Failed to customize check');
      setCustomizationStatus(status === 400 ? INVALID_VALUES : GENERIC_FAILURE);
    }
  };

  const resetChecksCustomization = async (groupId, checkId) => {
    try {
      await resetCheckCustomization(groupId, checkId);
      pipe(
        map(resetCheck(checkId)),
        setChecksSelection,
        notifySuccess('Customization was reset!')
      )(checksSelection);
    } catch (error) {
      notifyError('Unable to reset customization');
    }
  };

  return {
    checksSelectionLoading: loading,
    checksSelectionFetchError: fetchError,
    checksSelection,
    fetchChecksSelection,
    resetChecksCustomization,
    saveChecksCustomization,
    customizationStatus,
  };
};

/**
 * Checks execution frequency of a host or a cluster, and when its checks are
 * executed next. The next execution moves when an execution of the target
 * starts or completes, so the schedule is fetched again then, without the
 * loading state: what shows the schedule, and an open modal, stay.
 * `saveSchedule` resolves to whether the change was saved.
 */
export const useChecksSchedule = (targetType, targetID) => {
  const [schedule, setSchedule] = useState(null);
  const [fetchLoading, setFetchLoading] = useState(Boolean(targetID));
  const [fetchError, setFetchError] = useState(false);
  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitErrors, setSubmitErrors] = useState([]);

  // Responses can arrive out of order: only the latest request counts
  const latestRequest = useRef(0);
  const shownTarget = useRef(null);
  const target = `${targetType}/${targetID}`;

  const lastExecutionStatus = useSelector((state) =>
    get(state, ['lastExecutions', targetID, 'data', 'status'])
  );

  const fetchSchedule = async () => {
    latestRequest.current += 1;
    const request = latestRequest.current;
    const isLatest = () => request === latestRequest.current;

    if (shownTarget.current !== target) setFetchLoading(true);
    setFetchError(false);

    try {
      const { data } = await getChecksSchedule(targetType, targetID);
      if (isLatest()) {
        shownTarget.current = target;
        setSchedule(data);
      }
    } catch {
      if (isLatest()) setFetchError(true);
    } finally {
      if (isLatest()) setFetchLoading(false);
    }
  };

  const saveSchedule = async (changes) => {
    latestRequest.current += 1;
    const request = latestRequest.current;

    setSubmitLoading(true);
    setSubmitErrors([]);

    try {
      const { data } = await updateChecksSchedule(
        targetType,
        targetID,
        changes
      );
      if (request === latestRequest.current) setSchedule(data);
      return true;
    } catch (error) {
      setSubmitErrors(
        get(error, ['response', 'data', 'errors'], [defaultGlobalError])
      );
      return false;
    } finally {
      setSubmitLoading(false);
    }
  };

  useEffect(() => {
    if (targetID) fetchSchedule();
  }, [targetType, targetID, lastExecutionStatus]);

  return {
    schedule,
    fetchLoading,
    fetchError,
    submitLoading,
    submitErrors,
    fetchSchedule,
    saveSchedule,
    clearSubmitErrors: () => setSubmitErrors([]),
  };
};
