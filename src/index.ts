import { Capacitor, registerPlugin } from '@capacitor/core';

import type {
  NDEFMessagesTransformable,
  NDEFWriteOptions,
  NFCPlugin,
  NFCPluginBasic,
  StartScanOptions,
  PayloadType,
  TagResultListenerFunc,
  NFCError,
  NDEFMessages,
} from './definitions.js';

const NFCPlug = registerPlugin<NFCPluginBasic>('NFC', {
  // Explicit .js extension required under node16/nodenext module resolution for emitted ES modules.
  web: () => import('./web.js').then((m) => new m.NFCWeb()),
});
export * from './definitions.js';

const LISTENER_ATTACH_RETRY_MS = 500;

const isNativeRuntime = (): boolean => Capacitor.getPlatform() !== 'web';

const createRetryingNativeListener = (
  eventName: 'nfcTag' | 'nfcWriteSuccess' | 'nfcError',
  listener: (data: any) => void,
): (() => void) => {
  let removed = false;
  let attaching = false;
  let handle: any;
  let retryTimer: ReturnType<typeof setTimeout> | undefined;

  const attach = () => {
    if (removed || attaching || handle) return;
    attaching = true;
    try {
      const result = (NFCPlug as any).addListener(eventName, listener);
      if (result && typeof result.then === 'function') {
        result
          .then((h: any) => {
            attaching = false;
            handle = h ?? result;
          })
          .catch(() => {
            attaching = false;
            if (removed || !isNativeRuntime()) return;
            retryTimer = setTimeout(attach, LISTENER_ATTACH_RETRY_MS);
          });
      } else {
        attaching = false;
        handle = result;
      }
    } catch {
      attaching = false;
      if (removed || !isNativeRuntime()) return;
      retryTimer = setTimeout(attach, LISTENER_ATTACH_RETRY_MS);
    }
  };

  attach();

  return () => {
    removed = true;
    if (retryTimer) clearTimeout(retryTimer);
    try {
      handle?.remove?.();
    } catch {
      /* empty */
    }
  };
};

let stopNativeTagBridge: (() => void) | undefined;
let nativeTagBridgeAttached = false;

const dispatchNfcTag = (data: any): void => {
  const wrappedData: NDEFMessagesTransformable = {
    base64() {
      return mapPayloadTo('b64', data);
    },
    string() {
      return mapPayloadTo('string', data);
    },
    uint8Array() {
      return mapPayloadTo('uint8Array', data);
    },
    numberArray() {
      return mapPayloadTo('numberArray', data);
    },
  };

  for (const listener of NFC.wrapperListeners) {
    listener(wrappedData);
  }
};

const ensureNativeTagBridge = (): void => {
  if (nativeTagBridgeAttached) return;
  nativeTagBridgeAttached = true;
  stopNativeTagBridge = createRetryingNativeListener('nfcTag', dispatchNfcTag);
};

export const NFC: NFCPlugin = {
  isSupported: NFCPlug.isSupported.bind(NFCPlug),
  startScan: (options?: StartScanOptions) => {
    ensureNativeTagBridge();
    const normalizedOptions: Record<string, unknown> = {};
    if (options) {
      for (const [key, value] of Object.entries(options)) {
        if (value !== undefined && value !== null) {
          normalizedOptions[key] = value;
        }
      }
    }
    return NFCPlug.startScan(normalizedOptions);
  },
  cancelScan:
    NFCPlug.cancelScan?.bind(NFCPlug) ??
    (async () => {
      /* Android no-op */
    }),
  cancelWriteAndroid: NFCPlug.cancelWriteAndroid.bind(NFCPlug),
  onRead: (func: TagResultListenerFunc) => {
    ensureNativeTagBridge();
    NFC.wrapperListeners.push(func);
    // Return unsubscribe function
    return () => {
      NFC.wrapperListeners = NFC.wrapperListeners.filter((l: TagResultListenerFunc) => l !== func);
    };
  },
  onWrite: (func: () => void) => {
    return createRetryingNativeListener('nfcWriteSuccess', func);
  },
  onError: (errorFn: (error: NFCError) => void) => {
    return createRetryingNativeListener('nfcError', errorFn as (data: any) => void);
  },
  removeAllListeners: (eventName: 'nfcTag' | 'nfcError') => {
    NFC.wrapperListeners = [];
    if (eventName === 'nfcTag') {
      stopNativeTagBridge?.();
      stopNativeTagBridge = undefined;
      nativeTagBridgeAttached = false;
    }
    return NFCPlug.removeAllListeners(eventName);
  },
  wrapperListeners: [],

  async writeNDEF<T extends PayloadType = Uint8Array>(options?: NDEFWriteOptions<T>): Promise<void> {
    // Helper encoders for well-known record types (only applied to string payloads)
    const buildTextPayload = (text: string, lang = 'en'): number[] => {
      const langBytes = Array.from(new TextEncoder().encode(lang));
      const textBytes = Array.from(new TextEncoder().encode(text));
      const status = langBytes.length & 0x3f; // UTF-8 encoding, language length (<= 63)
      return [status, ...langBytes, ...textBytes];
    };
    const buildUriPayload = (uri: string, prefixCode = 0x00): number[] => {
      const uriBytes = Array.from(new TextEncoder().encode(uri));
      return [prefixCode, ...uriBytes];
    };

    const recordsArray = options?.records ?? [];
    if (recordsArray.length === 0) throw new Error('At least one NDEF record is required');

    const isRawMode = options?.rawMode === true;

    const ndefMessage: NDEFWriteOptions<number[]> = {
      records: recordsArray.map((record: any) => {
        let payload: number[] | null = null;

        if (typeof record.payload === 'string') {
          if (isRawMode) {
            // Raw mode: write string payloads as UTF-8 bytes without any framing
            payload = Array.from(new TextEncoder().encode(record.payload));
          } else {
            // Apply spec-compliant formatting only for Well Known Text (T) & URI (U) types.
            if (record.type === 'T') {
              payload = buildTextPayload(record.payload);
            } else if (record.type === 'U') {
              payload = buildUriPayload(record.payload);
            } else {
              // Generic string: raw UTF-8 bytes (no extra framing)
              payload = Array.from(new TextEncoder().encode(record.payload));
            }
          }
        } else if (Array.isArray(record.payload)) {
          // Assume already raw bytes; do NOT modify
          payload = record.payload as number[];
        } else if (record.payload instanceof Uint8Array) {
          payload = Array.from(record.payload);
        }

        if (!payload) throw new Error('Unsupported payload type');

        return { type: record.type, payload };
      }),
    };

    await NFCPlug.writeNDEF(ndefMessage);
  },
};

