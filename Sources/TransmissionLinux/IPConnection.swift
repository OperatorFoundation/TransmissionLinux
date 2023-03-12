//
//  IPConnection.swift
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
import TransmissionBase
import TransmissionTypes

public class IPConnection: BaseConnection
{
    var socket: Socket

    public init?(socket: Socket, logger: Logger? = nil)
    {
        self.socket = socket

        super.init(id: Int(socket.socketfd), logger: logger)
    }

    public override func close()
    {
        self.socket.close()
    }
}

public enum IPConnectionError: Error
{
    case unimplemented
}
