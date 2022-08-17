import XCTest
import Foundation
@testable import TransmissionLinux
import Logging

final class TransmissionTests: XCTestCase
{
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
