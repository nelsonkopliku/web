// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { Link } from 'react-router';

const URL_TYPES = {
  host: 'hosts',
  cluster: 'clusters',
  database: 'databases',
  sap_system: 'sap_systems',
};

// Link to the target a window is set on
function OwnerLink({
  window: { target_type: targetType, target_id: targetID },
  children,
}) {
  return (
    <Link
      className="text-jungle-green-500 hover:opacity-75"
      to={`/${URL_TYPES[targetType]}/${targetID}`}
    >
      {children}
    </Link>
  );
}

export default OwnerLink;
