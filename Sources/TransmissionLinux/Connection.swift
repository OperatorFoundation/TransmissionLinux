import Foundation
import Socket
import Datable
import Chord

public protocol Connection
{
    func read(size: Int) -> Data?
    func write(string: String) -> Bool
    func write(data: Data) -> Bool
}
