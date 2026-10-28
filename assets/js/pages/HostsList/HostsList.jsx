// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React, { useEffect, useState } from 'react';

import { useSelector, useDispatch } from 'react-redux';
import { EOS_WARNING_OUTLINED } from 'eos-icons-react';
import { fromPairs, uniqBy } from 'lodash';
import classNames from 'classnames';
import semver from 'semver';

import BulkScheduleModal from '@common/BulkScheduleModal';
import Button from '@common/Button';
import CleanUpButton from '@common/CleanUpButton';
import DisabledGuard from '@common/DisabledGuard';
import HealthIcon from '@common/HealthIcon';
import HostLink from '@common/HostLink';
import { Checkbox } from '@common/Input';
import { ScheduleWarningsModal } from '@common/OperationModals';
import MaintenanceWindowModal from '@common/MaintenanceWindowModal';
import PremiumPill from '@common/PremiumPill';
import PageHeader from '@common/PageHeader';
import Pill from '@common/Pill';
import ProviderLabel from '@common/ProviderLabel';
import SapSystemLink from '@common/SapSystemLink';
import Table from '@common/Table';
import Tags from '@common/Tags';
import Tooltip from '@common/Tooltip';

import { post, del } from '@lib/network';
import { agentVersionWarning } from '@lib/agent';
import { getFromConfig } from '@lib/config';
import {
  HOST_REBOOT,
  countTargets,
  getOperationLabel,
  getOperationPermittedFor,
} from '@lib/operations';
import { STALE_ROW } from '@lib/tables';

import usePersistentSearchParams from '@hooks/usePersistentSearchParams';

import ClusterLink from '@pages/ClusterDetails/ClusterLink';
import DeregistrationModal from '@pages/DeregistrationModal';
import HealthSummary from '@pages/HealthSummary';
import { getCounters } from '@pages/HealthSummary/summarySelection';

import { addTagToHost, removeTagFromHost, deregisterHost } from '@state/hosts';
import { getUserProfile } from '@state/selectors/user';
import { hostsListSelector } from '@state/selectors/host';
import { getInstanceID } from '@state/instances';
import {
  bulkScheduleOperation,
  hasScheduleWarnings,
  isScheduleSubmitted,
  resetOperationScheduleSubmission,
} from '@state/operationSchedules';
import { getOperationScheduleSubmission } from '@state/selectors/operationSchedules';
import {
  bulkScheduleMaintenanceWindows,
  isSubmittingWindow,
  isWindowSubmitted,
  resetMaintenanceWindowSubmission,
} from '@state/maintenanceWindows';
import { getMaintenanceWindowSubmission } from '@state/selectors/maintenanceWindows';

import { maintenanceWindowsPermittedFor } from '@pages/MaintenanceWindows/MaintenanceWindowsSection';

const compareAgentVersions = (a, b) => {
  const coercedA = semver.coerce(a);
  const coercedB = semver.coerce(b);
  if (coercedA && coercedB) {
    return semver.compare(coercedA, coercedB);
  }
  return String(a).localeCompare(String(b));
};

const addTag = (tag, hostId) => {
  post(`/hosts/${hostId}/tags`, {
    value: tag,
  });
};

const removeTag = (tag, hostId) => {
  del(`/hosts/${hostId}/tags/${tag}`);
};

