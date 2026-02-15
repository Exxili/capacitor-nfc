import Foundation
import CoreNFC
// swiftlint:disable:next type_body_length
@objc public class NFCReader: NSObject, NFCTagReaderSessionDelegate, NFCNDEFReaderSessionDelegate {
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Intentionally left blank; no special handling needed when tag session becomes active.
    }
    private enum ReaderMode {
        case fullTag
        case limitedTag
        case ndefFallback

        var alertSuffix: String {
            switch self {
            case .fullTag:
                return "."
            case .limitedTag:
                return " (compatibility mode)."
            case .ndefFallback:
                return " (NDEF mode)."
            }
        }

        var metadataValue: String {
            switch self {
            case .fullTag:
                return "full"
            case .limitedTag:
                return "compat"
            case .ndefFallback:
                return "ndef"
            }
        }
    }

    private var readerSession: NFCTagReaderSession?
    private var ndefReaderSession: NFCNDEFReaderSession?
    private var readerMode: ReaderMode = .fullTag
    private var autoRestartWorkItem: DispatchWorkItem?
    private var entitlementFailureDetected = false
    private var lastFallbackSignature: (mode: ReaderMode, reason: String?)?

    public var onNDEFMessageReceived: (([NFCNDEFMessage], [String: Any]?) -> Void)?
    public var onError: ((Error) -> Void)?

    @objc public func setPreferredReaderMode(_ rawMode: String?) {
        guard let rawMode = rawMode?.lowercased() else { return }
        switch rawMode {
        case "full", "advanced", "forcefull":
            readerMode = .fullTag
            entitlementFailureDetected = false
            lastFallbackSignature = nil
        case "compat", "compatibility", "limited":
            readerMode = .limitedTag
            lastFallbackSignature = nil
        case "ndef":
            readerMode = .ndefFallback
            lastFallbackSignature = nil
        case "auto":
            if entitlementFailureDetected {
                if readerMode == .fullTag {
                    readerMode = .limitedTag
                }
            } else {
                readerMode = .fullTag
                lastFallbackSignature = nil
            }
        default:
            break
        }
        if readerMode == .fullTag {
            lastFallbackSignature = nil
        }
    }

    @objc public func startScanning() {
        print("NFCReader startScanning called")
        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC scanning not supported on this device")
            return
        }
        if readerMode != .fullTag {
            let reason = entitlementFailureDetected ? "missing-entitlement" : nil
            emitFallbackMetadata(for: readerMode, reason: reason)
        }

        autoRestartWorkItem?.cancel()
        startCurrentModeSession()
    }

    @objc public func cancelScanning() {
        autoRestartWorkItem?.cancel()
        autoRestartWorkItem = nil
        if let session = readerSession { session.invalidate() }
        if let ndef = ndefReaderSession { ndef.invalidate() }
        readerSession = nil
        ndefReaderSession = nil
        lastFallbackSignature = nil
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("NFC reader session error: \(error.localizedDescription)")
        lastFallbackSignature = nil
        readerSession = nil
        guard let nfcError = error as? NFCReaderError else {
            onError?(error)
            return
        }

        if handleEntitlementOrSystemErrors(nfcError) {
            return
        }

        if nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            return
        }

        onError?(error)
    }

    private func startCurrentModeSession() {
        switch readerMode {
        case .fullTag:
            beginTagSession(pollingOption: [.iso14443, .iso15693, .iso18092])
        case .limitedTag:
            beginTagSession(pollingOption: [.iso14443])
        case .ndefFallback:
            beginNDEFFallbackSession()
        }
    }

    private func beginTagSession(pollingOption: NFCTagReaderSession.PollingOption) {
        guard NFCTagReaderSession.readingAvailable else {
            print("[NFC] Tag reading not supported on this device")
            return
        }
        DispatchQueue.main.async {
            if let existingSession = self.readerSession {
                existingSession.invalidate()
            }
            self.ndefReaderSession?.invalidate()
            self.ndefReaderSession = nil

            guard let session = NFCTagReaderSession(pollingOption: pollingOption, delegate: self, queue: nil) else {
                print("[NFC] Failed to create NFCTagReaderSession (nil).")
                return
            }
            session.alertMessage = "Hold your iPhone near the NFC tag" + self.readerMode.alertSuffix
            self.readerSession = session
            session.begin()
        }
    }

    private func beginNDEFFallbackSession() {
        guard NFCNDEFReaderSession.readingAvailable else { return }
        DispatchQueue.main.async {
            if self.ndefReaderSession != nil { return }
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
            session.alertMessage = "Hold your iPhone near the NFC tag. (NDEF mode)"
            self.ndefReaderSession = session
            session.begin()
        }
    }

    private func scheduleRestart(after delay: TimeInterval = 0.25) {
        autoRestartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.autoRestartWorkItem = nil
            self.startCurrentModeSession()
        }
        autoRestartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func emitFallbackMetadata(for mode: ReaderMode, reason: String? = nil) {
        guard mode != .fullTag else { return }
        if let last = lastFallbackSignature, last.mode == mode, last.reason == reason {
            return
        }
        lastFallbackSignature = (mode, reason)

        var metadata: [String: Any] = [
            "fallback": true,
            "fallbackMode": mode.metadataValue
        ]
        if let reason = reason {
            metadata["reason"] = reason
        }
        DispatchQueue.main.async {
            self.onNDEFMessageReceived?([], metadata)
        }
    }

    private func handleEntitlementOrSystemErrors(_ error: NFCReaderError) -> Bool {
        let description = error.localizedDescription.lowercased()

        if description.contains("missing required entitlement") || error.code == .readerErrorSecurityViolation {
            if readerMode == .fullTag {
                print("[NFC] Missing advanced tag entitlement detected -> switching to compatibility mode")
                readerMode = .limitedTag
                entitlementFailureDetected = true
                emitFallbackMetadata(for: readerMode, reason: "missing-entitlement")
                scheduleRestart()
                return true
            }

            if readerMode == .limitedTag {
                print("[NFC] Compatibility mode also unavailable -> falling back to NDEF session")
                readerMode = .ndefFallback
                entitlementFailureDetected = true
                emitFallbackMetadata(for: readerMode, reason: "missing-entitlement")
                scheduleRestart()
                return true
            }
        }

        if description.contains("system resource unavailable") || error.code == .readerSessionInvalidationErrorSystemIsBusy {
            print("[NFC] System resource unavailable; retrying current reader mode")
            scheduleRestart(after: 0.35)
            return true
        }

        return false
    }

    // MARK: - NFCNDEFReaderSessionDelegate
    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("NDEF reader session error: \(error.localizedDescription)")
        if session === ndefReaderSession {
            ndefReaderSession = nil
            lastFallbackSignature = nil
        }
        onError?(error)
    }

    // Called when the NFCNDEFReaderSession becomes active (needed to silence runtime delegate warning)
    public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        let isFallback = (session === ndefReaderSession)
        print("NDEF reader session became active (fallback mode: \(isFallback))")
        if isFallback {
            let reason = entitlementFailureDetected ? "missing-entitlement" : nil
            emitFallbackMetadata(for: .ndefFallback, reason: reason)
        }
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        // Mirror writer logic for reading first NDEF tag
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }
        guard let tag = tags.first else { return }
        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(connectError)
                return
            }
            tag.queryNDEFStatus { status, _, statusError in
                if let statusError = statusError {
                    session.invalidate(errorMessage: "Unable to query the NDEF status of tag.")
                    self.onError?(statusError)
                    return
                }
                guard status != .notSupported else {
                    session.invalidate(errorMessage: "Tag is not NDEF compliant.")
                    return
                }
                tag.readNDEF { message, readError in
                    if let readError = readError {
                        session.invalidate(errorMessage: "Failed to read NDEF message.")
                        self.onError?(readError)
                        return
                    }
                    if let message = message {
                        session.alertMessage = "Found 1 NDEF message."
                        session.invalidate()
                        self.onNDEFMessageReceived?([message], nil)
                    } else {
                        session.alertMessage = "No NDEF message found."
                        session.invalidate()
                        self.onNDEFMessageReceived?([], nil)
                    }
                }
            }
        }
    }

    // Some SDK versions (and build settings) still require this legacy delegate method.
    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Forward directly; no tag info available in this callback.
        if !messages.isEmpty {
            session.invalidate()
            onNDEFMessageReceived?(messages, nil)
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please remove extra tags and try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }

        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found.")
            return
        }
        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(error)
                return
            }

            // Extract tag information
            let tagInfo = self.extractTagInfo(from: tag)

            // Try to read NDEF if the tag supports it
            if case let .iso7816(iso7816Tag) = tag {
                self.handleISO7816Tag(iso7816Tag, session: session, tagInfo: tagInfo)
            } else if case let .miFare(miFareTag) = tag {
                self.handleMiFareTag(miFareTag, session: session, tagInfo: tagInfo)
            } else if case let .feliCa(feliCaTag) = tag {
                self.handleFeliCaTag(feliCaTag, session: session, tagInfo: tagInfo)
            } else if case let .iso15693(iso15693Tag) = tag {
                self.handleISO15693Tag(iso15693Tag, session: session, tagInfo: tagInfo)
            } else {
                // Unknown tag type, still return tag info
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
            }
        }
    }

    private func extractTagInfo(from tag: NFCTag) -> [String: Any] {
        var tagInfo: [String: Any] = [:]
        var techTypes: [String] = []
        var uid: String = ""

        switch tag {
        case .iso7816(let iso7816Tag):
            uid = iso7816Tag.identifier.map { String(format: "%02X", $0) }.joined()
            techTypes.append("ISO7816")
            tagInfo["type"] = "ISO7816"

        case .miFare(let miFareTag):
            uid = miFareTag.identifier.map { String(format: "%02X", $0) }.joined()
            techTypes.append("MiFare")
            tagInfo["type"] = "MiFare"

        case .feliCa(let feliCaTag):
            uid = feliCaTag.currentIDm.map { String(format: "%02X", $0) }.joined()
            techTypes.append("FeliCa")
            tagInfo["type"] = "FeliCa"

        case .iso15693(let iso15693Tag):
            uid = iso15693Tag.identifier.map { String(format: "%02X", $0) }.joined()
            techTypes.append("ISO15693")
            tagInfo["type"] = "ISO15693"

        @unknown default:
            techTypes.append("Unknown")
            tagInfo["type"] = "Unknown"
        }

        tagInfo["uid"] = uid
        tagInfo["techTypes"] = techTypes

        return tagInfo
    }

    private func handleMiFareTag(_ miFareTag: NFCMiFareTag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        miFareTag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                self.onError?(error)
                return
            }

            if ndefStatus == .notSupported {
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
                return
            }

            var updatedTagInfo = tagInfo
            updatedTagInfo["maxSize"] = capacity
            updatedTagInfo["isWritable"] = ndefStatus == .readWrite

            miFareTag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to read NDEF from tag.")
                    self.onError?(error)
                    return
                }

                if let message = message {
                    session.alertMessage = "Found 1 NDEF message."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], updatedTagInfo)
                } else {
                    session.alertMessage = "Tag detected but no NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([], updatedTagInfo)
                }
            }
        }
    }

    private func handleISO7816Tag(_ iso7816Tag: NFCISO7816Tag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        // ISO7816 tags don't typically support NDEF directly
        session.alertMessage = "Tag detected but no NDEF message found."
        session.invalidate()
        self.onNDEFMessageReceived?([], tagInfo)
    }

    private func handleFeliCaTag(_ feliCaTag: NFCFeliCaTag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        feliCaTag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                self.onError?(error)
                return
            }

            if ndefStatus == .notSupported {
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
                return
            }

            var updatedTagInfo = tagInfo
            updatedTagInfo["maxSize"] = capacity
            updatedTagInfo["isWritable"] = ndefStatus == .readWrite

            feliCaTag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to read NDEF from tag.")
                    self.onError?(error)
                    return
                }

                if let message = message {
                    session.alertMessage = "Found 1 NDEF message."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], updatedTagInfo)
                } else {
                    session.alertMessage = "Tag detected but no NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([], updatedTagInfo)
                }
            }
        }
    }

    private func handleISO15693Tag(_ iso15693Tag: NFCISO15693Tag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        iso15693Tag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                self.onError?(error)
                return
            }

            if ndefStatus == .notSupported {
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
                return
            }

            var updatedTagInfo = tagInfo
            updatedTagInfo["maxSize"] = capacity
            updatedTagInfo["isWritable"] = ndefStatus == .readWrite

            iso15693Tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to read NDEF from tag.")
                    self.onError?(error)
                    return
                }

                if let message = message {
                    session.alertMessage = "Found 1 NDEF message."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], updatedTagInfo)
                } else {
                    session.alertMessage = "Tag detected but no NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([], updatedTagInfo)
                }
            }
        }
    }
}

// Removed supplemental stubs (logNFCFormatsIfAvailable, tagReaderSessionDidBecomeActive) as they are no longer needed.
