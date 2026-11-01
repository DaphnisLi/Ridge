import AudioToolbox
import CoreAudio
import Foundation

/// 单 App Process Tap 路由：静音原路径 → 增益后写回默认输出。
/// 仅在 macOS 14.2+ 且具备屏幕录制权限时可用；失败必须 fail-open（销毁后声音恢复直通）。
@available(macOS 14.2, *)
final class SoundAppVolumeRoute {
    private struct Parameters {
        var volume: Float32 = 1
        var muted: Int32 = 0
    }

    let key: String
    private(set) var processObjectIDs: [AudioObjectID]
    private var outputDeviceUID: String

    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let parameters = UnsafeMutablePointer<Parameters>.allocate(capacity: 1)
    private let ioQueue: DispatchQueue

    static let aggregateUIDPrefix = "app.daphnis.Ridge.sound.agg."

    var volume: Float {
        get { Float(parameters.pointee.volume) }
        set { parameters.pointee.volume = Float32(min(1, max(0, newValue))) }
    }

    var isMuted: Bool {
        get { parameters.pointee.muted != 0 }
        set { parameters.pointee.muted = newValue ? 1 : 0 }
    }

    var isRunning: Bool { ioProcID != nil }

    init(key: String, processObjectIDs: [AudioObjectID], outputDeviceUID: String) {
        self.key = key
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        parameters.initialize(to: Parameters())
        ioQueue = DispatchQueue(label: "app.daphnis.Ridge.sound.io.\(key)", qos: .userInteractive)
    }

    deinit {
        stop()
        parameters.deinitialize(count: 1)
        parameters.deallocate()
    }

    func start() throws {
        guard !isRunning else { return }
        do {
            try createTap()
            try createAggregate()
            try startIO()
            AppLog.info("Sound", "App 音量路由已启动", ["key": key, "processes": processObjectIDs.count])
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    func updateProcesses(_ ids: [AudioObjectID]) throws {
        guard ids != processObjectIDs else { return }
        let was = isRunning
        stop()
        processObjectIDs = ids
        if was { try start() }
    }

    func updateOutputUID(_ uid: String) throws {
        guard uid != outputDeviceUID else { return }
        let was = isRunning
        stop()
        outputDeviceUID = uid
        if was { try start() }
    }

    // MARK: - Build

    private func createTap() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "Ridge Sound – \(key)"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .muted

        var id = AudioObjectID.unknown
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr, id.isValid else {
            throw SoundRouteError.tapFailed(status)
        }
        tapID = id
    }

    private func createAggregate() throws {
        guard let tapUID = CoreAudioProperty.getCFString(object: tapID, kAudioTapPropertyUID) else {
            throw SoundRouteError.missingTapUID
        }
        let uid = Self.aggregateUIDPrefix + UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Ridge Sound \(key)",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var id = AudioObjectID.unknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr, id.isValid else {
            throw SoundRouteError.aggregateFailed(status)
        }
        aggregateID = id
    }

