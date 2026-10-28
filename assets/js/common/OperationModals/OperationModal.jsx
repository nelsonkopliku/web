// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useEffect, useState } from 'react';
import { noop } from 'lodash';

import Modal from '@common/Modal';
import Button from '@common/Button';
import Label from '@common/Label';
import { Checkbox } from '@common/Input';
import Banner from '@common/Banners';
import { describeOccurrences, recurrenceToForm } from '@lib/model/recurrence';
import {
  describeOperationParams,
  shouldShowOperationDisclaimer,
  waiveOperationDisclaimer,
} from '@lib/operations';
import { DEFAULT_TIMEZONE } from '@lib/timezones';

import ScheduleFields, {
  ScheduleRequestErrors,
  initialScheduleForm,
  isScheduleFormValid,
  scheduleFormErrors,
  scheduleToForm,
  toScheduleRequest,
} from './ScheduleFields';

const FORM_STEP = 'form';
const ALREADY_SCHEDULED_STEP = 'already_scheduled';
const CONFIRM_CANCEL_STEP = 'confirm_cancel';

const defaultSchedules = [];
const defaultErrors = [];

function DisclaimerContent({
  dontShowAgainDisclaimerChecked,
  setDontShowAgainDisclaimerChecked,
  operationText,
}) {
  return (
    <>
      <Banner type="warning" iconSize="xl" truncate={false}>
        By proceeding I confirm to be aware of the impact that executing
        operation &quot;{operationText}&quot; will have in my environment
      </Banner>
      <div className="flex space-x-1 items-center pt-2">
        <Label className="cursor-pointer">
          Don&apos;t show this again
          <Checkbox
            className="ml-2"
            checked={dontShowAgainDisclaimerChecked}
            onChange={() => setDontShowAgainDisclaimerChecked((prev) => !prev)}
          />
        </Label>
      </div>
    </>
  );
}

const describeSchedule = (schedule) => {
  const options = describeOperationParams(schedule.params);
  const when = `${describeOccurrences(schedule, schedule.timezone)} (${schedule.timezone})`;

  return options ? `${when}, ${options}` : when;
};

function AlreadyScheduledContent({ operationText, schedules }) {
  return (
    <>
      <Banner type="warning" truncate={false}>
        {operationText} is already scheduled for this target:
      </Banner>
      <ul className="list-disc list-inside space-y-1 my-2 text-sm">
        {schedules.map((schedule) => (
          <li key={schedule.id}>{describeSchedule(schedule)}</li>
        ))}
      </ul>
      <p className="text-sm">Schedule it once more?</p>
    </>
  );
}

// The start of an existing schedule, kept as it is when it is in the past
const startOf = (schedule) => {
  if (!schedule) return null;

  const { date, time } = recurrenceToForm(schedule, schedule.timezone);
  return { date, time };
};

/**
 * Modal to request an operation now, or to schedule it when `schedulable`.
 * `onRequest` receives the schedule, or null when the operation is requested
 * now. With an `initialSchedule`, the modal changes or cancels that schedule.
 * The parent remounts the modal, with a `key`, to start again from scratch.
 */
