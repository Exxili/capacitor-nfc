import Foundation
import CoreNFC

@objc public class NFCWriter: NSObject, NFCNDEFReaderSessionDelegate {
    private var writerSession: NFCNDEFReaderSession?
    private var messageToWrite: NFCNDEFMessage?

    public var onWriteSuccess: (() -> Void)?
    public var onError: ((Error) -> Void)?

    @objc public func startWriting(message: NFCNDEFMessage) {
        print("NFCWriter startWriting called")
        self.messageToWrite = message

        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC writing not supported on this device")
            return
        }
        writerSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        writerSession?.alertMessage = "Hold your iPhone near the NFC tag to write."
        writerSession?.begin()
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
    }

    // NFCNDEFReaderSessionDelegate methods for writing
    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("NFC writer session error: \(error.localizedDescription)")
        onError?(error)
    }

    public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {

    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }

        guard let tag = tags.first else { return }

        session.connect(to: tag) { (error) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(error)
                return
            }

            tag.queryNDEFStatus { (ndefStatus, _, error) in
                if let error = error {
                    session.invalidate(errorMessage: "Unable to query the NDEF status of tag.")
                    self.onError?(error)
                    return
                }

                switch ndefStatus {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF compliant.")
                case .readOnly:
                    session.invalidate(errorMessage: "Tag is read-only.")
                case .readWrite:
                    if let message = self.messageToWrite {
                        tag.writeNDEF(message) { (error) in
                            if let error = error {
                                session.invalidate(errorMessage: "Failed to write NDEF message.")
                                self.onError?(error)
                                return
                            }
                            session.alertMessage = "NDEF message written successfully."
                            session.invalidate()
                            self.onWriteSuccess?()
                        }
                    } else {
                        session.invalidate(errorMessage: "No message to write.")
                    }
                @unknown default:
                    session.invalidate(errorMessage: "Unknown NDEF tag status.")
                }
            }
        }
    }
}
