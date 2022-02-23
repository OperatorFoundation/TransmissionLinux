import XCTest
import Foundation
@testable import TransmissionLinux
import Logging

final class TransmissionTests: XCTestCase
{
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
