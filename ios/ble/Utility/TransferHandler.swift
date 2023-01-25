import Foundation

@available(iOS 13.0, *)
class TransferHandler {
    var data: Data?
    private var currentState: States = States.UnInitialised
    private var responseStartTimeInMillis: UInt64 = 0
    private var chunker: Chunker?
    private var chunkCounter = 0
    private var isRetryFrame = false
    
    public static var shared = TransferHandler()
    
    func initialize(initdData: Data) {
        data = initdData
    }
    
    func sendMessage(message: imessage) {
        handleMessage(msg: message)
    }
    deinit{
        print("deinit happend in transferh")
    }
    private func handleMessage(msg: imessage) {
        if msg.msgType == .INIT_RESPONSE_TRANSFER {
            var responseData = msg.data!
            print("Total response size of data",responseData.count)
            // TODO: Init chunker to use the exchanged MTU size
            chunker = Chunker(chunkData: responseData, mtuSize: BLEConstants.DEFAULT_CHUNK_SIZE)
            print("MTU found to be", BLEConstants.DEFAULT_CHUNK_SIZE)
            currentState = States.ResponseSizeWritePending
            sendMessage(message: imessage(msgType: .RESPONSE_SIZE_WRITE_PENDING, data: responseData, dataSize: responseData.count))
        }
        else if msg.msgType == .RESPONSE_SIZE_WRITE_PENDING {
            sendResponseSize(size: msg.dataSize!)
        }
        else if msg.msgType == .RESPONSE_SIZE_WRITE_SUCCESS {
            responseStartTimeInMillis = Utils.currentTimeInMilliSeconds()
            currentState = States.ResponseSizeWriteSuccess
            initResponseChunkSend()
        } else if msg.msgType == .RESPONSE_SIZE_WRITE_FAILED {
            print("failed to write response size")
            currentState = States.ResponseWriteFailed
        } else if msg.msgType == .INIT_RESPONSE_CHUNK_TRANSFER {
            currentState = .ResponseWritePending
            sendResponseChunk()
        }
        else if msg.msgType == .READ_TRANSMISSION_REPORT {
            currentState = States.WaitingForTransferReport
            requestTransmissionReport()
        }
        else if msg.msgType == .HANDLE_TRANSMISSION_REPORT {
            currentState = States.HandlingTransferReport
            var handleTransmissionReportMessage = msg.data
            handleTransmissionReport(report: handleTransmissionReportMessage!)
        } else if msg.msgType == .RESPONSE_CHUNK_WRITE_SUCCESS {
            // send retry resp chunk or resp chunk
            if (isRetryFrame) {
                // sendRetryRespChunk()
            } else {
                sendResponseChunk()
                chunkCounter+=1
            }
        } else if msg.msgType == .RESPONSE_CHUNK_WRITE_FAILURE {
            sendMessage(message: imessage(msgType: .RESPONSE_CHUNK_WRITE_FAILURE, data: msg.data))
        } else if msg.msgType == .RESPONSE_TRANSFER_COMPLETE {
            currentState = States.TransferComplete
            sendMessage(message: imessage(msgType: .READ_TRANSMISSION_REPORT))
        } else if msg.msgType == .RESPONSE_TRANSFER_FAILED {
            // handle failures?
            currentState = States.ResponseWriteFailed
            handleTransmissionReport(report: msg.data!)
        } else if msg.msgType == .INIT_RETRY_TRANSFER {
            isRetryFrame = true
            // create a RetryChunker object
            // sendRetryRespChunk()
        }
        else {
            print("out of scope")
        }
    }
    
