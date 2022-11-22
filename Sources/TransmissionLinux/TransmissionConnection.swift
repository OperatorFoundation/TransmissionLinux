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
            log?.debug("TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.")
            readLock.leave()
            return result
        }

        guard let data = networkRead(size: size) else
        {
            readLock.leave()
            return nil
        }
        
        guard data.count > 0 else
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
        log?.debug("TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.")
        readLock.leave()
        
        return result
    }

    public func read(maxSize: Int) -> Data?
    {
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

            log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - returned \(result.count) bytes")
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
                    let bytesRead = try tcpConnection.read(into: &data!)
                    
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
                    log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error: There are no valid connections")
                    readLock.leave()
                    return nil
                }
            }
            catch
            {
                log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error trying to read from the network: \(error)")
                readLock.leave()
                return nil
            }

            guard let bytes = data else
            {
                log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error received a nil response when attempting to read from the network.")
                readLock.leave()
                return nil
            }
            
            guard bytes.count > 0 else
            {
                log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error received an empty response when attempting to read from the network.")
                readLock.leave()
                return nil
            }

            buffer.append(bytes)
            let targetSize = min(maxSize, buffer.count)
            let result = Data(buffer[0..<targetSize])
            buffer = Data(buffer[targetSize..<buffer.count])

            log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - returned \(result.count) bytes")
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
        
        log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> write(string:), success: \(success)")
        return success
    }
    
    public func write(data: Data) -> Bool
    {
        writeLock.enter()
        let success = networkWrite(data: data)
        writeLock.leave()
        
        log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> write(data:), success: \(success)")
        return success
    }

    public func readWithLengthPrefix(prefixSizeInBits: Int) -> Data?
    {
        print("TransmissionLinux: readWithLengthPrefix entering lock...")
        readLock.enter()
        print("TransmissionLinux: entered readWithLengthPrefix ")

        guard let result = TransmissionTypes.readWithLengthPrefix(prefixSizeInBits: prefixSizeInBits, connection: self) else
        {
            readLock.leave()
            return nil
        }

        print("TransmissionLinux: TransmissionConnection.readWithLengthPrefix -> returned \(result.count) bytes.")
        readLock.leave()
        return result
    }

    public func writeWithLengthPrefix(data: Data, prefixSizeInBits: Int) -> Bool
    {
        writeLock.enter()

        let result = TransmissionTypes.writeWithLengthPrefix(data: data, prefixSizeInBits: prefixSizeInBits, connection: self)

        writeLock.leave()
        return result
    }

    public func identifier() -> Int
    {
        return self.id
    }

    private func networkRead(size: Int) -> Data?
    {
        guard size > 0 else
        {
            log?.error("TransmissionLinux: TransmissionConnection - network read requested for a read size of 0")
            return nil
        }
        
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
                    log?.error("TransmissionLinux: TransmissionConnection.networkRead - Error: There are no valid connections")
                    return nil
                }
            }
            catch
            {
                log?.error("TransmissionLinux: TransmissionConnection.networkRead - Error: \(error)")
                return nil
            }
        }
        
        return networkBuffer
    }

    private func networkWrite(data: Data) -> Bool
    {
        do
        {
            if let tcpConnection = tcpConnection
            {
                let byteCountWritten = try tcpConnection.write(from: data)
                
                log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> tcp connection wrote \(byteCountWritten) bytes")
                return true
            }
            else if let udpConnection = udpConnection, let udpAddress = udpOutgoingAddress
            {
                let byteCountWritten = try udpConnection.write(from: data, to: udpAddress)
                
                log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> udp connection wrote \(byteCountWritten) bytes")
                return true
            }
            else
            {
                log?.debug("TransmissionLinux: TransmissionConnection.networkWrite - Error: There are no valid connections")
                return false
            }
            
        }
        catch
        {
            log?.debug("TransmissionLinux: TransmissionConnection.networkWrite - Error: \(error)")
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
