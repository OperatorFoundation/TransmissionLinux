//
//  TCPConnection.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/11/23.
//

import Foundation
#if os(macOS)
import os.log
#else
import Logging
#endif

import Chord
import Datable
import Net
import Socket
import SwiftHexTools
import SwiftQueue
import TransmissionTypes

public class TCPConnection: IPConnection
{
    let port: Int

    public init?(host: String, port: Int, logger: Logger? = nil)
    {
        self.port = port

        guard let socket = try? Socket.create() else
        {
            print("TransmissionLinux: Failed to create a Linux TCP TransmissionConnection: Socket.create() failed.")
            return nil
        }

        do
        {
            try socket.connect(to: host, port: Int32(port))
        }
        catch
        {
            print("error in TCPConnection(\(host), \(port))")
            return nil
        }

        super.init(socket: socket, logger: logger)
    }

    public override func networkWrite(data: Data) throws
    {
        try self.socket.write(from: data)
    }

    public override func networkRead(size: Int, timeoutSeconds: Int = 10) throws -> Data
    {
        print("TransmissionLinux.TransmissionConnection: networkRead(size: \(size))")

        guard size > 0 else
        {
            print("TransmissionLinux: TransmissionConnection - network read requested for a read size of 0")
            return Data()
        }

        var networkBuffer = Data()

        while networkBuffer.count < size
        {
            print("TransmissionLinux.TransmissionConnection: calling tcpConnection.read")
            let bytesRead = try self.socket.read(into: &networkBuffer)
            print("TransmissionLinux.TransmissionConnection: tcpConnection.read read \(bytesRead) bytes")

            if bytesRead == 0 && self.socket.remoteConnectionClosed
            {
                throw TCPConnectionError.closed
            }
        }

        return networkBuffer
    }
}

public enum TCPConnectionError: Error
{
    case closed
}
