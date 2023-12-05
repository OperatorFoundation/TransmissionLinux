//
//  SystemdConnection.swift
//
//
//  Created by Dr. Brandon Wiley on 12/5/23.
//

import Foundation

import Straw
import TransmissionTypes

public class SystemdConnection: Connection
{
    let stdin = FileHandle(fileDescriptor: 3)
    let stdout = FileHandle(fileDescriptor: 3)
    let straw: UnsafeStraw = UnsafeStraw()
    let readLock = DispatchSemaphore(value: 0)
    let writeLock = DispatchSemaphore(value: 0)

    public func read(size: Int) -> Data?
    {
        defer
        {
            self.readLock.signal()
        }
        self.readLock.wait()

        while self.straw.count < size
        {
            let data = self.stdin.availableData
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
        defer
        {
            self.readLock.signal()
        }
        self.readLock.wait()

        while self.straw.count < maxSize
        {
            let data = self.stdin.availableData
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
        while self.straw.count < size
        {
            let data = self.stdin.availableData
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
        return TransmissionTypes.readWithLengthPrefix(prefixSizeInBits: prefixSizeInBits, connection: self)
    }
    
    public func write(string: String) -> Bool
    {
        defer
        {
            self.writeLock.signal()
        }
        self.writeLock.wait()

        return self.write(data: string.data)
    }
    
    public func write(data: Data) -> Bool
    {
        self.stdout.write(data)

        return true
    }
    
    public func writeWithLengthPrefix(data: Data, prefixSizeInBits: Int) -> Bool
    {
        TransmissionTypes.writeWithLengthPrefix(data: data, prefixSizeInBits: prefixSizeInBits, connection: self)
    }
    
    public func close()
    {
        do
        {
            try self.stdin.close()
            try self.stdout.close()
        }
        catch
        {
            print(error)
        }
    }
}
