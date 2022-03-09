import Foundation
import Datable
import Logging
import SwiftQueue
import SwiftHexTools

import Chord
import Socket
import Net
import TransmissionTypes

public class TransmissionConnection: Connection
{
    let id: Int
    var connection: Socket
    var connectLock = DispatchGroup()
    var readLock = DispatchGroup()
    var writeLock = DispatchGroup()
    let log: Logger?
    var buffer: Data = Data()

    public init?(host: String, port: Int, type: ConnectionType = .tcp, logger: Logger? = nil)
    {
        self.log = logger

        switch type
        {
            case .tcp:
                guard let socket = try? Socket.create()
                else
                {
                    log?.error("Failed to create a Linux TransmissionConnection: Socket.create() failed.")
                    print("Failed to create a Linux TransmissionConnection: Socket.create() failed.")
                    return nil
                }
                self.connection = socket
                self.id = Int(socket.socketfd)

                do
                {
                    print("Attempting socket.connect with host: \(host) and port: \(port)")
                    try socket.connect(to: host, port: Int32(port))
                }
                catch
                {
                    log?.error("Failed to create a Linux transmission connection. socket.connect() failed: \(error)")
                    print("socket.connect() failed:")
                    print(error)
                    return nil
                }
            case .udp:
                // FIXME
                return nil
        }
    }

    public init(socket: Socket, logger: Logger? = nil)
    {
        self.connection = socket
        self.id = Int(socket.socketfd)
        self.log = nil
    }

    public func read(size: Int) -> Data?
    {
//        print("TransmissionLinux read called: \(#file), \(#line)")
        readLock.enter()

        if size == 0
        {
            if let log = self.log {log.error("transmission read size was zero")}
            readLock.leave()
            return nil
        }

        if size <= buffer.count
        {
            let result = Data(buffer[0..<size])
            buffer = Data(buffer[size..<buffer.count])

            readLock.leave()
            //print("\nTransmission read returned result: \(result.hex), buffer: \(buffer.hex)\n")
            return result
        }

        guard let data = networkRead(size: size) else
        {
            if let log = self.log {log.error("transmission read's network read failed")}
            readLock.leave()
            return nil
        }

        buffer.append(data)

        guard size <= buffer.count else
        {
            if let log = self.log {log.error("transmission read asked for more bytes than available in the buffer")}
            readLock.leave()
            return nil
        }

        let result = Data(buffer[0..<size])
        buffer = Data(buffer[size..<buffer.count])

        readLock.leave()
        //print("\nTransmission read returned result: \(result.hex), buffer: \(buffer.hex)\n")
        return result
    }

    public func read(maxSize: Int) -> Data?
    {
//        print("TransmissionLinux read called: \(#file), \(#line)")
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

            do
            {
                data = Data(repeating: 0, count: maxSize)
                let bytesRead = try self.connection.read(into: &data!)
                if (bytesRead < maxSize)
                {
                    data = Data(data![..<bytesRead])
                }
            }
            catch
            {
                readLock.leave()
                return nil
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
        maybeLog(message: "TransmissionLinux:TransmissionConnection.networkRead(size: \(size))", logger: self.log)
        while self.buffer.count < size
        {
            do
            {
                maybeLog(message: "TransmissionLinux:TransmissionConnection.networkRead - buffer count before network read\(self.buffer.count)", logger: self.log)
                let bytesRead = try self.connection.read(into: &self.buffer)
                maybeLog(message: "TransmissionLinux:TransmissionConnection.networkRead - actual read size \(bytesRead)", logger: self.log)
                maybeLog(message: "TransmissionLinux:TransmissionConnection.networkRead - buffer count after network read \(self.buffer.count)", logger: self.log)
            }
            catch
            {
                return nil
            }
        }

        maybeLog(message: "TransmissionLinux:TransmissionConnection.networkRead - buffer count after loop \(self.buffer.count)", logger: self.log)

        let data = Data(self.buffer[..<size])
        self.buffer = Data(self.buffer[size...])

        return data
    }

    func networkWrite(data: Data) -> Bool
    {
        do
        {
            try self.connection.write(from: data)
            return true
        }
        catch
        {
            return false
        }
    }

    public func close()
    {
        self.connection.close()
    }
}

public func maybeLog(message: String, logger: Logger? = nil) {
    if logger != nil {
        logger!.debug("\(message)")
    } else {
        print(message)
    }
}
