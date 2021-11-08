import Foundation
import Socket
import Datable
import Chord

public class TransmissionConnection: Connection
{
    var connectLock = DispatchGroup()
    var readLock = DispatchGroup()
    var writeLock = DispatchGroup()

    let socket: Socket
    var buffer: Data = Data()

    public init?(host: String, port: Int)
    {
        guard let socket = try? Socket.create() else {return nil}
        self.socket = socket
        
        do
        {
            try self.socket.connect(to: host, port: Int32(port))
        }
        catch
        {
            return nil
        }
    }
    
    public init(socket: Socket)
    {
        self.socket = socket
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

        do
        {
            let _ = try self.socket.read(into: &buffer)

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
        catch
        {
            readLock.leave()
            return nil
        }
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

            do
            {
                let readSize = try self.socket.read(into: &buffer)

                let result = Data(buffer[0..<readSize])
                buffer = Data(buffer[readSize..<buffer.count])

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

        do
        {
            try self.socket.write(from: data)
        }
        catch
        {
            writeLock.leave()
            return false
        }

        writeLock.leave()
        return true
    }

    public func readWithLengthPrefix(prefixSizeInBits: Int) -> Data?
    {
        readLock.enter()

        var maybeLength: Int? = nil

        switch prefixSizeInBits
        {
            case 8:
                var lengthData = Data(repeating: 0, count: 1)

                do
                {
                    let readSize = try self.socket.read(into: &lengthData)

                    guard readSize == 1 else
                    {
                        readLock.leave()
                        return nil
                    }

                    guard let length8 = UInt8(maybeNetworkData: lengthData) else
                    {
                        readLock.leave()
                        return nil
                    }

                    maybeLength = Int(length8)
                }
                catch
                {
                    readLock.leave()
                    return nil
                }
            case 16:
                var lengthData = Data(repeating: 0, count: 2)

                do
                {
                    let readSize = try self.socket.read(into: &lengthData)

                    guard readSize == 2 else
                    {
                        readLock.leave()
                        return nil
                    }

                    guard let length16 = UInt16(maybeNetworkData: lengthData) else
                    {
                        readLock.leave()
                        return nil
                    }

                    maybeLength = Int(length16)
                }
                catch
                {
                    readLock.leave()
                    return nil
                }
            case 32:
                var lengthData = Data(repeating: 0, count: 4)

                do
                {
                    let readSize = try self.socket.read(into: &lengthData)

                    guard readSize == 4 else
                    {
                        readLock.leave()
                        return nil
                    }

                    guard let length32 = UInt32(maybeNetworkData: lengthData) else
                    {
                        readLock.leave()
                        return nil
                    }

                    maybeLength = Int(length32)
                }
                catch
                {
                    readLock.leave()
                    return nil
                }
            case 64:
                var lengthData = Data(repeating: 0, count: 8)

                do
                {
                    let readSize = try self.socket.read(into: &lengthData)

                    guard readSize == 8 else
                    {
                        readLock.leave()
                        return nil
                    }

                    guard let length64 = UInt64(maybeNetworkData: lengthData) else
                    {
                        readLock.leave()
                        return nil
                    }

                    maybeLength = Int(length64)
                }
                catch
                {
                    readLock.leave()
                    return nil
                }
            default:
                readLock.leave()
                return nil
        }

        guard let length = maybeLength else
        {
            readLock.leave()
            return nil
        }

        var data = Data(repeating: 0, count: length)

        do
        {
            let readSize = try self.socket.read(into: &data)

            guard readSize == length else
            {
                readLock.leave()
                return nil
            }

            return data
        }
        catch
        {
            readLock.leave()
            return nil
        }
    }

    public func writeWithLengthPrefix(data: Data, prefixSizeInBits: Int) -> Bool
    {
        writeLock.enter()

        let length = data.count

        switch prefixSizeInBits
        {
            case 8:
                let length8 = UInt8(length)

                guard let lengthData = length8.maybeNetworkData else
                {
                    writeLock.leave()
                    return false
                }

                do
                {
                    try self.socket.write(from: lengthData)
                    try self.socket.write(from: data)

                    writeLock.leave()
                    return true
                }
                catch
                {
                    writeLock.leave()
                    return false
                }

            case 16:
                let length16 = UInt16(length)

                guard let lengthData = length16.maybeNetworkData else
                {
                    writeLock.leave()
                    return false
                }

                do
                {
                    try self.socket.write(from: lengthData)
                    try self.socket.write(from: data)

                    writeLock.leave()
                    return true
                }
                catch
                {
                    writeLock.leave()
                    return false
                }

            case 32:
                let length32 = UInt32(length)

                guard let lengthData = length32.maybeNetworkData else
                {
                    writeLock.leave()
                    return false
                }

                do
                {
                    try self.socket.write(from: lengthData)
                    try self.socket.write(from: data)

                    writeLock.leave()
                    return true
                }
                catch
                {
                    writeLock.leave()
                    return false
                }

            case 64:
                let length64 = UInt8(length)

                guard let lengthData = length64.maybeNetworkData else
                {
                    writeLock.leave()
                    return false
                }

                do
                {
                    try self.socket.write(from: lengthData)
                    try self.socket.write(from: data)

                    writeLock.leave()
                    return true
                }
                catch
                {
                    writeLock.leave()
                    return false
                }

            default:
                writeLock.leave()
                return false
        }
    }
    
    public func identifier() -> Int {
        return Int(self.socket.socketfd)
    }
}
