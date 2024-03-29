import Foundation
import Datable
import Logging
import SwiftQueue
import SwiftHexTools

import Chord
import Socket
import Straw
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
    
    var buffer: UnsafeStraw = UnsafeStraw()

    public init?(host: String, port: Int, type: ConnectionType = .tcp, logger: Logger? = nil)
    {
        self.log = logger
        
        switch type
        {
            case .tcp:
                guard let socket = try? Socket.create()
                else
                {
                    self.log?.debug("TransmissionLinux: Failed to create a Linux TCP TransmissionConnection: Socket.create() failed.")
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
                        self.log?.debug("TransmissionLinux: Failed to create a Linux TransmissionConnection.")
                        return nil
                    }
                }
                catch
                {
                    self.log?.debug("TransmissionLinux: Failed to create a Linux transmission connection. socket.connect() failed: \(error)")
                    return nil
                }
                
            case .udp:
                guard let socket = try? Socket.create(family: .inet, type: .datagram, proto: .udp)
                else
                {
                    self.log?.debug("TransmissionLinux: Failed to create a Linux UDP TransmissionConnection: Socket.create() failed.")
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
            self.log?.debug("TransmissionLinux: requested read size was zero")
            readLock.leave()
            return nil
        }

        if size <= buffer.count
        {
            do
            {
                let result = try self.buffer.read(size: size)
                self.log?.debug("TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.")

                readLock.leave()
                return result
            }
            catch
            {
                readLock.leave()
                return nil
            }
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

        self.buffer.write(data)

        guard size <= buffer.count else
        {
            readLock.leave()
            return nil
        }

        do
        {
            let result = try self.buffer.read(size: size)
            self.log?.debug("TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.")
            readLock.leave()

            return result
        }
        catch
        {
            return nil
        }
    }
    
    public func unsafeRead(size: Int) -> Data?
    {        
        if size == 0
        {
            self.log?.debug("TransmissionLinux: requested read size was zero")
            return nil
        }

        if size <= buffer.count
        {
            do
            {
                let result = try self.buffer.read(size: size)
                self.log?.debug("TransmissionLinux: TransmissionConnection.read(size: \(size)) -> returned \(result.count) bytes.")
                return result
            }
            catch
            {
                return nil
            }
        }

        guard let data = networkRead(size: size) else
        {
            self.log?.debug("TransmissionLinux: unsafeRead received nil response from networkRead()")
            return nil
        }
        
        guard data.count > 0 else
        {
            self.log?.debug("TransmissionLinux: unsafeRead received 0 bytes from networkRead()")
            return nil
        }

        self.buffer.write(data)

        guard size <= buffer.count else
        {
            self.log?.debug("TransmissionLinux: unsafeRead requested size \(size) is larger than the buffer size \(buffer.count). Returning nil.")
            return nil
        }

        do
        {
            let result = try self.buffer.read(size: size)
            return result
        }
        catch
        {
            return nil
        }
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
            do
            {
                let result = try self.buffer.read(size: size)

                self.log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - returned \(result.count) bytes")
                readLock.leave()
                return result
            }
            catch
            {
                readLock.leave()
                return nil
            }
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
                    self.log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error: There are no valid connections")
                    readLock.leave()
                    return nil
                }
            }
            catch
            {
                self.log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error trying to read from the network: \(error)")
                readLock.leave()
                return nil
            }

            guard let bytes = data else
            {
                self.log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error received a nil response when attempting to read from the network.")
                readLock.leave()
                return nil
            }
            
            guard bytes.count > 0 else
            {
                self.log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - Error received an empty response when attempting to read from the network.")
                readLock.leave()
                return nil
            }

            self.buffer.write(bytes)
            let targetSize = min(maxSize, buffer.count)

            do
            {
                let result = try self.buffer.read(size: targetSize)

                self.log?.debug("TransmissionLinux: TransmissionConnection.read(maxSize: \(maxSize)) - returned \(result.count) bytes")
                readLock.leave()
                return result
            }
            catch
            {
                readLock.leave()
                return nil
            }
        }
    }


    public func write(string: String) -> Bool
    {
        writeLock.enter()
        let data = string.data
        let success = write(data: data)
        writeLock.leave()
        
        self.log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> write(string:), success: \(success)")
        return success
    }
    
    public func write(data: Data) -> Bool
    {
        writeLock.enter()
        let success = networkWrite(data: data)
        writeLock.leave()
        
        self.log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> write(data:), success: \(success)")
        return success
    }

    public func readWithLengthPrefix(prefixSizeInBits: Int) -> Data?
    {
        self.log?.debug("TransmissionLinux: readWithLengthPrefix entering lock...")
        readLock.enter()
        self.log?.debug("TransmissionLinux: entered readWithLengthPrefix ")

        guard let result = TransmissionTypes.readWithLengthPrefix(prefixSizeInBits: prefixSizeInBits, connection: self) else
        {
            readLock.leave()
            return nil
        }

        self.log?.debug("TransmissionLinux: TransmissionConnection.readWithLengthPrefix -> returned \(result.count) bytes.")
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
        self.log?.debug("TransmissionLinux.TransmissionConnection: networkRead(size: \(size))")
        
        guard size > 0 else
        {
            self.log?.debug("TransmissionLinux: TransmissionConnection - network read requested for a read size of 0")
            return nil
        }
        
        var networkBuffer = Data()

        while networkBuffer.count < size
        {
            do
            {
                if let tcpConnection = tcpConnection
                {
                    self.log?.debug("TransmissionLinux.TransmissionConnection: calling tcpConnection.read")
                    let bytesRead = try tcpConnection.read(into: &networkBuffer)
                    self.log?.debug("TransmissionLinux.TransmissionConnection: tcpConnection.read read \(bytesRead) bytes")
                    
                    if bytesRead == 0 && tcpConnection.remoteConnectionClosed
                    {
                        return nil
                    }
                }
                else if let udpConnection = udpConnection
                {
                    if let udpPort = udpIncomingPort
                    {
                        self.log?.debug("TransmissionLinux.TransmissionConnection: calling udpConnection.listen")
                        let (bytesRead, address) = try udpConnection.listen(forMessage: &networkBuffer, on: udpPort)
                        self.log?.debug("TransmissionLinux.TransmissionConnection: udpConnection.listen read \(bytesRead) bytes.")
                        
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
                        self.log?.debug("TransmissionLinux.TransmissionConnection: calling udpConnection.readDatagram")
                        let (bytesRead, address) = try udpConnection.readDatagram(into: &networkBuffer)
                        self.log?.debug("TransmissionLinux.TransmissionConnection: udpConnection.readDatagram read \(bytesRead) bytes")
                        
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
                    self.log?.debug("TransmissionLinux.TransmissionConnection: networkRead - Error: There are no valid connections")
                    return nil
                }
            }
            catch
            {
                self.log?.debug("TransmissionLinux.TransmissionConnection: networkRead - Error: \(error)")
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
                
                self.log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> tcp connection wrote \(byteCountWritten) bytes")
                return true
            }
            else if let udpConnection = udpConnection, let udpAddress = udpOutgoingAddress
            {
                let byteCountWritten = try udpConnection.write(from: data, to: udpAddress)
                
                self.log?.debug("TransmissionLinux: TransmissionConnection.networkWrite -> udp connection wrote \(byteCountWritten) bytes")
                return true
            }
            else
            {
                self.log?.debug("TransmissionLinux: TransmissionConnection.networkWrite - Error: There are no valid connections")
                return false
            }
            
        }
        catch
        {
            self.log?.debug("TransmissionLinux: TransmissionConnection.networkWrite - Error: \(error)")
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
