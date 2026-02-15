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
    CAPPluginMethod(name: "cancelScan", returnType: CAPPluginReturnPromise),
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
        if let preferredMode = call.getString("mode") {
            reader.setPreferredReaderMode(preferredMode)
        } else if call.getBool("forceFull") == true {
            reader.setPreferredReaderMode("full")
        } else if call.getBool("forceCompat") == true {
            reader.setPreferredReaderMode("compat")
        } else if call.getBool("forceNDEF") == true {
            reader.setPreferredReaderMode("ndef")
        }
        reader.onNDEFMessageReceived = { messages, tagInfo in
            var ndefMessages = [[String: Any]]()

            if messages.isEmpty {
                // If no NDEF messages but we have tag info, create a fallback record with the UID
                if let tagInfo = tagInfo, let uid = tagInfo["uid"] as? String {
                    let payloadData = uid.data(using: .utf8)?.base64EncodedString() ?? ""
                    let records = [[
                        "type": "ID",
                        "payload": payloadData
                    ]]
                    ndefMessages.append([
                        "records": records
                    ])
                }
            } else {
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
            }

            var response: [String: Any] = ["messages": ndefMessages]
            if let tagInfo = tagInfo {
                response["tagInfo"] = tagInfo
            }

            self.notifyListeners("nfcTag", data: response)
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

    @objc func cancelScan(_ call: CAPPluginCall) {
        reader.cancelScanning()
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
                let payload = recordData["payload"] as? [NSNumber]
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

            let format: NFCTypeNameFormat
            let typeEncoding: String.Encoding
            if type == "T" || type == "U" {
                format = .nfcWellKnown
                typeEncoding = .utf8
            } else if type.contains("/") {
                format = .media
                typeEncoding = .ascii
            } else {
                format = .nfcExternal
                typeEncoding = .utf8
            }

            guard let typeData = type.data(using: typeEncoding) else {
                print("Skipping record due to unsupported type encoding")
                continue
            }

            let ndefRecord = NFCNDEFPayload(
                format: format,
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