function OperationModal({
  title,
  description,
  operationText,
  requestDisabled = false,
  isOpen = false,
  schedulable = false,
  timezone = DEFAULT_TIMEZONE,
  initialSchedule = null,
  existingSchedules = defaultSchedules,
  loading = false,
  errors = defaultErrors,
  onRequest = noop,
  onCancel = noop,
  onCancelSchedule = null,
  children,
}) {
  const scheduleTimezone = initialSchedule?.timezone ?? timezone;
  const [scheduleForm, setScheduleForm] = useState(() =>
    initialSchedule
      ? scheduleToForm(initialSchedule)
      : initialScheduleForm(timezone)
  );
  const [step, setStep] = useState(FORM_STEP);

  const [showDisclaimer, setShowDisclaimer] = useState(
    shouldShowOperationDisclaimer()
  );
  const [dontShowAgainDisclaimerChecked, setDontShowAgainDisclaimerChecked] =
    useState(false);

  const resolvedTitle = showDisclaimer ? 'Disclaimer' : title;

  const unchangedStart = startOf(initialSchedule);
  const scheduling = schedulable && scheduleForm.type !== 'now';
  const scheduleValid =
    !scheduling ||
    isScheduleFormValid(
      scheduleFormErrors(scheduleForm, scheduleTimezone, { unchangedStart })
    );
  const schedule = schedulable
    ? toScheduleRequest(scheduleForm, scheduleTimezone)
    : null;

  const maybeWaiveDisclaimerAndContinue = () => {
    dontShowAgainDisclaimerChecked && waiveOperationDisclaimer();
    setShowDisclaimer(false);
    setDontShowAgainDisclaimerChecked(false);
  };

  const request = () => {
    if (scheduling && !initialSchedule && existingSchedules.length > 0) {
      setStep(ALREADY_SCHEDULED_STEP);
      return;
    }

    onRequest(schedule);
  };

  useEffect(() => {
    isOpen && setShowDisclaimer(shouldShowOperationDisclaimer());
    isOpen && setStep(FORM_STEP);
  }, [isOpen]);

  let requestLabel = 'Request';
  if (scheduling) requestLabel = initialSchedule ? 'Save Schedule' : 'Schedule';

  const cancelButton = (
    <Button
      type="primary-white-fit"
      className="inline-block mx-0.5 border-green-500 border"
      size="small"
      onClick={() => {
        onCancel();
        setDontShowAgainDisclaimerChecked(false);
      }}
    >
      Cancel
    </Button>
  );

  const renderStep = () => {
    if (showDisclaimer) {
      return (
        <>
          <DisclaimerContent
            dontShowAgainDisclaimerChecked={dontShowAgainDisclaimerChecked}
            setDontShowAgainDisclaimerChecked={
              setDontShowAgainDisclaimerChecked
            }
            operationText={operationText}
          />
          <div className="flex justify-start gap-2 mt-4">
            <Button
              type="default-fit"
              className="inline-block mx-0.5 border-green-500 border w-fit"
              size="small"
              onClick={maybeWaiveDisclaimerAndContinue}
            >
              Proceed
            </Button>
            {cancelButton}
          </div>
        </>
      );
    }

    if (step === ALREADY_SCHEDULED_STEP) {
      return (
        <>
          <AlreadyScheduledContent
            operationText={operationText}
            schedules={existingSchedules}
          />
          <div className="flex justify-start gap-2 mt-4">
            <Button
              type="default-fit"
              className="inline-block mx-0.5 border-green-500 border w-fit"
              size="small"
              onClick={() => {
                setStep(FORM_STEP);
                onRequest(schedule);
              }}
            >
              Continue
            </Button>
            {cancelButton}
          </div>
        </>
      );
    }

    if (step === CONFIRM_CANCEL_STEP) {
      return (
        <>
          <p className="text-sm">
            Cancel this schedule of {operationText}? The operation will not be
            requested anymore.
          </p>
          <div className="flex justify-start gap-2 mt-4">
            <Button
              type="danger"
              size="small"
              className="inline-block mx-0.5 w-fit"
              disabled={loading}
              onClick={onCancelSchedule}
            >
              Yes, Cancel Schedule
            </Button>
            <Button
              type="primary-white-fit"
              className="inline-block mx-0.5 border-green-500 border"
              size="small"
              onClick={() => setStep(FORM_STEP)}
            >
              Keep Schedule
            </Button>
          </div>
          <ScheduleRequestErrors errors={errors} />
        </>
      );
    }

    return (
      <>
        <p className="text-gray-500 text-sm font-normal tracking-wide pb-3">
          {description}
        </p>
        {children}
        {schedulable && (
          <ScheduleFields
            form={scheduleForm}
            timezone={scheduleTimezone}
            allowNow={!initialSchedule}
            unchangedStart={unchangedStart}
            errors={errors}
            onChange={setScheduleForm}
          />
        )}
        <div className="flex justify-start gap-2 mt-4">
          <Button
            type="default-fit"
            className="inline-block mx-0.5 border-green-500 border w-fit"
            size="small"
            disabled={requestDisabled || loading || !scheduleValid}
            onClick={request}
          >
            {requestLabel}
          </Button>
          {initialSchedule && onCancelSchedule && (
            <Button
              type="danger"
              size="small"
              className="inline-block mx-0.5 w-fit"
              onClick={() => setStep(CONFIRM_CANCEL_STEP)}
            >
              Cancel Schedule
            </Button>
          )}
          {cancelButton}
        </div>
        <ScheduleRequestErrors errors={errors} />
      </>
    );
  };

  return (
    <Modal
      className="!w-3/4 !max-w-3xl"
      title={resolvedTitle}
      open={isOpen}
      onClose={onCancel}
    >
      {renderStep()}
    </Modal>
  );
}

export default OperationModal;