    private func sendRetryRespChunk(missingChunks: [Int]) {
        for chunkIndex in missingChunks {
            let chunk = chunker?.getChunkWithIndex(index: chunkIndex)
            Central.shared.write(serviceUuid: Peripheral.SERVICE_UUID, charUUID: NetworkCharNums.responseCharacteristic, data: chunk!)
            // checks if no more missing chunks exist on verifier
        }
        sendMessage(message: imessage(msgType: .READ_TRANSMISSION_REPORT, data: nil))
    }
    private func requestTransmissionReport() {
        var notifyObj: Data
        Central.shared.write(serviceUuid: BLEConstants.SERVICE_UUID, charUUID: NetworkCharNums.semaphoreCharacteristic, data: withUnsafeBytes(of: 1.littleEndian) { Data($0) })
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: "HANDLE_TRANSMISSION_REPORT"), object: nil, queue: nil) { [unowned self] notification in
            print("Handling notification for \(notification.name.rawValue)")
            if let notifyObj = notification.userInfo?["report"] as? Data {
                sendMessage(message: imessage(msgType: .RESPONSE_TRANSFER_FAILED, data: notifyObj))
            } else {
                print("weird reason!!")
            }
        }

    }
    
    private func handleTransmissionReport(report: Data) {
        let r = TransferReport(bytes: report)
        print(" got the transfer report type \(r.type)")
        print("missing pages: ", r.totalPages)
        
        if (r.type == .SUCCESS) {
            currentState = States.TransferVerified
            EventEmitter.sharedInstance.emitNearbyMessage(event: "send-vc:response", data: "RECEIVED")
            print("Emitting send-vc:response RECEIVED message")
        } else if r.type == .MISSING_CHUNKS {
            currentState = .PartiallyTransferred
            sendRetryRespChunk(missingChunks: r.missingSequences!)
        }
    }
    
    private func sendResponseSize(size: Int) {
        // TODO: Send a stringified number in a byte array
        let decimalString = String(size)
        let d = decimalString.data(using: .utf8)
        print(d!)
        Central.shared.write(serviceUuid: Peripheral.SERVICE_UUID, charUUID: NetworkCharNums.responseSizeCharacteristic, data: d!)
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: "RESPONSE_SIZE_WRITE_SUCCESS"), object: nil, queue: nil) { [unowned self] notification in
            print("Handling notification for \(notification.name.rawValue)")
            sendMessage(message: imessage(msgType: .RESPONSE_SIZE_WRITE_SUCCESS, data: data))
        }
    }
    
    private func initResponseChunkSend() {
        print("initResponseChunkSend")
        sendMessage(message: imessage(msgType: .INIT_RESPONSE_CHUNK_TRANSFER, data: data, dataSize: data?.count))
    }
    
    private func sendResponseChunk() {
        if let chunker = chunker {
            if chunker.isComplete() {
                print("Data send complete")
                sendMessage(message: imessage(msgType: .READ_TRANSMISSION_REPORT))
                return
            }
            
            var done = false
            while !done {
                let chunk = chunker.next()
                if chunk.isEmpty {
                    done = true
                    sendMessage(message: imessage(msgType: .INIT_RESPONSE_CHUNK_TRANSFER, data: data, dataSize: data?.count))
                }
                else {
                    Central.shared.write(serviceUuid: Peripheral.SERVICE_UUID, charUUID: NetworkCharNums.responseCharacteristic, data: chunk)
                }
                
            }
        }
    }
}

enum TransferMessageTypes {
    case INIT_RESPONSE_TRANSFER
    case RESPONSE_SIZE_WRITE_PENDING
    case RESPONSE_SIZE_WRITE_SUCCESS
    case RESPONSE_SIZE_WRITE_FAILED
    case INIT_RESPONSE_CHUNK_TRANSFER
    case CHUNK_WRITE_TO_REMOTE_STATUS_UPDATED
    case RESPONSE_CHUNK_WRITE_SUCCESS
    case RESPONSE_CHUNK_WRITE_FAILURE
    case RESPONSE_TRANSFER_COMPLETE
    case RESPONSE_TRANSFER_FAILED
    
    case READ_TRANSMISSION_REPORT
    case HANDLE_TRANSMISSION_REPORT
    
    case INIT_RETRY_TRANSFER
}

struct imessage {
    var msgType: TransferMessageTypes
    var data: Data?
    var dataSize: Int?
}

enum  States {
    case UnInitialised
    case ResponseSizeWritePending
    case ResponseSizeWriteSuccess
    case ResponseSizeWriteFailed
    case ResponseWritePending
    case ResponseWriteFailed
    case TransferComplete
    case WaitingForTransferReport
    case HandlingTransferReport
    case TransferVerified
    case PartiallyTransferred
}

enum SemaphoreMarker: Int {
    case UnInitialised = 0
    case RequestReport = 1
    case Error = 2
}


