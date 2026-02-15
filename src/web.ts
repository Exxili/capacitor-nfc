import { WebPlugin } from '@capacitor/core';

import type { StartScanOptions } from './definitions.js';

export class NFCWeb extends WebPlugin {
  async isSupported(): Promise<{ supported: boolean }> {
    return { supported: false };
  }

  async startScan(_options?: StartScanOptions): Promise<void> {
    throw new Error('NFC is not supported on web');
  }

  async cancelScan(): Promise<void> {
    throw new Error('NFC is not supported on web');
  }

  async cancelWriteAndroid(): Promise<void> {
    throw new Error('NFC is not supported on web');
  }

  async writeNDEF(_options?: any): Promise<void> {
    throw new Error('NFC is not supported on web');
  }
}
