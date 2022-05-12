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
    let log: Logger?
    
    public var udpOutgoingAddress: Socket.Address?
    
    var tcpConnection: Socket?
    var udpConnection: Socket?
    var udpIncomingPort: Int? = nil
    
    var connectLock = DispatchGroup()
    var readLock = DispatchGroup()
    var writeLock = DispatchGroup()
    
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
                    log?.error("TransmissionLinux: Failed to create a Linux TCP TransmissionConnection: Socket.create() failed.")
                    return nil
                }
                self.tcpConnection = socket
                self.id = Int(socket.socketfd)
                
                do
                {
                    if tcpConnection != nil
                    {
                        try tcpConnection!.connect(to: host, port: Int32(port))
                    }
                    else
                    {
                        log?.error("TransmissionLinux: Failed to create a Linux TransmissionConnection.")
                        return nil
                    }
                }
                catch
                {
                    log?.error("TransmissionLinux: Failed to create a Linux transmission connection. socket.connect() failed: \(error)")
                    return nil
                }
                
            case .udp:
                guard let socket = try? Socket.create(family: .inet, type: .datagram, proto: .udp)
                else
                {
                    log?.error("TransmissionLinux: Failed to create a Linux UDP TransmissionConnection: Socket.create() failed.")
                    return nil
                }
                self.udpConnection = socket
                self.udpOutgoingAddress = Socket.createAddress(for: host, on: Int32(port))
                self.id = Int(socket.socketfd)
        }
    }

    public init(socket: Socket, type: ConnectionType = .tcp, logger: Logger? = nil)
    {
        if type == .tcp
        {
            self.tcpConnection = socket
        }
        else
        {
            self.udpConnection = socket
        }
        
        self.id = Int(socket.socketfd)
        self.log = logger
    }
    
    // UDP Server init
    public init(socket: Socket, port: Int, logger: Logger? = nil)
    {
        self.udpConnection = socket
        self.udpIncomingPort = port
        self.id = Int(socket.socketfd)
        self.log = logger
    }

    public func read(size: Int) -> Data?
    {
        readLock.enter()

        if size == 0
        {
            log?.error("TransmissionLinux: requested read size was zero")
            readLock.leave()
            return nil
        }

        if size <= buffer.count
        {
            let result = Data(buffer[0..<size])
            buffer = Data(buffer[size..<buffer.count])
            
            maybeLog(message: "TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.", logger: self.log)
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
        
        maybeLog(message: "TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.", logger: self.log)
        readLock.leave()
        return result
    }

    public func read(maxSize: Int) -> Data?
    {
        print("TransmissionLinux: Entering readLock")
        readLock.enter()
        print("TransmissionLinux: readLock entered")

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

            maybeLog(message: "TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - returned \(result.count) bytes", logger: self.log)
            readLock.leave()
            return result
        }
        else
        {
            // Buffer is empty, so we need to do a network read
            var data: Data?
            
            do
            {
                data = Data()
                
                if let tcpConnection = tcpConnection
                {
                    print("TransmissionLinux: Calling tcpConnection.read")
                    let bytesRead = try tcpConnection.read(into: &data!)
                    print("TransmissionLinux: Returned from tcpConnection.read with \(bytesRead) bytes")
                    
                    if (bytesRead < maxSize)
                    {
                        data = Data(data![..<bytesRead])
                    }
                }
                else if let udpConnection = udpConnection
                {
                    let (bytesRead, _) = try udpConnection.readDatagram(into: &data!)
                    
                    if (bytesRead < maxSize)
                    {
                        data = Data(data![..<bytesRead])
                    }
                }
                else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error: There are no valid connections", logger: self.log)
                    readLock.leave()
                    return nil
                }
            }
            catch
            {
                maybeLog(message: "TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error trying to read from the network: \(error)", logger: self.log)
                readLock.leave()
                return nil
            }

            guard let bytes = data else
            {
                maybeLog(message: "TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error received a nil response when attempting to read from the network.", logger: self.log)
                readLock.leave()
                return nil
            }
            
            guard bytes.count > 0 else
            {
                maybeLog(message: "TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error received an empty response when attempting to read from the network.", logger: self.log)
                readLock.leave()
                return nil
            }

            buffer.append(bytes)
            let targetSize = min(maxSize, buffer.count)
            let result = Data(buffer[0..<targetSize])
            buffer = Data(buffer[targetSize..<buffer.count])

            maybeLog(message: "TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - returned \(result.count) bytes", logger: self.log)
            readLock.leave()
            return result
        }
    }


    public func write(string: String) -> Bool
    {
        writeLock.enter()
        let data = string.data
        let success = write(data: data)
        writeLock.leave()
        
        maybeLog(message: "TransmissionLinux: TransmissionConnection.networkWrite -> write(string:), success: \(success)", logger: self.log)
        return success
    }
    
    public func write(data: Data) -> Bool
    {
        writeLock.enter()
        let success = networkWrite(data: data)
        writeLock.leave()

        maybeLog(message: "TransmissionLinux: TransmissionConnection.networkWrite -> write(data:), success: \(success)", logger: self.log)
        return success
    }

    public func readWithLengthPrefix(prefixSizeInBits: Int) -> Data?
    {
        readLock.enter()

        var maybeLength: Int? = nil
        var maybeExtraData: Data? = nil
        
        let prefixSize = prefixSizeInBits/8
        
        switch prefixSizeInBits
        {
            case 8:
                guard let data = networkRead(size: prefixSize) else
                {
                    readLock.leave()
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - networkRead(size: 8) returned null.", logger: self.log)
                    return nil
                }
                
                let lengthData = data[..<prefixSize]
                maybeExtraData = data[prefixSize...]
                
                guard let boundedLength = UInt8(maybeNetworkData: lengthData) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix(8) - failed to get the bounded length.", logger: self.log)
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
                
            case 16:
                guard let data = networkRead(size: prefixSize) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - networkRead(size: 16) returned null.", logger: self.log)
                    readLock.leave()
                    return nil
                }

                let lengthData = data[..<prefixSize]
                maybeExtraData = data[prefixSize...]
                
                guard let boundedLength = UInt16(maybeNetworkData: lengthData) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix(16) - failed to get the bounded length.", logger: self.log)
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            case 32:
                guard let data = networkRead(size: prefixSize) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - networkRead(size: 32) returned null.", logger: self.log)
                    readLock.leave()
                    return nil
                }
                
                let lengthData = data[..<prefixSize]
                maybeExtraData = data[prefixSize...]
                
                guard let boundedLength = UInt32(maybeNetworkData: lengthData) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix(32) - failed to get the bounded length.", logger: self.log)
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            case 64:
                guard let data = networkRead(size: prefixSize) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - networkRead(size: 64) returned null.", logger: self.log)
                    readLock.leave()
                    return nil
                }
                
                let lengthData = data[..<prefixSize]
                maybeExtraData = data[prefixSize...]

                guard let boundedLength = UInt64(maybeNetworkData: lengthData) else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix(64) - failed to get the bounded length.", logger: self.log)
                    readLock.leave()
                    return nil
                }

                maybeLength = Int(boundedLength)
            default:
                maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - \(prefixSizeInBits) is invalid.", logger: self.log)
                readLock.leave()
                return nil
        }

        guard let length = maybeLength else
        {
            maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - failed to determine the correct length.", logger: self.log)
            readLock.leave()
            return nil
        }
                
        if let extraData = maybeExtraData, !extraData.isEmpty
        {
            self.buffer.append(extraData)
        }
        
        while buffer.count < length
        {
            guard let data = networkRead(size: length - buffer.count) else
            {
                maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix - networkRead(size: \(length) - \(buffer.count)) returned nil.", logger: self.log)
                readLock.leave()
                return nil
            }
            
            buffer.append(data)
        }
        
        let result = Data(buffer[..<length])
        buffer = Data(buffer[length...])
        
        maybeLog(message: "TransmissionLinux: TransmissionConnection.readWithLengthPrefix -> returned \(result.count) bytes.", logger: self.log)
        readLock.leave()
        return result
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

    private func networkRead(size: Int) -> Data?
    {
        var networkBuffer = Data()
        
        while networkBuffer.count < size
        {
            do
            {
                if let tcpConnection = tcpConnection
                {
                    let bytesRead = try tcpConnection.read(into: &networkBuffer)
                    
                    if bytesRead == 0 && tcpConnection.remoteConnectionClosed
                    {
                        return nil
                    }
                }
                else if let udpConnection = udpConnection
                {
                    if let udpPort = udpIncomingPort
                    {
                        let (bytesRead, address) = try udpConnection.listen(forMessage: &networkBuffer, on: udpPort)
                        
                        if udpOutgoingAddress == nil
                        {
                            udpOutgoingAddress = address
                        }
                        
                        if bytesRead == 0 && udpConnection.remoteConnectionClosed
                        {
                            return nil
                        }
                    }
                    else
                    {
                        let (bytesRead, address) = try udpConnection.readDatagram(into: &networkBuffer)
                        
                        if udpOutgoingAddress == nil
                        {
                            udpOutgoingAddress = address
                        }
                        
                        if bytesRead == 0 && udpConnection.remoteConnectionClosed
                        {
                            return nil
                        }
                    }
                    
                }
                else
                {
                    maybeLog(message: "TransmissionLinux: TransmissionConnection.networkRead - Error: There are no valid connections", logger: self.log)
                    return nil
                }
                
            }
            catch
            {
                maybeLog(message: "TransmissionLinux: TransmissionConnection.networkRead - Error: \(error)", logger: self.log)
                return nil
            }
        }
        
        // maybeLog(message: "TransmissionLinux: TransmissionConnection.networkRead(size: \(size)) -> returned \(networkBuffer.count) bytes.", logger: self.log)
        return networkBuffer
    }

    private func networkWrite(data: Data) -> Bool
    {
        do
        {
            if let tcpConnection = tcpConnection
            {
                let byteCountWritten = try tcpConnection.write(from: data)
                
                maybeLog(message: "TransmissionLinux: TransmissionConnection.networkWrite -> tcp connection wrote \(byteCountWritten) bytes", logger: self.log)
                return true
            }
            else if let udpConnection = udpConnection, let udpAddress = udpOutgoingAddress
            {
                let byteCountWritten = try udpConnection.write(from: data, to: udpAddress)
                
                maybeLog(message: "TransmissionLinux: TransmissionConnection.networkWrite -> udp connection wrote \(byteCountWritten) bytes", logger: self.log)
                return true
            }
            else
            {
                maybeLog(message: "TransmissionLinux: TransmissionConnection.networkWrite - Error: There are no valid connections", logger: self.log)
                return false
            }
            
        }
        catch
        {
            maybeLog(message: "TransmissionLinux: TransmissionConnection.networkWrite - Error: \(error)", logger: self.log)
            return false
        }
    }

    public func close()
    {
        if let tcpConnection = tcpConnection
        {
            tcpConnection.close()
        }
        else if let udpConnection = udpConnection
        {
            udpConnection.close()
        }
        
    }
}

public func maybeLog(message: String, logger: Logger? = nil) {
    if logger != nil {
        logger!.debug("\(message)")
    } else {
        print(message)
    }
}
