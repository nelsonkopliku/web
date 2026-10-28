// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import React from 'react';
import { Link } from 'react-router';
import { get, map, noop, split } from 'lodash';

const replacePattern = /({\d+})/;
const urlTypes = {
  cluster: 'clusters',
  database: 'databases',
  host: 'hosts',
  sap_system: 'sap_systems',
};

/**
 * Message of an operation policy. The resources it names as {0}, {1}... are
 * replaced with links to them, taken from the metadata by index.
 */
function PolicyMessage({ message, metadata, onLinkClick = noop }) {
  // find {i} entries in the text splitting the whole content
  const parts = split(message, replacePattern);

  return map(parts, (part) => {
    // if a part matches with the replacement pattern, find the
    // corresponding metadata by index and create the link
    if (part.match(replacePattern)) {
      const index = parseInt(part.substring(1));
      const { id, label, type } = get(metadata, index) ?? {};

      return id ? (
        <Link
          className="text-jungle-green-500 hover:opacity-75"
          onClick={onLinkClick}
          key={id}
          to={`/${urlTypes[type]}/${id}`}
        >
          {label}
        </Link>
      ) : (
        part
      );
    }
    return part;
  });
}

export default PolicyMessage;
