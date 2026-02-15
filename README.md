# Capacitor NFC Plugin (@exxili/capacitor-nfc)

A Capacitor plugin for reading and writing NFC tags on iOS and Android devices. This plugin allows you to:

- Read NDEF messages from NFC tags.
- Write NDEF messages to NFC tags.

**Note**: NFC functionality is only available on compatible iOS devices running iOS 13.0 or later.

## Table of Contents

- [Capacitor NFC Plugin (@exxili/capacitor-nfc)](#capacitor-nfc-plugin-exxilicapacitor-nfc)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [iOS Setup](#ios-setup)
    - [1. Enable NFC Capability](#1-enable-nfc-capability)
    - [2. Add Usage Description](#2-add-usage-description)
  - [Android Setup](#android-setup)
  - [Usage](#usage)
    - [Reading NFC Tags](#reading-nfc-tags)
    - [Writing NFC Tags](#writing-nfc-tags)
  - [API](#api)
    - [Methods](#methods)
      - [`isSupported()`](#issupported)
      - [`startScan()`](#startscan)
      - [`cancelScan()`](#cancelscan)
      - [`writeNDEF(options: NDEFWriteOptions<T extends string | number[] | Uint8Array = string>)`](#writendefoptions-ndefwriteoptionst-extends-string--number--uint8array--string)
      - [`cancelWriteAndroid()`](#cancelwriteandroid)
    - [Listeners](#listeners)
      - [`onRead(listener: (data: NDEFMessagesTransformable) => void)`](#onreadlistener-data-ndefmessagestransformable--void)
    - [Interfaces](#interfaces)
      - [`NDEFWriteOptions`](#ndefwriteoptions)
      - [`NDEFMessagesTransformable`](#ndefmessagestransformable)
      - [`NDEFMessages`](#ndefmessages)
      - [`NDEFMessage`](#ndefmessage)
      - [`NDEFRecord`](#ndefrecord)
      - [`NFCError`](#nfcerror)
  - [Integration into a Capacitor App](#integration-into-a-capacitor-app)
  - [Example](#example)
  - [License](#license)

## Installation

Install the plugin using npm:

```bash
npm install @exxili/capacitor-nfc
npx cap sync
```

## iOS Setup

To use NFC functionality on iOS, you need to perform some additional setup steps.

### 1. Enable NFC Capability

In Xcode:

1. Open your project (`.xcworkspace` file) in Xcode.
2. Select your project in the Project Navigator.
3. Select your app target.
4. Go to the **Signing & Capabilities** tab.
5. Click the `+ Capability` button.
6. Add **Near Field Communication Tag Reading**.

> **Advanced tag formats:** If you need ISO 7816, ISO 15693, or FeliCa access (to read raw UIDs, system codes, etc.), Apple requires additional entitlements in your provisioning profile and `Info.plist`. The plugin will fall back automatically when they are absent, but to unlock the full feature set add the relevant keys:
>
> ```xml
> <key>com.apple.developer.nfc.readersession.felica.systemcodes</key>
> <array>
>   <string>12FC</string>
>   <string>0000</string>
> </array>
> <key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
> <array>
>   <string>D2760000850100</string>
>   <string>D2760000850101</string>
>   <string>D2760001180101</string>
>   <string>00000000000000</string>
> </array>
> ```
>
> Replace the sample identifiers with the values required for your tags. Consult Apple's CoreNFC documentation for the complete list of entitlement keys.

### 2. Add Usage Description

Add the `NFCReaderUsageDescription` key to your `Info.plist` file to explain why your app needs access to NFC.

In your `Info.plist` file (usually located at `ios/App/App/Info.plist`), add:

```xml
<key>NFCReaderUsageDescription</key>
<string>This app requires access to NFC to read and write NFC tags.</string>
```

Replace the description with a message that explains why your app needs NFC access.

## Android Setup

Add the following to your `AndroidManifest.xml` file:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="true" />
```

## Usage

Import the plugin into your code:

```typescript
import { NFC } from '@exxili/capacitor-nfc';
```

### Reading NFC Tags

To read NFC tags, you need to listen for `nfcTag` events. On iOS, you must also start the NFC scanning session using `startScan()`.

```typescript
import { NFC, NDEFMessagesTransformable, NFCError } from '@exxili/capacitor-nfc';

// Start NFC scanning (iOS only)
NFC.startScan().catch((error) => {
  console.error('Error starting NFC scan:', error);
});

// Listen for NFC tag detection
NFC.onRead((data: NDEFMessagesTransformable) => {
  // Text (T) and URI (U) records decoded; others best-effort UTF-8
  const asString = data.string();
  console.log('First record text payload:', asString.messages[0]?.records[0]?.payload);

  // Raw bytes
  const asUint8 = data.uint8Array();
  console.log('First record raw bytes length:', asUint8.messages[0]?.records[0]?.payload.length);

  // Access tag information (UID, tech types, etc.)
  const info = asString.tagInfo;
  if (info?.fallback) {
    console.log('Reader fallback mode:', info.fallbackMode, 'Reason:', info.reason);
  } else if (info) {
    console.log('Tag UID:', info.uid);
    console.log('Tag technologies:', info.techTypes);
    console.log('Tag type:', info.type);
    if (info.maxSize) {
      console.log('Max NDEF size:', info.maxSize);
    }
    console.log('Is writable:', info.isWritable);
  }
});

// Handle NFC errors
NFC.onError((error: NFCError) => {
  console.error('NFC Error:', error);
});
```

### Writing NFC Tags

To write NDEF messages to NFC tags, use the `writeNDEF` method and listen for `onWrite` events.

```typescript
import { NFC, NDEFWriteOptions, NFCError } from '@exxili/capacitor-nfc';

const message: NDEFWriteOptions = {
  records: [
    {
      type: 'T', // Well Known Text record. String payload will be encoded as: [status][lang='en'][UTF-8 text]
      payload: 'Hello, NFC!',
    },
    {
      type: 'U', // Well Known URI record. String payload encoded as: [0x00][URI bytes]
      payload: 'https://example.com',
    },
    {
      type: 'T',
      payload: new Uint8Array([0x01, 0x65, 0x48, 0x69]), // Raw bytes preserved (DO NOT re-format)
    },
  ],
};

// For complete control over binary content, use raw mode:
const rawMessage: NDEFWriteOptions = {
  rawMode: true, // Bypasses automatic Text/URI formatting
  records: [
    {
      type: 'T',
      payload: 'Hello, NFC!', // Written as UTF-8 bytes without Text record prefix
    },
    {
      type: 'custom',
      payload: new Uint8Array([0x01, 0x02, 0x03, 0x04]), // Exact bytes written to tag
    },
  ],
};

// Write NDEF message to NFC tag
NFC.writeNDEF(message)
  .then(() => {
    console.log('Write initiated');
  })
  .catch((error) => {
    console.error('Error writing to NFC tag:', error);
  });

// Listen for write success
NFC.onWrite(() => {
  console.log('NDEF message written successfully.');
});

// Handle NFC errors
NFC.onError((error: NFCError) => {
  console.error('NFC Error:', error);
});
```

## API

### Methods

#### `isSupported()`

Returns if NFC is supported on the scanning device.

**Returns**: `Promise<{ supported: boolean }>`

#### `startScan()`

Starts the NFC scanning session on **_iOS only_**. Android devices are always in reading mode, so setting up the `nfcTag` listener is sufficient to handle tag reads on Android.

The iOS implementation now adapts automatically if the extended CoreNFC entitlements (ISO 7816, ISO 15693, FeliCa) are missing. The plugin first attempts the advanced tag reader so you can access UID/tech info. When iOS reports `Missing required entitlement`, the plugin downgrades to a compatibility mode (ISO 14443 only) and, if necessary, to the classic NDEF reader. A synthetic `nfcTag` event is emitted with `tagInfo.fallback`, `tagInfo.fallbackMode`, and `tagInfo.reason` so your UI can react immediately.

You can override the mode explicitly:

- `mode: 'auto'` (default) – advanced reader with automatic downgrade and caching.
- `mode: 'full'` – force a fresh attempt at the advanced reader, resetting cached fallback state.
- `mode: 'compat'` – skip the advanced probe and jump straight to the ISO 14443 compatibility reader.
- `mode: 'ndef'` – bypass tag sessions entirely and revert to the legacy NDEF-only reader.

Legacy booleans `forceFull`, `forceCompat`, and `forceNDEF` map to the options above for backwards compatibility.

**Returns**: `Promise<void>`

```typescript
NFC.startScan({ mode: 'auto' })
  .then(() => {
    // Scanning started
  })
  .catch((error) => {
    console.error('Error starting NFC scan:', error);
  });
```

#### `cancelScan()`

Immediately invalidates the active iOS CoreNFC reader session (if any). Useful when you want to abort a scan early instead of waiting for the user to cancel or for a tag detection timeout.

Platform notes:

- iOS: Actively ends the session. Calling `startScan()` again after the returned promise resolves is safe.
- Android: No-op (Android is always passively listening via foreground dispatch; you generally just ignore future events or control UI state).

```typescript
await NFC.cancelScan(); // iOS: ends session; Android: no-op
// Optionally restart
await NFC.startScan();
```

**Returns**: `Promise<void>`

#### `writeNDEF(options: NDEFWriteOptions<T extends string | number[] | Uint8Array = string>)`

Writes an NDEF message to an NFC tag.

Payload may be provided as a string, `Uint8Array`, or an array of numbers.

Automatic formatting rules (to aid interoperability):

- Text (`type: 'T'` + string payload): encoded per NFC Forum RTD Text spec `[status][lang=en][UTF-8 text]`.
- URI (`type: 'U'` + string payload): encoded as `[0x00][UTF-8 URI bytes]` (prefix compression not yet applied).
- Any other `type` + string payload: UTF-8 bytes only (no extra framing).
- `Uint8Array` or `number[]` payloads are treated as raw bytes and written verbatim (never altered).

**Raw Mode**: Set `rawMode: true` to bypass automatic Well Known Type formatting entirely. All string payloads will be written as UTF-8 bytes without Text ('T') or URI ('U') prefixes, giving you complete control over the binary content.

If you need full manual control of a Text or URI record, supply raw bytes (number[] / Uint8Array) and the plugin will not modify them.

If you attempt to write zero records the promise rejects with `Error("At least one NDEF record is required")`.

Android use: since Android has no default UI for reading and writing NFC tags, it is recommended that you add a UI indicator to your application when calling `writeNDEF` and remove it in the `nfcWriteSuccess` listener callback and the `nfcError` listener callback. This will prevent accidental writes to tags that your users intended to read from.

**Parameters**:

- `options: NDEFWriteOptions<T extends string | number[] | Uint8Array = string>` - The NDEF message to write. Must include at least one record.

**Returns**: `Promise<void>`

```typescript
NFC.writeNDEF(options)
  .then(() => {
    // Write initiated
  })
  .catch((error) => {
    console.error('Error writing NDEF message:', error);
  });
```

#### `cancelWriteAndroid()`

Cancels an Android NFC write operation. Android does not have a native UI for NFC tag writing, so this method allows developers to hook up a custom UI to cancel an in-progress scan.

### Listeners

#### `onRead(listener: (data: NDEFMessagesTransformable) => void)`

Adds a listener for NFC tag detection events. Returns type `NDEFMessagesTransformable`, which returns the following methods to provide the payload:

- `string()`: Returns `NDEFMessages<string>`, where all payloads are strings.
- `base64()`: Returns `NDEFMessages<string>`, where all payloads are the base64-encoded payloads read from the NFC tag.
- `uint8Array()`: Returns `NDEFMessages<Uint8Array>`, where all payloads are the `Uint8Array` bytes from the NFC tag.
- `numberArray()`: Returns `NDEFMessages<number[]>`, where all payloads' bytes from the NFC tag are represented as a `number[]`.

**Parameters**:

- `listener: (data: NDEFMessagesTransformable) => void` - The function to call when an NFC tag is detected.

**Returns**: `() => void` Unsubscribe function to remove just this listener.

```typescript
const offRead = NFC.onRead((data) => {
  const textRecords = data.string(); // Decoded string representation
  const base64Records = data.base64(); // Original base64 payloads
  const bytesRecords = data.uint8Array(); // Uint8Array payloads
  const numArrayRecords = data.numberArray(); // number[] representation
  console.log(textRecords);
});

// Later (component unmount / cleanup)
offRead();
```

> Tip: Register listeners once per screen/component and always dispose them when unmounting to avoid duplicate callbacks.

````

#### On Error

Adds a listener for NFC error events.

**Parameters**:

- `listener: (error: NFCError) => void` - The function to call when an NFC error occurs.

**Returns**: `() => void` Unsubscribe function.

#### On Error

Adds a listener for NFC error events.

**Parameters**:

- `listener: (error: NFCError) => void` - The function to call when an NFC error occurs.

**Returns**: `() => void` Unsubscribe function.

```typescript
const offError = NFC.onError(err => console.error('NFC Error:', err));
// later
offError();
````

### Interfaces

#### `NDEFWriteOptions`

Options for writing an NDEF message.

```typescript
interface NDEFWriteOptions<T extends string | number[] | Uint8Array = string> {
  records: NDEFRecord<T>[];
  /**
   * When true, bypasses automatic Well Known Type formatting (Text 'T' and URI 'U' prefixes).
   * All payloads are written as raw bytes without additional framing.
   */
  rawMode?: boolean;
}
```

#### `NDEFMessagesTransformable`

Returned by `onRead` and includes the following methods to provide the payload:

- `string()`: Returns `NDEFMessages<string>`, where all payloads are strings.
- `base64()`: Returns `NDEFMessages<string>`, where all payloads are the base64-encoded payloads read from the NFC tag.
- `uint8Array()`: Returns `NDEFMessages<Uint8Array>`, where all payloads are the `Uint8Array` bytes from the NFC tag.
- `numberArray()`: Returns `NDEFMessages<number[]>`, where all payloads bytes from the NFC tag represented as a `number[]`.

```typescript
interface NDEFMessagesTransformable {
  base64: () => NDEFMessages<string>; // Original base64 strings
  uint8Array: () => NDEFMessages<Uint8Array>; // Raw bytes
  string: () => NDEFMessages<string>; // Decoded (T & U handled, others UTF-8 best-effort)
  numberArray: () => NDEFMessages<number[]>; // Raw bytes as number[]
}
```

#### `NDEFMessages`

Data received from an NFC tag.

```typescript
interface NDEFMessages {
  messages: NDEFMessage[];
  tagInfo?: TagInfo;
}
```

#### `TagInfo`

Information about the NFC tag that was read.

```typescript
interface TagInfo {
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
   * Present when the plugin downgraded capabilities for compatibility.
   */
  fallback?: boolean;

  /**
   * Which fallback strategy is in use (`compat` or `ndef`).
   */
  fallbackMode?: 'compat' | 'ndef';

  /**
   * Reason metadata (e.g., `missing-entitlement`).
   */
  reason?: string;
}
```

#### `StartScanOptions`

Optional tweaks for the iOS reader behavior.

```typescript
interface StartScanOptions {
  mode?: 'auto' | 'full' | 'compat' | 'ndef';
  forceFull?: boolean;
  forceCompat?: boolean;
  forceNDEF?: boolean;
}
```

#### `NDEFMessage`

An NDEF message consisting of one or more records.

```typescript
interface NDEFMessage {
  records: NDEFRecord[];
}
```

#### `NDEFRecord`

An NDEF record. `payload` is, by default, an array of bytes representing the data; this is how an `NDEFRecord` is read from an NFC tag. You can choose to provide an `NDEFRecord` as a string a `Uint8Array` also.

```typescript
interface NDEFRecord<T = number[]> {
  /**
   * The type of the record.
   */
  type: string;

  /**
   * The payload of the record.
   */
  payload: T;
}
```

#### `NFCError`

An NFC error.

```typescript
interface NFCError {
  /**
   * The error message.
   */
  error: string;
}
```

## Integration into a Capacitor App

To integrate this plugin into your Capacitor app:

1. **Install the plugin:**

   ```bash
   npm install @exxili/capacitor-nfc
   npx cap sync
   ```

2. **Import the plugin in your code:**

   ```typescript
   import { NFC } from '@exxili/capacitor-nfc';
   ```

3. **Use the plugin methods as described in the [Usage](#usage) section.**

## Example

Here's a complete example of how to read and write NFC tags in your app:

```typescript
import { NFC, NDEFWriteOptions, NFCError, NDEFMessagesTransformable } from '@exxili/capacitor-nfc';

// Check if NFC is supported (optional gating logic)
const { supported } = await NFC.isSupported();
if (!supported) {
  console.warn('NFC not supported on this device');
}

// Start NFC scanning (needed on iOS only)
NFC.startScan().catch((err) => console.error('Failed to start scan', err));

// Read listener returns a transformable wrapper
const offRead = NFC.onRead((data: NDEFMessagesTransformable) => {
  const textView = data.string(); // NDEFMessages<string>
  const rawBytesView = data.uint8Array(); // NDEFMessages<Uint8Array>

  const firstText = textView.messages[0]?.records[0]?.payload;
  const firstLength = rawBytesView.messages[0]?.records[0]?.payload.length;
  console.log('First text record:', firstText);
  console.log('First record byte length:', firstLength);
});

// Error listener (covers read & write errors)
const offError = NFC.onError((error: NFCError) => console.error('NFC Error:', error));

// Prepare an NDEF message to write (auto-formats Text/URI if payload is string)
const message: NDEFWriteOptions = {
  records: [
    { type: 'T', payload: 'Hello, NFC!' },
    { type: 'U', payload: 'https://example.com' },
  ],
};

await NFC.writeNDEF(message).catch((err) => console.error('Write failed', err));

const offWrite = NFC.onWrite(() => console.log('Write success'));

// Later (cleanup)
offRead();
offError();
offWrite();
```

## License

[MIT License](https://opensource.org/license/mit)

---

**Support**: If you encounter any issues or have questions, feel free to open an issue.

---
