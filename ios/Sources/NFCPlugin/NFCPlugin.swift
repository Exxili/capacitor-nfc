import Foundation
import Capacitor
import CoreNFC

@objc(NFCPlugin)
public class NFCPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NFCPlugin"
    public let jsName = "NFC"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancelWriteAndroid", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startScan", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "writeNDEF", returnType: CAPPluginReturnPromise)
    ]

    private let reader = NFCReader()
    private let writer = NFCWriter()

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["supported": NFCNDEFReaderSession.readingAvailable])
    }

    @objc func cancelWriteAndroid(_ call: CAPPluginCall) {
        call.reject("Function not implemented for iOS")
    }

    @objc func startScan(_ call: CAPPluginCall) {
        print("startScan called")
        reader.onNDEFMessageReceived = { messages in
            var ndefMessages = [[String: Any]]()
            for message in messages {
                var records = [[String: Any]]()
                for record in message.records {
                    let recordType = String(data: record.type, encoding: .utf8) ?? ""
                    let payloadData = record.payload.base64EncodedString()
                    
                    records.append([
                        "type": recordType,
                        "payload": payloadData
                    ])
                }
                ndefMessages.append([
                    "records": records
                ])
            }
            self.notifyListeners("nfcTag", data: ["messages": ndefMessages])
        }

        reader.onError = { error in
            if let nfcError = error as? NFCReaderError {
                if nfcError.code != .readerSessionInvalidationErrorUserCanceled {
                    self.notifyListeners("nfcError", data: ["error": nfcError.localizedDescription])
                }
            }
        }

        reader.startScanning()
        call.resolve()
    }

    @objc func writeNDEF(_ call: CAPPluginCall) {
        print("writeNDEF called")

        guard let recordsData = call.getArray("records") as? [[String: Any]] else {
            call.reject("Records are required")
            return
        }

        var ndefRecords = [NFCNDEFPayload]()
        for recordData in recordsData {
            guard let type = recordData["type"] as? String,
                let payload = recordData["payload"] as? [NSNumber],
                let typeData = type.data(using: .utf8)
            else {
                print("Skipping record due to missing or invalid record")
                continue
            }
            
            guard let payloadArray = payload as [NSNumber]? else {
                print("Skipping record due to missing or invalid 'payload' (expected array of numbers)")
                continue
            }
            
            var payloadBytes = [UInt8]()
            for number in payloadArray {
                payloadBytes.append(number.uint8Value)
            }
            let payloadData = Data(payloadBytes)

            let ndefRecord = NFCNDEFPayload(
                format: .nfcWellKnown,
                type: typeData,
                identifier: Data(),
                payload: payloadData
            )
            ndefRecords.append(ndefRecord)
        }

        let ndefMessage = NFCNDEFMessage(records: ndefRecords)

        writer.onWriteSuccess = {
            self.notifyListeners("nfcWriteSuccess", data: ["success": true])
        }

        writer.onError = { error in
            if let nfcError = error as? NFCReaderError {
                if nfcError.code != .readerSessionInvalidationErrorUserCanceled {
                    self.notifyListeners("nfcError", data: ["error": nfcError.localizedDescription])
                }
            }
        }

        writer.startWriting(message: ndefMessage)
        call.resolve()
    }
}
