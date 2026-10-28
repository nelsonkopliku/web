// SPDX-FileCopyrightText: SUSE LLC
// SPDX-License-Identifier: GPL-3.0-or-later

import { action } from 'storybook/actions';

import OperationAlreadyRunningModal from './OperationAlreadyRunningModal';

export default {
  title: 'Components/OperationAlreadyRunningModal',
  component: OperationAlreadyRunningModal,
  argTypes: {
    isOpen: {
      description: 'Whether the dialog is open or not',
      control: { type: 'boolean' },
    },
    operation: {
      description: 'Label of the refused operation',
      control: { type: 'text' },
    },
    onClose: {
      description: 'Callback when the dialog is closed',
      action: 'onClose',
    },
  },
};

export const Default = {
  args: {
    isOpen: true,
    operation: 'Reboot host',
    onClose: action('onClose'),
  },
};