// ----- Payload transformation helpers -----
type DecodeSpecifier = 'b64' | 'string' | 'uint8Array' | 'numberArray';
type decodedType<T extends DecodeSpecifier> = NDEFMessages<
  T extends 'b64' ? string : T extends 'string' ? string : T extends 'uint8Array' ? Uint8Array : number[]
>;

// Decode a base64 string into a Uint8Array (browser-safe). Existing code used atob already.
const decodeBase64ToBytes = (base64Payload: string): Uint8Array => {
  const bin = atob(base64Payload);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
};

// Parse NFC Forum "Text" (Well Known 'T') records according to spec.
const decodeTextRecord = (bytes: Uint8Array): string => {
  if (bytes.length === 0) return '';
  const status = bytes[0];
  const isUTF16 = (status & 0x80) !== 0; // Bit 7 indicates encoding
  const langLength = status & 0x3f; // Bits 0-5 language code length
  if (1 + langLength > bytes.length) return ''; // Corrupt
  const textBytes = bytes.slice(1 + langLength);
  try {
    const decoder = new TextDecoder(isUTF16 ? 'utf-16' : 'utf-8');
    return decoder.decode(textBytes);
  } catch {
    // Fallback: naive ASCII
    return Array.from(textBytes)
      .map((b) => String.fromCharCode(b))
      .join('');
  }
};

// Basic URI prefix table for Well Known 'U' records (optional convenience)
const URI_PREFIX: string[] = [
  '',
  'http://www.',
  'https://www.',
  'http://',
  'https://',
  'tel:',
  'mailto:',
  'ftp://anonymous:anonymous@',
  'ftp://ftp.',
  'ftps://',
  'sftp://',
  'smb://',
  'nfs://',
  'ftp://',
  'dav://',
  'news:',
  'telnet://',
  'imap:',
  'rtsp://',
  'urn:',
  'pop:',
  'sip:',
  'sips:',
  'tftp:',
  'btspp://',
  'btl2cap://',
  'btgoep://',
  'tcpobex://',
  'irdaobex://',
  'file://',
  'urn:epc:id:',
  'urn:epc:tag:',
  'urn:epc:pat:',
  'urn:epc:raw:',
  'urn:epc:',
  'urn:nfc:',
];

const decodeUriRecord = (bytes: Uint8Array): string => {
  if (bytes.length === 0) return '';
  const prefixIndex = bytes[0];
  const prefix = URI_PREFIX[prefixIndex] || '';
  const remainder = bytes.slice(1);
  try {
    return prefix + new TextDecoder('utf-8').decode(remainder);
  } catch {
    return (
      prefix +
      Array.from(remainder)
        .map((b) => String.fromCharCode(b))
        .join('')
    );
  }
};

const toStringPayload = (recordType: string, bytes: Uint8Array): string => {
  // Well Known Text
  if (recordType === 'T') return decodeTextRecord(bytes);
  // Well Known URI
  if (recordType === 'U') return decodeUriRecord(bytes);
  // Default: attempt UTF-8 decode
  try {
    return new TextDecoder('utf-8').decode(bytes);
  } catch {
    return Array.from(bytes)
      .map((c) => String.fromCharCode(c))
      .join('');
  }
};

const mapPayloadTo = <T extends DecodeSpecifier>(type: T, data: NDEFMessages): decodedType<T> => {
  return {
    messages: data.messages.map((message: any) => ({
      records: message.records.map((record: any) => {
        const bytes = decodeBase64ToBytes(record.payload as unknown as string);
        let payload: any;
        switch (type) {
          case 'b64':
            payload = record.payload; // original base64 string
            break;
          case 'uint8Array':
            payload = bytes;
            break;
          case 'numberArray':
            payload = Array.from(bytes);
            break;
          case 'string':
            payload = toStringPayload(record.type, bytes);
            break;
          default:
            payload = record.payload;
        }
        return { type: record.type, payload };
      }),
    })),
    tagInfo: data.tagInfo, // Include tag information
  } as decodedType<T>;
};
