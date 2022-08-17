import Logging
import Foundation
import XCTest

import Socket
@testable import TransmissionLinux

final class TransmissionTests: XCTestCase
{
    public func testBlueSocket() throws
    {
        let socket1 = try Socket.create()
        XCTAssertNoThrow(try socket1.listen(on: 1234, allowPortReuse: false))

        let socket2 = try Socket.create()
        XCTAssertThrowsError(try socket2.listen(on: 1234, allowPortReuse: false))
    }

    public func testListenConflict()
    {
        let listener1 = TransmissionListener(port: 1234, logger: nil)
        XCTAssertNotNil(listener1)

        let listener2 = TransmissionListener(port: 1234, logger: nil)
        XCTAssertNil(listener2)
    }

    public

    func testUDPConnection()
    {
        let lock = DispatchGroup()
        let queue = DispatchQueue(label: "testingUDP")
        
        lock.enter()
        
        queue.async
        {
            self.runUDPServer(lock)
        }
        
        lock.wait()
        
        runUDPClient()
    }
    
    func runUDPServer(_ lock: DispatchGroup)
    {
        guard let listener = TransmissionListener(port: 7777, type: .udp, logger: nil) else {return}
        lock.leave()

        let connection = listener.accept()
        
        let result = connection.read(size: 4)
        
        if result != nil
        {
            print("Server received a result: \(result!.hex)")
        }
        else
        {
            print("Server received nothing on read.")
        }
        
        XCTAssertEqual(result!, "test")
        
        let _ = connection.write(string: "back")
    }
    
    func runUDPClient()
    {
        let connection = TransmissionConnection(host: "127.0.0.1", port: 7777, type: .udp, logger: nil)
        XCTAssertNotNil(connection)
        
        let writeResult = connection!.write(string: "test")
        XCTAssertTrue(writeResult)
        
        let result = connection!.read(size: 4)
        XCTAssertNotNil(result)
                
        XCTAssertEqual(result!, "back")
    }
    
    public func testConnection()
    {
        let lock = DispatchGroup()
        let queue = DispatchQueue(label: "testing")
        
        lock.enter()
        
        queue.async
        {
            self.runServer(lock)
        }
        
        lock.wait()
        
        runClient()
    }
    
    func runServer(_ lock: DispatchGroup)
    {
        let logger: Logger = Logger(label: "runServer")
        guard let listener = TransmissionListener(port: 1234, logger: logger) else {return}
        lock.leave()

        let connection = listener.accept()
        let _ = connection.read(size: 4)
        let _ = connection.write(string: "back")
    }
    
    func runClient()
    {
      guard let connection = TransmissionConnection(host: "127.0.0.1", port: 1234) else
      {
        XCTFail()
        return
      }

      guard let _ = connection.readWithLengthPrefix(prefixSizeInBits: 16) else
      {
        XCTFail()
        return
      }
    }
}
