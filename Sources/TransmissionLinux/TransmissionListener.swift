//
//  Listener.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/31/20.
//

import Foundation
import Socket
import Chord
import Logging
import TransmissionTypes

public class TransmissionListener: Listener
{
    let logger: Logger?
    var socket: Socket
    var udpPort: Int? = nil
    let type: ConnectionType
    
    public init?(port: Int, type: ConnectionType = .tcp, logger: Logger?)
    {
        self.logger = logger
        self.type = type
        
        switch (type)
        {
            case .tcp:
                guard let socket = try? Socket.create() else
                {
                    return nil

                }
                self.socket = socket

                do
                {
                    try socket.listen(on: port)
                }
                catch
                {
                    print(error)
                    return nil
                }
                
            case .udp:
                guard let socket = try? Socket.create(family: .inet, type: .datagram, proto: .udp)
                else
                {
                    logger?.error("Failed to create a Linux UDP TransmissionListener: Socket.create() failed.")
                    return nil
                }
                
                self.socket = socket
                self.udpPort = port
        }
        
    }
    
    public func accept() -> Connection
    {
        switch (type)
        {
            case .tcp:
                while true
                {
                    if let newConnection = try? self.socket.acceptClientConnection(invokeDelegate: false)
                    {
                        return TransmissionConnection(socket: newConnection)
                    }
                }
            case .udp:
                while true
                {
                    return TransmissionConnection(socket: socket, port: udpPort!, logger: logger)
                }
        }
    }

    public func close()
    {
        self.socket.close()
    }
}
