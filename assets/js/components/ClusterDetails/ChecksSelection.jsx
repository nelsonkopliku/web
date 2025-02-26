/* eslint-disable react/no-array-index-key */

import React, { useState, useEffect, useCallback } from 'react';
import { useSelector, useDispatch } from 'react-redux';

import { EOS_LOADING_ANIMATED } from 'eos-icons-react';

import { TARGET_CLUSTER } from '@lib/model';

import { remove, uniq, toggle, groupBy } from '@lib/lists';
import { getCatalog } from '@state/selectors/catalog';
import { updateCatalog } from '@state/actions/catalog';
import { executionRequested } from '@state/actions/lastExecutions';
import {
  isSaving,
  isSuccessfullySaved,
  isSavingFailed,
} from '@state/selectors/checksSelection';
import { clusterChecksSelected } from '@state/checksSelection';

import CatalogContainer from '@components/ChecksCatalog/CatalogContainer';
import {
  SavingFailedAlert,
  SuggestTriggeringChecksExecutionAfterSettingsUpdated,
} from './ClusterSettings';
import ChecksSelectionGroup, {
  NONE_CHECKED,
  SOME_CHECKED,
  ALL_CHECKED,
  allSelected,
} from './ChecksSelectionGroup';
import ChecksSelectionItem from './ChecksSelectionItem';

const isSelected = (selectedChecks, checkID) =>
  selectedChecks ? selectedChecks.includes(checkID) : false;

const getGroupSelectedState = (checks, selectedChecks) => {
  if (checks.every(({ id }) => isSelected(selectedChecks, id))) {
    return ALL_CHECKED;
  }
  if (checks.some((check) => isSelected(selectedChecks, check.id))) {
    return SOME_CHECKED;
  }
  return NONE_CHECKED;
};

function ChecksSelection({ clusterId, cluster }) {
  const dispatch = useDispatch();

  const saving = useSelector(isSaving(TARGET_CLUSTER, clusterId));
  const savingSuccess = useSelector(
    isSuccessfullySaved(TARGET_CLUSTER, clusterId)
  );
  const savingError = useSelector(isSavingFailed(TARGET_CLUSTER, clusterId));

  const {
    data: catalogData,
    error: catalogError,
    loading,
  } = useSelector(getCatalog());

  const [selectedChecks, setSelectedChecks] = useState(
    cluster ? cluster.selected_checks : []
  );
  const [localSavingError, setLocalSavingError] = useState(null);
  const [localSavingSuccess, setLocalSavingSuccess] = useState(null);
  const [groupSelection, setGroupSelection] = useState([]);
  const catalogEnv = {
    provider: cluster.provider,
    target_type: 'cluster',
  };

  useEffect(() => {
    dispatch(updateCatalog(catalogEnv));
  }, [dispatch]);

  useEffect(() => {
    const groupedCheckSelection = Object.entries(
      groupBy(catalogData, 'group')
    ).map(([group, checks]) => {
      const groupChecks = checks.map((check) => ({
        ...check,
        selected: isSelected(selectedChecks, check.id),
      }));

      return {
        group,
        checks: groupChecks,
        groupSelected: getGroupSelectedState(checks, selectedChecks),
      };
    });
    setGroupSelection(groupedCheckSelection);
  }, [catalogData, selectedChecks]);

  useEffect(() => {
    if (savingError === true) {
      setLocalSavingError(
        'An unexpected error happened while selecting your desired checks'
      );
    }
    setLocalSavingSuccess(savingSuccess);
  }, [savingError, savingSuccess]);

  useEffect(() => {
    if (cluster) {
      setSelectedChecks(cluster.selected_checks ? cluster.selected_checks : []);
    }
  }, [cluster?.selected_checks]);

  useEffect(() => {
    if (loading === true) {
      setLocalSavingError(null);
      setLocalSavingSuccess(null);
    }
  }, [loading]);

  const saveSelection = useCallback(() =>
    dispatch(
      clusterChecksSelected({
        clusterID: clusterId,
        clusterName: cluster.name,
        checks: selectedChecks,
      })
    )
  );

  return (
    <div className="bg-white rounded p-3">
      <CatalogContainer
        onRefresh={() => dispatch(updateCatalog(catalogEnv))}
        isCatalogEmpty={catalogData.length === 0}
        catalogError={catalogError}
        loading={loading}
      >
        <div>
          <div className="pb-4">
            {groupSelection?.map(({ group, checks, groupSelected }, idx) => (
              <ChecksSelectionGroup
                key={idx}
                group={group}
                selected={groupSelected}
                onChange={() => {
                  const groupChecks = checks.map((check) => check.id);
                  if (allSelected(groupSelected)) {
                    setSelectedChecks(remove(groupChecks, selectedChecks));
                  } else {
                    setSelectedChecks(
                      uniq([...selectedChecks, ...groupChecks])
                    );
                  }
                  setLocalSavingSuccess(null);
                }}
              >
                {checks.map((check) => (
                  <ChecksSelectionItem
                    key={check.id}
                    checkID={check.id}
                    name={check.name}
                    description={check.description}
                    premium={check.premium}
                    selected={check.selected}
                    onChange={() => {
                      setSelectedChecks(toggle(check.id, selectedChecks));
                      setLocalSavingSuccess(null);
                    }}
                  />
                ))}
              </ChecksSelectionGroup>
            ))}
          </div>
          <div className="place-items-end flex">
            <button
              className="flex justify-center items-center bg-jungle-green-500 hover:opacity-75 text-white font-bold py-2 px-4 rounded"
              onClick={saveSelection}
              disabled={saving}
              type="button"
              data-testid="save-selection-button"
            >
              {saving ? (
                <span className="px-20">
                  <EOS_LOADING_ANIMATED color="green" size={25} />
                </span>
              ) : (
                'Select Checks for Execution'
              )}
            </button>
            {savingError && (
              <SavingFailedAlert onClose={() => setLocalSavingError(null)}>
                <p>{localSavingError}</p>
              </SavingFailedAlert>
            )}
            {localSavingSuccess && selectedChecks.length > 0 && (
              <SuggestTriggeringChecksExecutionAfterSettingsUpdated
                clusterId={clusterId}
                selectedChecks={cluster.selected_checks}
                onClose={() => setLocalSavingSuccess(null)}
                onStartExecution={(clusterID, hosts, checks, navigate) =>
                  dispatch(
                    executionRequested(clusterID, hosts, checks, navigate)
                  )
                }
              />
            )}
          </div>
        </div>
      </CatalogContainer>
    </div>
  );
}

export default ChecksSelection;
