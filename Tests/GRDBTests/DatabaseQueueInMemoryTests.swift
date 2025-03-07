import XCTest
import GRDB

class DatabaseQueueInMemoryTests : GRDBTestCase
{
    func testInMemoryDatabase() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.inTransaction { db in
            try db.execute(sql: "CREATE TABLE foo (bar TEXT)")
            try db.execute(sql: "INSERT INTO foo (bar) VALUES ('baz')")
            let baz = try String.fetchOne(db, sql: "SELECT bar FROM foo")!
            XCTAssertEqual(baz, "baz")
            return .rollback
        }
    }
}
