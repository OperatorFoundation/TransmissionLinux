import Foundation
import Datable
import Transport
import Logging
import SwiftQueue

import Chord
import Socket
import Net

public class TransmissionConnection: Connection
{
    let id: Int
    var connection: NetworkConnection
    var connectLock = DispatchGroup()
    var readLock = DispatchGroup()
    var writeLock = DispatchGroup()
    let log: Logger?
    let states: Queue<Bool> = Queue<Bool>()

    var buffer: Data = Data()

    public init?(host: String, port: Int, type: ConnectionType = .tcp, logger: Logger? = nil)
    {
        self.log = logger

        switch type
        {
            case .tcp:
                guard let socket = try? Socket.create() else {return nil}
                self.connection = .socket(socket)
                self.id = Int(socket.socketfd)

                do
                {
                    try socket.connect(to: host, port: Int32(port))
                }
                catch
                {
                    return nil
                }
            case .udp:
                // FIXME
                return nil
        }
    }

    public required init?(transport: Transport.Connection, logger: Logger? = nil)
    {
        self.log = logger
        maybeLog(message: "Initializing Transmission connection", logger: self.log)

        self.id = Int.random(in: 0..<Int.max)

        var mutableTransport = transport
        self.connection = .transport(mutableTransport)
        mutableTransport.stateUpdateHandler = self.handleState
        mutableTransport.start(queue: .global())

        guard let success = self.states.dequeue() else {return nil}
        guard success else {return nil}
    }

    public init(socket: Socket)
    {
        self.connection = .socket(socket)
        self.id = Int(socket.socketfd)
        self.log = nil
    }

    func handleState(state: NWConnection.State)
    {
        connectLock.wait()

        switch state
        {
            case .ready:
                self.states.enqueue(true)
                return
            case .cancelled:
                self.states.enqueue(false)
                self.failConnect()
                return
            case .failed(_):
                self.states.enqueue(false)
                self.failConnect()
                return
            case .waiting(_):
                self.states.enqueue(false)
                self.failConnect()
                return
            default:
                return
        }
    }

    func failConnect()
    {
        maybeLog(message: "Failed to make a Transmission connection", logger: self.log)

        switch self.connection
        {
            case .socket(let socket):
                socket.close()
                break
            case .transport(var connection):
                connection.stateUpdateHandler = nil
                connection.cancel()
                break
        }
    }

    public func read(size: Int) -> Data?
    {
        print("TransmissionLinux read called: \(#file), \(#line)")
        readLock.enter()

        if size == 0
        {
            readLock.leave()
            return nil
        }

        if size <= buffer.count
        {
            let result = Data(buffer[0..<size])
            buffer = Data(buffer[size..<buffer.count])

            readLock.leave()
            return result
        }

        guard let data = networkRead(size: size) else
        {
            readLock.leave()
            return nil
        }

        buffer.append(data)

        guard size <= buffer.count else
        {
            readLock.leave()
            return nil
        }

        let result = Data(buffer[0..<size])
        buffer = Data(buffer[size..<buffer.count])

        readLock.leave()
        return result
    }

    public func read(maxSize: Int) -> Data?
    {
        print("TransmissionLinux read called: \(#file), \(#line)")
        readLock.enter()

        if maxSize == 0
        {
            readLock.leave()
            return nil
        }

        let size = maxSize <= buffer.count ? maxSize : buffer.count

        if size > 0
        {
            let result = Data(buffer[0..<size])
            buffer = Data(buffer[size..<buffer.count])

            readLock.leave()
            return result
        }
        else
        {
            // Buffer is empty, so we need to do a network read

            var data: Data?

            switch self.connection
            {
                case .socket(let socket):
                    do
                    {
                        data = Data(repeating: 0, count: maxSize)
                        let bytesRead = try socket.read(into: &data!)
                        if (bytesRead < size)
                        {
                            data = Data(data![..<bytesRead])
                        }
                    }
                    catch
                    {
                        readLock.leave()
                        return nil
                    }

                case .transport(let transport):
                    let transportLock = DispatchGroup()
                    transportLock.enter()
                    transport.receive(minimumIncompleteLength: 1, maximumLength: maxSize)
                    {
                        maybeData, maybeContext, isComplete, maybeError in

                        guard let transportData = maybeData else
                        {
                            data = nil
                            return
                        }

                        guard maybeError == nil else
                        {
                            data = nil
                            return
                        }

                        data = transportData
                    }
            }

            guard let bytes = data else
            {
                readLock.leave()
                return nil
            }

            buffer.append(bytes)

            let targetSize = min(maxSize, buffer.count)

            let result = Data(buffer[0..<targetSize])
            buffer = Data(buffer[targetSize..<buffer.count])

            readLock.leave()
            return result
        }
    }