    private func startIO() throws {
        guard var tapFormat: AudioStreamBasicDescription = CoreAudioProperty.get(
            object: tapID,
            kAudioTapPropertyFormat
        ) else {
            throw SoundRouteError.missingFormat
        }
        let streams: [AudioObjectID] = CoreAudioProperty.getArray(
            object: aggregateID,
            kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeOutput
        )
        guard let stream = streams.first,
              var outputFormat: AudioStreamBasicDescription = CoreAudioProperty.get(
                object: stream,
                kAudioStreamPropertyVirtualFormat
              )
        else {
            throw SoundRouteError.missingFormat
        }

        // 目标输出若自带输入，tap buffer 可能排在其后。
        let inputOffset: Int = {
            guard let outID = deviceID(forUID: outputDeviceUID) else { return 0 }
            let inputStreams: [AudioObjectID] = CoreAudioProperty.getArray(
                object: outID,
                kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeInput
            )
            return inputStreams.count
        }()

        let capturedTapFormat = tapFormat
        let capturedOutputFormat = outputFormat
        let params = parameters
        let block: AudioDeviceIOBlock = { _, inInputData, _, outOutputData, _ in
            Self.render(
                input: inInputData,
                inputFormat: capturedTapFormat,
                inputBufferOffset: inputOffset,
                output: outOutputData,
                outputFormat: capturedOutputFormat,
                parameters: params
            )
        }

        var procID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue, block)
        guard status == noErr, let procID else {
            throw SoundRouteError.ioProcFailed(status)
        }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            throw SoundRouteError.ioProcFailed(status)
        }
        ioProcID = procID
    }

    private static func render(
        input: UnsafePointer<AudioBufferList>?,
        inputFormat: AudioStreamBasicDescription,
        inputBufferOffset: Int,
        output: UnsafeMutablePointer<AudioBufferList>?,
        outputFormat: AudioStreamBasicDescription,
        parameters: UnsafeMutablePointer<Parameters>
    ) {
        guard let input, let output else { return }
        let outList = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outList {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        let state = parameters.pointee
        guard state.muted == 0, state.volume > 0 else { return }

        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inChannels = max(1, Int(inputFormat.mChannelsPerFrame))
        let outChannels = max(1, Int(outputFormat.mChannelsPerFrame))
        let inNonInterleaved = (inputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let outNonInterleaved = (outputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let inBuffersNeeded = inNonInterleaved ? inChannels : 1
        guard inList.count >= inputBufferOffset + inBuffersNeeded,
              outList.count >= (outNonInterleaved ? outChannels : 1),
              inputFormat.mBytesPerFrame > 0,
              outputFormat.mBytesPerFrame > 0
        else { return }

        let inFrames = Int(inList[inputBufferOffset].mDataByteSize) / Int(inputFormat.mBytesPerFrame)
        let outFrames = Int(outList[0].mDataByteSize) / Int(outputFormat.mBytesPerFrame)
        let frames = min(inFrames, outFrames)
        guard frames > 0 else { return }

        let gain = state.volume
        for channel in 0..<outChannels {
            let srcChannel = min(channel, inChannels - 1)
            for frame in 0..<frames {
                let sample: Float32 = {
                    if inNonInterleaved {
                        guard let data = inList[inputBufferOffset + srcChannel].mData else { return 0 }
                        return data.assumingMemoryBound(to: Float32.self)[frame]
                    } else {
                        guard let data = inList[inputBufferOffset].mData else { return 0 }
                        return data.assumingMemoryBound(to: Float32.self)[frame * inChannels + srcChannel]
                    }
                }()
                let value = max(-1, min(1, sample * gain))
                if outNonInterleaved {
                    guard let data = outList[channel].mData else { continue }
                    data.assumingMemoryBound(to: Float32.self)[frame] = value
                } else {
                    guard let data = outList[0].mData else { continue }
                    data.assumingMemoryBound(to: Float32.self)[frame * outChannels + channel] = value
                }
            }
        }
    }

    private func deviceID(forUID uid: String) -> AudioObjectID? {
        let devices: [AudioObjectID] = CoreAudioProperty.getArray(
            object: .system,
            kAudioHardwarePropertyDevices
        )
        return devices.first {
            CoreAudioProperty.getCFString(object: $0, kAudioDevicePropertyDeviceUID) == uid
        }
    }

    /// 清理异常退出留下的私有 aggregate。
    static func cleanupOrphans() {
        let devices: [AudioObjectID] = CoreAudioProperty.getArray(
            object: .system,
            kAudioHardwarePropertyDevices
        )
        for id in devices {
            guard let uid = CoreAudioProperty.getCFString(object: id, kAudioDevicePropertyDeviceUID),
                  uid.hasPrefix(aggregateUIDPrefix)
            else { continue }
            AudioHardwareDestroyAggregateDevice(id)
            AppLog.warn("Sound", "清理残留聚合设备", ["uid": uid])
        }
    }
}

enum SoundRouteError: Error, LocalizedError {
    case tapFailed(OSStatus)
    case aggregateFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case missingTapUID
    case missingFormat

    var errorDescription: String? {
        switch self {
        case .tapFailed(let s): return "创建 Process Tap 失败 (\(s))"
        case .aggregateFailed(let s): return "创建聚合设备失败 (\(s))"
        case .ioProcFailed(let s): return "启动 IOProc 失败 (\(s))"
        case .missingTapUID: return "缺少 tap UID"
        case .missingFormat: return "无法读取音频格式"
        }
    }
}
