//
//  UDPConnection.swift
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

public class UDPConnection: IPConnection
{
    let port: Int

    var udpOutgoingAddress: Socket.Address?

    public init?(host: String, port: Int, logger: Logger? = nil)
    {
        guard let socket = try? Socket.create(family: .inet, type: .datagram, proto: .udp) else
        {
            print("TransmissionLinux: Failed to create a Linux UDP TransmissionConnection: Socket.create() failed.")
            return nil
        }
        self.udpOutgoingAddress = Socket.createAddress(for: host, on: Int32(port))
        self.port = port

        super.init(socket: socket, logger: logger)
    }

    public override func networkWrite(data: Data) throws
    {
        try self.socket.write(from: data, to: self.udpOutgoingAddress!)
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
            print("TransmissionLinux.TransmissionConnection: calling udpConnection.readDatagram")
            let (bytesRead, address) = try self.socket.readDatagram(into: &networkBuffer)
            print("TransmissionLinux.TransmissionConnection: udpConnection.readDatagram read \(bytesRead) bytes")

            if udpOutgoingAddress == nil
            {
                self.udpOutgoingAddress = address
            }

            if bytesRead == 0 && self.socket.remoteConnectionClosed
            {
                throw UDPConnectionError.closed
            }
        }

        return networkBuffer
    }
}

public enum UDPConnectionError: Error
{
    case closed
}