    public func write(string: String) -> Bool
    {
        print("TransmissionLinux write called: \(#file), \(#line)")

        writeLock.enter()

        let data = string.data

        writeLock.leave()
        return write(data: data)
    }
    
    public func write(data: Data) -> Bool
    {
        print("TransmissionLinux write called: \(#file), \(#line)")

        writeLock.enter()

        let success = networkWrite(data: data)

        writeLock.leave()

        return success
    }

    public func readWithLengthPrefix(prefixSizeInBits: Int) -> Data?
    {
        readLock.enter()

        var maybeLength: Int? = nil

        switch prefixSizeInBits
        {
            case 8:
                guard let lengthData = networkRead(size: prefixSizeInBits/8) else
                {
                    readLock.leave()
                    return nil
                }

                guard let boundedLength = UInt8(maybeNetworkData: lengthData) else
                {
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            case 16:
                guard let lengthData = networkRead(size: prefixSizeInBits/8) else
                {
                    readLock.leave()
                    return nil
                }

                guard let boundedLength = UInt16(maybeNetworkData: lengthData) else
                {
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            case 32:
                guard let lengthData = networkRead(size: prefixSizeInBits/8) else
                {
                    readLock.leave()
                    return nil
                }

                guard let boundedLength = UInt32(maybeNetworkData: lengthData) else
                {
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            case 64:
                guard let lengthData = networkRead(size: prefixSizeInBits/8) else
                {
                    readLock.leave()
                    return nil
                }

                guard let boundedLength = UInt64(maybeNetworkData: lengthData) else
                {
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            default:
                readLock.leave()
                return nil
        }

        guard let length = maybeLength else
        {
            readLock.leave()
            return nil
        }

        guard let data = networkRead(size: length) else
        {
            readLock.leave()
            return nil
        }

        return data
    }

    public func writeWithLengthPrefix(data: Data, prefixSizeInBits: Int) -> Bool
    {
        writeLock.enter()

        let length = data.count

        var maybeLengthData: Data? = nil

        switch prefixSizeInBits
        {
            case 8:
                let boundedLength = UInt8(length)
                maybeLengthData = boundedLength.maybeNetworkData
            case 16:
                let boundedLength = UInt16(length)
                maybeLengthData = boundedLength.maybeNetworkData
            case 32:
                let boundedLength = UInt32(length)
                maybeLengthData = boundedLength.maybeNetworkData
            case 64:
                let boundedLength = UInt64(length)
                maybeLengthData = boundedLength.maybeNetworkData
            default:
                maybeLengthData = nil
        }

        guard let lengthData = maybeLengthData else
        {
            writeLock.leave()
            return false
        }

        let atomicData = lengthData + data
        let success = networkWrite(data: atomicData)
        writeLock.leave()
        return success
    }
    
    public func identifier() -> Int
    {
        return self.id
    }

    func networkRead(size: Int) -> Data?
    {
        var data: Data?

        switch self.connection
        {
            case .socket(let socket):
                do
                {
                    data = Data(repeating: 0, count: size)
                    let bytesRead = try socket.read(into: &data!)
                    if (bytesRead < size)
                    {
                        data = Data(data![..<bytesRead])
                    }
                }
                catch
                {
                    data = nil
                    break
                }

            case .transport(let transport):
                let transportLock = DispatchGroup()
                transportLock.enter()
                transport.receive(minimumIncompleteLength: size, maximumLength: size)
                {
                    maybeData, maybeContext, isComplete, maybeError in

                    guard let transportData = maybeData else
                    {
                        data = nil
                        return
                    }

                    guard maybeError == nil else
                    {
                        data = nil
                        return
                    }

                    data = transportData
                }
        }

        return data
    }

    func networkWrite(data: Data) -> Bool
    {
        var success = false
        switch self.connection
        {
            case .socket(let socket):
                do
                {
                    try socket.write(from: data)
                    success = true
                    break
                }
                catch
                {
                    success = false
                    break
                }
            case .transport(let transport):
                let lock = DispatchGroup()
                lock.enter()
                transport.send(content: data, contentContext: .defaultMessage, isComplete: false, completion: NWConnection.SendCompletion.contentProcessed(
                    {
                        error in

                        guard error == nil else
                        {
                            success = false
                            lock.leave()
                            return
                        }

                        success = true
                        lock.leave()
                        return
                    }))
                lock.wait()
        }

        return success
    }
}

enum NetworkConnection
{
    case socket(Socket)
    case transport(Transport.Connection)
}

public func maybeLog(message: String, logger: Logger? = nil) {
    if logger != nil {
        logger!.debug("\(message)")
    } else {
        print(message)
    }
}
