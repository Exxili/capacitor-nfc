import type { PluginListenerHandle } from '@capacitor/core';

// Payload from a new NFC scan is a base64 encoded string
export type PayloadType = string | number[] | Uint8Array;

export interface StartScanOptions {
  /**
   * Select the native reader strategy.
   * - `auto` (default): attempt advanced tag session first, downgrade automatically on entitlement failures.
   * - `full`: force the advanced tag session (resets any cached fallback state).
   * - `compat`: force the compatibility tag session (ISO14443-only, avoids advanced entitlements).
   * - `ndef`: skip tag session entirely and use the legacy NDEF reader.
   */
  mode?: 'auto' | 'full' | 'compat' | 'ndef';
  /**
   * Backwards-compatible hints for older app code. When true, they map to `mode` selections above.
   */
  forceFull?: boolean;
  forceCompat?: boolean;
  forceNDEF?: boolean;
}

export interface NFCPluginBasic {
  /**
   * Checks if NFC is supported on the device. Returns true on all iOS devices, and checks for support on Android.
   */
  isSupported(): Promise<{ supported: boolean }>;

  /**
   * Begins listening for NFC tags.
   * @param options Optional tuning parameters for native reader behavior.
   */
  startScan(options?: StartScanOptions): Promise<void>;

  /**
   * Cancels an ongoing scan session (iOS only currently; no-op / rejection on Android).
   */
  cancelScan(): Promise<void>;

  /**
   * Writes an NDEF message to an NFC tag.
   * @param options The NDEF message to write.
   */
  writeNDEF<T extends PayloadType = number[]>(options: NDEFWriteOptions<T>): Promise<void>;

  /**
   * Cancels writeNDEF on Android (exits "write mode").
   */
  cancelWriteAndroid(): Promise<void>;

  /**
   * Adds a listener for NFC tag detection events.
   * @param eventName The name of the event ('nfcTag').
   * @param listenerFunc The function to call when an NFC tag is detected.
   */
  addListener(
    eventName: 'nfcTag',
    listenerFunc: (data: NDEFMessages) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Adds a listener for NFC tag write events.
   * @param eventName The name of the event ('nfcWriteSuccess').
   * @param listenerFunc The function to call when an NFC tag is written.
   */
  addListener(
    eventName: 'nfcWriteSuccess',
    listenerFunc: () => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Adds a listener for NFC error events.
   * @param eventName The name of the event ('nfcError').
   * @param listenerFunc The function to call when an NFC error occurs.
   */
  addListener(
    eventName: 'nfcError',
    listenerFunc: (error: NFCError) => void,
  ): Promise<PluginListenerHandle> & PluginListenerHandle;

  /**
   * Removes all listeners for the specified event.
   * @param eventName The name of the event.
   */
  removeAllListeners(eventName: 'nfcTag' | 'nfcError'): Promise<void>;
}

export interface NDEFMessages<T extends PayloadType = string> {
  messages: NDEFMessage<T>[];
  tagInfo?: TagInfo;
}

export interface NDEFMessage<T extends PayloadType = string> {
  records: NDEFRecord<T>[];
}

export interface TagInfo {
  /**
   * The unique identifier of the tag (UID) as a hex string
   */
  uid?: string;

  /**
   * The NFC tag technology types supported
   */
  techTypes?: string[];

  /**
   * The maximum size of NDEF message that can be written to this tag (if applicable)
   */
  maxSize?: number;

  /**
   * Whether the tag is writable
   */
  isWritable?: boolean;

  /**
   * The tag type (e.g., "ISO14443-4", "MifareClassic", etc.)
   */
  type?: string;

  /**
   * Truthy when the plugin downgraded reader capabilities for compatibility.
   */
  fallback?: boolean;

  /**
   * Indicates the active fallback mode (`compat` or `ndef`).
   */
  fallbackMode?: 'compat' | 'ndef';

  /**
   * Optional reason string when fallback was applied (e.g., `missing-entitlement`).
   */
  reason?: string;
}

export interface NDEFRecord<T extends PayloadType = string> {
  /**
   * The type of the record.
   */
  type: string;

  /**
   * The payload of the record.
   */
  payload: T;
}

export interface NFCError {
  /**
   * The error message.
   */
  error: string;
}

export interface NDEFWriteOptions<T extends PayloadType = Uint8Array> {
  records: NDEFRecord<T>[];
  /**
   * When true, bypasses automatic Well Known Type formatting (Text 'T' and URI 'U' prefixes).
   * All payloads are written as raw bytes without additional framing.
   */
  rawMode?: boolean;
}

export type NDEFMessagesTransformable = {
  base64: () => NDEFMessages;
  uint8Array: () => NDEFMessages<Uint8Array>;
  string: () => NDEFMessages;
  numberArray: () => NDEFMessages<number[]>;
};

export type TagResultListenerFunc = (data: NDEFMessagesTransformable) => void;

export interface NFCPlugin extends Omit<NFCPluginBasic, 'writeNDEF' | 'addListener'> {
  writeNDEF: <T extends PayloadType = Uint8Array>(record?: NDEFWriteOptions<T>) => Promise<void>;
  wrapperListeners: TagResultListenerFunc[];
  /**
   * Register a read listener. Returns an unsubscribe function to remove just this listener.
   */
  onRead: (listenerFunc: TagResultListenerFunc) => () => void;
  /**
   * Register a write success listener. Returns an unsubscribe function.
   */
  onWrite: (listenerFunc: () => void) => () => void;
  /**
   * Register an error listener. Returns an unsubscribe function.
   */
  onError: (listenerFunc: (error: NFCError) => void) => () => void;
}
