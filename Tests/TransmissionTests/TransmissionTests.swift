import XCTest
import Foundation
@testable import Transmission

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
        let _ = connection.read(size: 4)
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

    public func testListenConflict()
    {
        let listener1 = TransmissionListener(port: 1234)
        XCTAssertNotNil(listener1)

        let listener2 = TransmissionListener(port: 1234)
        XCTAssertNil(listener2)
    }
    
    func runServer(_ lock: DispatchGroup)
    {
        guard let listener = Listener(port: 1234) else {return}
        lock.leave()

        let connection = listener.accept()
        let _ = connection.read(size: 4)
        let _ = connection.write(string: "back")
    }
    
    func runClient()
    {
        let connection = Connection(host: "127.0.0.1", port: 1234)
        XCTAssertNotNil(connection)
        
        let writeResult = connection!.write(string: "test")
        XCTAssertTrue(writeResult)
        
        let result = connection!.read(size: 4)
        XCTAssertNotNil(result)
        
        XCTAssertEqual(result!, "back")
    }
}
