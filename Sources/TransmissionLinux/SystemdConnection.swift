//
//  SystemdConnection.swift
//
//
//  Created by Dr. Brandon Wiley on 12/5/23.
//

import Foundation
import Logging

import Straw
import TransmissionTypes

public class SystemdConnection: Connection
{
    let fd = FileHandle(fileDescriptor: 3)

    let logger: Logger
    let verbose: Bool

    let straw: UnsafeStraw = UnsafeStraw()
    let readLock = DispatchSemaphore(value: 0)
    let writeLock = DispatchSemaphore(value: 0)

    var closed: Bool = false

    public init(logger: Logger, verbose: Bool)
    {
        self.logger = logger
        self.verbose = verbose
    }

    public func read(size: Int) -> Data?
    {
        if closed
        {
            return nil
        }

        defer
        {
            self.readLock.signal()
        }
        self.readLock.wait()

        while self.straw.count < size
        {
            let data = self.fd.availableData
            self.straw.write(data)
        }

        do
        {
            return try self.straw.read(size: size)
        }
        catch
        {
            return nil
        }
    }
    
    public func read(maxSize: Int) -> Data?
    {
        if closed
        {
            return nil
        }

        defer
        {
            self.readLock.signal()
        }
        self.readLock.wait()

        while self.straw.count < maxSize
        {
            let data = self.fd.availableData
            guard data.count > 0 else
            {
                do
                {
                    return try self.straw.read(maxSize: maxSize)
                }
                catch
                {
                    return nil
                }
            }

            self.straw.write(data)
        }

        do
        {
            return try self.straw.read(maxSize: maxSize)
        }
        catch
        {
            return nil
        }
    }

    public func unsafeRead(size: Int) -> Data?
    {
        if closed
        {
            return nil
        }

        while self.straw.count < size
        {
            let data = self.fd.availableData
            self.straw.write(data)
        }

        do
        {
            return try self.straw.read(size: size)
        }
        catch
        {
            return nil
        }
    }

    public func readWithLengthPrefix(prefixSizeInBits: Int) -> Data?
    {
        if closed
        {
            return nil
        }

        return TransmissionTypes.readWithLengthPrefix(prefixSizeInBits: prefixSizeInBits, connection: self)
    }
    
    public func write(string: String) -> Bool
    {
        if closed
        {
            return false
        }

        defer
        {
            self.writeLock.signal()
        }
        self.writeLock.wait()

        return self.write(data: string.data)
    }
    
    public func write(data: Data) -> Bool
    {
        if closed
        {
            return false
        }

        self.fd.write(data)

        return true
    }
    
    public func writeWithLengthPrefix(data: Data, prefixSizeInBits: Int) -> Bool
    {
        if closed
        {
            return false
        }

        return TransmissionTypes.writeWithLengthPrefix(data: data, prefixSizeInBits: prefixSizeInBits, connection: self)
    }
    
    public func close()
    {
        if closed
        {
            return
        }

        do
        {
            self.closed = true
            try self.fd.close()
        }
        catch
        {
            print(error)
        }
    }
}