function HostsList() {
  const hostsData = useSelector(hostsListSelector);
  const { abilities, timezone } = useSelector(getUserProfile);

  const [searchParams, setSearchParams] = usePersistentSearchParams('hosts');
  const [cleanUpModalOpen, setCleanUpModalOpen] = useState(false);
  const [hostToDeregister, setHostToDeregister] = useState(undefined);
  // The selectable table of #4954 will replace this selection
  const [selectedHostIDs, setSelectedHostIDs] = useState([]);
  // The hosts of the bulk modals, taken from the selection when one opens: a
  // change of the rows clears the selection, also while a modal is open
  const [bulkHostIDs, setBulkHostIDs] = useState([]);
  const [bulkModalOpen, setBulkModalOpen] = useState(false);
  const scheduleSubmission = useSelector(getOperationScheduleSubmission);
  const [maintenanceModalOpen, setMaintenanceModalOpen] = useState(false);
  const windowSubmission = useSelector(getMaintenanceWindowSubmission);

  const operationsEnabled = getFromConfig('operationsEnabled');

  const dispatch = useDispatch();

  // Only the hosts shown with the current filters and page can be selected:
  // the selection is forgotten when they change, and leaves out the hosts
  // that are gone
  const selectedHosts = (hostsData || []).filter(({ id }) =>
    selectedHostIDs.includes(id)
  );
  const clearSelection = () => setSelectedHostIDs([]);
  const bulkHosts = (hostsData || []).filter(({ id }) =>
    bulkHostIDs.includes(id)
  );

  const filtersQuery = searchParams.toString();
  useEffect(() => {
    clearSelection();
  }, [filtersQuery]);

  const scheduleSubmitted = isScheduleSubmitted(scheduleSubmission);
  useEffect(() => {
    if (scheduleSubmitted) {
      setBulkModalOpen(false);
      clearSelection();
    }
  }, [scheduleSubmitted]);

  const windowsScheduled = isWindowSubmitted(windowSubmission);
  useEffect(() => {
    if (windowsScheduled) {
      setMaintenanceModalOpen(false);
      clearSelection();
    }
  }, [windowsScheduled]);

  useEffect(
    () => () => {
      dispatch(resetOperationScheduleSubmission());
      dispatch(resetMaintenanceWindowSubmission());
    },
    [dispatch]
  );

  const scheduleMaintenance = (window) =>
    dispatch(
      bulkScheduleMaintenanceWindows({
        request: {
          target_type: 'host',
          target_ids: bulkHosts.map(({ id }) => id),
          ...window,
        },
      })
    );

  const toggleHostSelection = (hostID) =>
    setSelectedHostIDs((selected) =>
      selected.includes(hostID)
        ? selected.filter((id) => id !== hostID)
        : [...selected, hostID]
    );

  const scheduleReboot = (schedule, { confirmed }) =>
    dispatch(
      bulkScheduleOperation({
        request: {
          target_type: 'host',
          target_ids: bulkHosts.map(({ id }) => id),
          operation: HOST_REBOOT,
          params: {},
          ...schedule,
        },
        confirmed,
      })
    );

  const openDeregistrationModal = (host) => {
    setHostToDeregister(host);
    setCleanUpModalOpen(true);
  };

  const cleanUpHost = ({ id, hostname }) => {
    setCleanUpModalOpen(false);
    dispatch(deregisterHost({ id, hostname }));
  };

  const counters = getCounters(hostsData || []);

  const selectionColumns = operationsEnabled
    ? [
        {
          title: <span className="sr-only">Selection</span>,
          key: 'id',
          className: 'w-8',
          render: (id, { hostname }) => (
            <Checkbox
              aria-label={`Select ${hostname}`}
              checked={selectedHostIDs.includes(id)}
              onChange={() => toggleHostSelection(id)}
            />
          ),
        },
      ]
    : [];

  const config = {
    pagination: true,
    usePadding: false,
    onPageChange: clearSelection,
    rowClassName: ({ staleAt }) =>
      classNames({
        [STALE_ROW]: !!staleAt,
      }),
    columns: [
      ...selectionColumns,
      {
        title: 'Health',
        key: 'health',
        filter: true,
        filterFromParams: true,
        render: (health, { staleAt }) => (
          <HealthIcon
            health={health}
            staleAt={staleAt}
            timezone={timezone}
            centered
          />
        ),
      },
      {
        title: 'Hostname',
        key: 'hostname',
        className: 'w-40',
        filter: true,
        filterFromParams: true,
        render: (content, { id }) => <HostLink hostId={id}>{content}</HostLink>,
      },
      {
        title: 'IP',
        key: 'ip',
        render: (content) =>
          content.map((ip) => (
            <div key={ip} className="text-sm">
              {ip}
            </div>
          )),
      },
      {
        title: 'Provider',
        key: 'provider',
        render: (content) => {
          if (content) {
            return <ProviderLabel provider={content} />;
          }
          return '';
        },
      },
      {
        title: 'Cluster',
        key: 'cluster',
        className: 'w-40',
        render: (cluster) => <ClusterLink cluster={cluster} />,
      },
      {
        title: 'SID',
        key: 'sid',
        filterFromParams: true,
        filter: (filter, key) => (element) =>
          element[key].some((sid) => filter.includes(sid)),
        render: (_sids, { sap_systems }) => {
          const instances = uniqBy(sap_systems, getInstanceID);
          return instances.map((instance) => {
            const sapSystemId = getInstanceID(instance);
            return (
              <span key={sapSystemId}>
                <SapSystemLink
                  systemType={instance?.type}
                  sapSystemId={sapSystemId}
                >
                  {instance?.sid}
                </SapSystemLink>{' '}
              </span>
            );
          });
        },
      },
      {
        title: 'Agent version',
        key: 'agent_version',
        filter: true,
        filterFromParams: true,
        filterOptionsSorter: compareAgentVersions,
        render: (content) => {
          const warning = agentVersionWarning(content);
          if (warning) {
            return (
              <Tooltip className="w-52" content={warning} place="bottom">
                <Pill
                  size="xs"
                  className="bg-yellow-100 text-yellow-800 group flex items-center relative"
                >
                  <EOS_WARNING_OUTLINED
                    size="base"
                    className="centered fill-yellow-800"
                  />
                  <span className="ml-1 truncate max-w-[100px]">{content}</span>
                </Pill>
              </Tooltip>
            );
          }
          return (
            <Pill
              size="xs"
              display="inline-block"
              className="bg-green-100 text-green-800 truncate max-w-[112px]"
            >
              {content}
            </Pill>
          );
        },
      },
      {
        title: 'Tags',
        key: 'tags',
        className: 'w-80',
        filterFromParams: true,
        filter: (filter, key) => (element) =>
          element[key].some((tag) => filter.includes(tag)),
        render: (content, item) => (
          <Tags
            userAbilities={abilities}
            tagAdditionPermittedFor={['all:host_tags']}
            tagDeletionPermittedFor={['all:host_tags']}
            tags={content}
            resourceId={item.id}
            onChange={() => {}}
            onAdd={(tag) => {
              addTag(tag, item.id);
              dispatch(addTagToHost({ tags: [{ value: tag }], id: item.id }));
            }}
            onRemove={(tag) => {
              removeTag(tag, item.id);
              dispatch(
                removeTagFromHost({ tags: [{ value: tag }], id: item.id })
              );
            }}
          />
        ),
      },
      {
        title: '',
        key: 'deregisterable',
        className: 'w-48',
        render: (content, item) =>
          content && (
            <CleanUpButton
              cleaning={item.deregistering}
              size="fit"
              type="transparent"
              className="border-none shadow-none"
              userAbilities={abilities}
              permittedFor={['cleanup:host']}
              onClick={() => {
                openDeregistrationModal(item);
              }}
            />
          ),
      },
    ],
  };

  return (
    <>
      <PageHeader className="font-bold">Hosts</PageHeader>
      <DeregistrationModal
        hostname={hostToDeregister?.hostname}
        isOpen={!!cleanUpModalOpen}
        onCleanUp={() => {
          cleanUpHost(hostToDeregister);
        }}
        onCancel={() => {
          setCleanUpModalOpen(false);
        }}
      />
      {operationsEnabled && (
        <>
          <BulkScheduleModal
            key={`bulk-schedule-${bulkModalOpen}`}
            isOpen={bulkModalOpen}
            operation={HOST_REBOOT}
            targetType="host"
            targetsCount={bulkHosts.length}
            timezone={timezone}
            targetNames={fromPairs(
              bulkHosts.map(({ id, hostname }) => [id, hostname])
            )}
            submission={scheduleSubmission}
            onSchedule={scheduleReboot}
            onCancel={() => setBulkModalOpen(false)}
          />
          <ScheduleWarningsModal
            isOpen={hasScheduleWarnings(scheduleSubmission)}
            operation={getOperationLabel(scheduleSubmission.operation)}
            warnings={scheduleSubmission.warnings}
            onClose={() => dispatch(resetOperationScheduleSubmission())}
          />
        </>
      )}
      {maintenanceModalOpen && (
        <MaintenanceWindowModal
          isOpen
          targetLabel={countTargets(bulkHosts.length, 'host')}
          timezone={timezone}
          loading={isSubmittingWindow(windowSubmission)}
          errors={windowSubmission.errors}
          onSave={scheduleMaintenance}
          onCancel={() => setMaintenanceModalOpen(false)}
        />
      )}
      {operationsEnabled && (
        <div className="flex justify-end items-center space-x-2 pb-2">
          <span className="text-sm text-gray-500" aria-live="polite">
            {selectedHosts.length === 0
              ? 'No hosts selected'
              : `${countTargets(selectedHosts.length, 'host')} selected`}
          </span>
          <Button
            type="primary-white-fit"
            size="small"
            disabled={selectedHosts.length === 0}
            onClick={clearSelection}
          >
            Clear selection
          </Button>
          <DisabledGuard
            userAbilities={abilities}
            permitted={maintenanceWindowsPermittedFor}
          >
            <Button
              type="primary-white-fit"
              size="small"
              disabled={selectedHosts.length === 0}
              onClick={() => {
                dispatch(resetMaintenanceWindowSubmission());
                setBulkHostIDs(selectedHosts.map(({ id }) => id));
                setMaintenanceModalOpen(true);
              }}
            >
              Schedule Maintenance
              <PremiumPill className="ml-2" />
            </Button>
          </DisabledGuard>
          <DisabledGuard
            userAbilities={abilities}
            permitted={getOperationPermittedFor(HOST_REBOOT)}
          >
            <Button
              type="primary-white-fit"
              size="small"
              disabled={selectedHosts.length === 0}
              onClick={() => {
                dispatch(resetOperationScheduleSubmission());
                setBulkHostIDs(selectedHosts.map(({ id }) => id));
                setBulkModalOpen(true);
              }}
            >
              Schedule Reboot
            </Button>
          </DisabledGuard>
        </div>
      )}
      <div className="bg-white rounded-lg shadow">
        <HealthSummary {...counters} className="px-4 py-2" />
        <Table
          config={config}
          data={hostsData}
          searchParams={searchParams}
          setSearchParams={setSearchParams}
        />
      </div>
    </>
  );
}

export default HostsList;
