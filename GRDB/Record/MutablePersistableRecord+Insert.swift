// MARK: - Insert Callbacks

extension MutablePersistableRecord {
    @inline(__always)
    @inlinable
    public mutating func willInsert(_ db: Database) throws { }
    
    @inline(__always)
    @inlinable
    public func aroundInsert(_ db: Database, insert: () throws -> InsertionSuccess) throws {
        _ = try insert()
    }
    
    @inline(__always)
    @inlinable
    public mutating func didInsert(_ inserted: InsertionSuccess) { }
}

// MARK: - Insert

extension MutablePersistableRecord {
    /// Executes an `INSERT` statement.
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    public mutating func insert(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil)
    throws
    {
        try willSave(db)
        
        var saved: PersistenceSuccess?
        try aroundSave(db) {
            let inserted = try insertWithCallbacks(db, onConflict: conflictResolution)
            saved = PersistenceSuccess(inserted)
            return saved!
        }
        
        guard let saved else {
            try persistenceCallbackMisuse("aroundSave")
        }
        didSave(saved)
    }
    
    /// Executes an `INSERT` statement, and returns the inserted record.
    ///
    /// Usage:
    ///
    ///     let player = Player(id: nil, name: "Arthur")
    ///     let insertedPlayer = try dbQueue.write { db in
    ///         try player.inserted(db)
    ///     }
    ///     print(player.id)         // nil
    ///     print(insertedPlayer.id) // some id
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - returns: The inserted record.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    public func inserted(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil)
    throws -> Self
    {
        var result = self
        try result.insert(db, onConflict: conflictResolution)
        return result
    }
}

// MARK: - Insert and Fetch

extension MutablePersistableRecord {
#if GRDBCUSTOMSQLITE || GRDBCIPHER
    /// Executes an `INSERT ... RETURNING ...` statement, and returns the
    /// inserted record.
    ///
    /// This method helps dealing with default column values and
    /// generated columns.
    ///
    /// For example:
    ///
    ///     let player: Player = ...
    ///     let insertedPlayer = player.insertAndFetch(db)
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - returns: The inserted record, if any. The result can be nil when the
    ///   conflict policy is `IGNORE`.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    public func insertAndFetch(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil)
    throws -> Self?
    where Self: FetchableRecord
    {
        var result = self
        return try result.insertAndFetch(db, onConflict: conflictResolution, as: Self.self)
    }
    
    /// Executes an `INSERT ... RETURNING ...` statement, and returns a new
    /// record built from the inserted row.
    ///
    /// This method helps dealing with default column values and
    /// generated columns.
    ///
    /// For example:
    ///
    ///     // A table with an auto-incremented primary key and a default value
    ///     try dbQueue.write { db in
    ///         try db.execute(sql: """
    ///             CREATE TABLE player(
    ///               id INTEGER PRIMARY KEY AUTOINCREMENT,
    ///               name TEXT,
    ///               score INTEGER DEFAULT 1000)
    ///             """)
    ///     }
    ///
    ///     // A player with partial database information
    ///     struct PartialPlayer: MutablePersistableRecord {
    ///         static let databaseTableName = "player"
    ///         var name: String
    ///     }
    ///
    ///     // A full player, with all database information
    ///     struct Player: TableRecord, FetchableRecord {
    ///         var id: Int64
    ///         var name: String
    ///         var score: Int
    ///     }
    ///
    ///     // Insert a base player, get a full one
    ///     try dbQueue.write { db in
    ///         var partialPlayer = PartialPlayer(name: "Alice")
    ///
    ///         // INSERT INTO player (name) VALUES ('Alice') RETURNING *
    ///         if let player = try partialPlayer.insertAndFetch(db, as: FullPlayer.self) {
    ///             print(player.id)    // The inserted id
    ///             print(player.name)  // The inserted name
    ///             print(player.score) // The default score
    ///         }
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - parameter returnedType: The type of the returned record.
    /// - returns: A record of type `returnedType`, if any. The result can be
    ///   nil when the conflict policy is `IGNORE`.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    public mutating func insertAndFetch<T: FetchableRecord & TableRecord>(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil,
        as returnedType: T.Type)
    throws -> T?
    {
        try insertAndFetch(db, onConflict: conflictResolution, selection: T.databaseSelection) {
            try T.fetchOne($0)
        }
    }
    
    /// Executes an `INSERT ... RETURNING ...` statement, and returns the
    /// selected columns from the inserted row.
    ///
    /// This method helps dealing with default column values and
    /// generated columns.
    ///
    /// For example:
    ///
    ///     // A table with an auto-incremented primary key and a default value
    ///     try dbQueue.write { db in
    ///         try db.execute(sql: """
    ///             CREATE TABLE player(
    ///               id INTEGER PRIMARY KEY AUTOINCREMENT,
    ///               name TEXT,
    ///               score INTEGER DEFAULT 1000)
    ///             """)
    ///     }
    ///
    ///     // A player with partial database information
    ///     struct PartialPlayer: MutablePersistableRecord {
    ///         static let databaseTableName = "player"
    ///         var name: String
    ///     }
    ///
    ///     // Insert a base player, get the inserted score
    ///     try dbQueue.write { db in
    ///         var partialPlayer = PartialPlayer(name: "Alice")
    ///
    ///         // INSERT INTO player (name) VALUES ('Alice') RETURNING score
    ///         let score = try partialPlayer.insertAndFetch(db, selection: [Column("score")]) { statement in
    ///             try Int.fetchOne(statement)
    ///         }
    ///         print(score) // The inserted score
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - parameter selection: The returned columns (must not be empty).
    /// - parameter fetch: A function that executes its ``Statement`` argument.
    /// - returns: The result of the `fetch` function.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    /// - precondition: `selection` is not empty.
    @inlinable // allow specialization so that empty callbacks are removed
    public mutating func insertAndFetch<T>(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil,
        selection: [any SQLSelectable],
        fetch: (Statement) throws -> T)
    throws -> T
    {
        GRDBPrecondition(!selection.isEmpty, "Invalid empty selection")
        
        try willSave(db)
        
        var success: (inserted: InsertionSuccess, returned: T)?
        try aroundSave(db) {
            success = try insertAndFetchWithCallbacks(
                db, onConflict: conflictResolution,
                selection: selection,
                fetch: fetch)
            return PersistenceSuccess(success!.inserted)
        }
        
        guard let success else {
            try persistenceCallbackMisuse("aroundSave")
        }
        didSave(PersistenceSuccess(success.inserted))
        return success.returned
    }
#else
    /// Executes an `INSERT ... RETURNING ...` statement, and returns the
    /// inserted record.
    ///
    /// This method helps dealing with default column values and
    /// generated columns.
    ///
    /// For example:
    ///
    ///     let player: Player = ...
    ///     let insertedPlayer = player.insertAndFetch(db)
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - returns: The inserted record, if any. The result can be nil when the
    ///   conflict policy is `IGNORE`.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) // SQLite 3.35.0+
    public func insertAndFetch(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil)
    throws -> Self?
    where Self: FetchableRecord
    {
        var result = self
        return try result.insertAndFetch(db, onConflict: conflictResolution, as: Self.self)
    }
    
    /// Executes an `INSERT ... RETURNING ...` statement, and returns a new
    /// record built from the inserted row.
    ///
    /// This method helps dealing with default column values and
    /// generated columns.
    ///
    /// For example:
    ///
    ///     // A table with an auto-incremented primary key and a default value
    ///     try dbQueue.write { db in
    ///         try db.execute(sql: """
    ///             CREATE TABLE player(
    ///               id INTEGER PRIMARY KEY AUTOINCREMENT,
    ///               name TEXT,
    ///               score INTEGER DEFAULT 1000)
    ///             """)
    ///     }
    ///
    ///     // A player with partial database information
    ///     struct PartialPlayer: MutablePersistableRecord {
    ///         static let databaseTableName = "player"
    ///         var name: String
    ///     }
    ///
    ///     // A full player, with all database information
    ///     struct Player: TableRecord, FetchableRecord {
    ///         var id: Int64
    ///         var name: String
    ///         var score: Int
    ///     }
    ///
    ///     // Insert a base player, get a full one
    ///     try dbQueue.write { db in
    ///         var partialPlayer = PartialPlayer(name: "Alice")
    ///
    ///         // INSERT INTO player (name) VALUES ('Alice') RETURNING *
    ///         if let player = try partialPlayer.insertAndFetch(db, as: FullPlayer.self) {
    ///             print(player.id)    // The inserted id
    ///             print(player.name)  // The inserted name
    ///             print(player.score) // The default score
    ///         }
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - parameter returnedType: The type of the returned record.
    /// - returns: A record of type `returnedType`, if any. The result can be
    ///   nil when the conflict policy is `IGNORE`.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) // SQLite 3.35.0+
    public mutating func insertAndFetch<T: FetchableRecord & TableRecord>(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil,
        as returnedType: T.Type)
    throws -> T?
    {
        try insertAndFetch(db, onConflict: conflictResolution, selection: T.databaseSelection) {
            try T.fetchOne($0)
        }
    }
    
    /// Executes an `INSERT ... RETURNING ...` statement, and returns the
    /// selected columns from the inserted row.
    ///
    /// This method helps dealing with default column values and
    /// generated columns.
    ///
    /// For example:
    ///
    ///     // A table with an auto-incremented primary key and a default value
    ///     try dbQueue.write { db in
    ///         try db.execute(sql: """
    ///             CREATE TABLE player(
    ///               id INTEGER PRIMARY KEY AUTOINCREMENT,
    ///               name TEXT,
    ///               score INTEGER DEFAULT 1000)
    ///             """)
    ///     }
    ///
    ///     // A player with partial database information
    ///     struct PartialPlayer: MutablePersistableRecord {
    ///         static let databaseTableName = "player"
    ///         var name: String
    ///     }
    ///
    ///     // Insert a base player, get the inserted score
    ///     try dbQueue.write { db in
    ///         var partialPlayer = PartialPlayer(name: "Alice")
    ///
    ///         // INSERT INTO player (name) VALUES ('Alice') RETURNING score
    ///         let score = try partialPlayer.insertAndFetch(db, selection: [Column("score")]) { statement in
    ///             try Int.fetchOne(statement)
    ///         }
    ///         print(score) // The inserted score
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution.
    /// - parameter selection: The returned columns (must not be empty).
    /// - parameter fetch: A function that executes its ``Statement`` argument.
    /// - returns: The result of the `fetch` function.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    /// - precondition: `selection` is not empty.
    @inlinable // allow specialization so that empty callbacks are removed
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) // SQLite 3.35.0+
    public mutating func insertAndFetch<T>(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil,
        selection: [any SQLSelectable],
        fetch: (Statement) throws -> T)
    throws -> T
    {
        GRDBPrecondition(!selection.isEmpty, "Invalid empty selection")
        
        try willSave(db)
        
        var success: (inserted: InsertionSuccess, returned: T)?
        try aroundSave(db) {
            success = try insertAndFetchWithCallbacks(
                db, onConflict: conflictResolution,
                selection: selection,
                fetch: fetch)
            return PersistenceSuccess(success!.inserted)
        }
        
        guard let success else {
            try persistenceCallbackMisuse("aroundSave")
        }
        didSave(PersistenceSuccess(success.inserted))
        return success.returned
    }
#endif
}

// MARK: - Internals

extension MutablePersistableRecord {
    /// Executes an `INSERT` statement, and runs insertion callbacks.
    @inlinable // allow specialization so that empty callbacks are removed
    mutating func insertWithCallbacks(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution?)
    throws -> InsertionSuccess
    {
        let (inserted, _) = try insertAndFetchWithCallbacks(db, onConflict: conflictResolution, selection: []) {
            // Nothing to fetch
            try $0.execute()
        }
        return inserted
    }
    
    /// Executes an `INSERT` statement, with `RETURNING` clause if `selection`
    /// is not empty, and runs insertion callbacks.
    @inlinable // allow specialization so that empty callbacks are removed
    mutating func insertAndFetchWithCallbacks<T>(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution?,
        selection: [any SQLSelectable],
        fetch: (Statement) throws -> T)
    throws -> (InsertionSuccess, T)
    {
        try willInsert(db)
        
        var success: (inserted: InsertionSuccess, returned: T)?
        try aroundInsert(db) {
            success = try insertAndFetchWithoutCallbacks(
                db, onConflict: conflictResolution,
                selection: selection,
                fetch: fetch)
            return success!.inserted
        }
        
        guard let success else {
            try persistenceCallbackMisuse("aroundInsert")
        }
        didInsert(success.inserted)
        return success
    }
    
    /// Executes an `INSERT` statement, with `RETURNING` clause if `selection`
    /// is not empty, and DOES NOT run insertion callbacks.
    @usableFromInline
    func insertAndFetchWithoutCallbacks<T>(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution?,
        selection: [any SQLSelectable],
        fetch: (Statement) throws -> T)
    throws -> (InsertionSuccess, T)
    {
        let conflictResolution = conflictResolution ?? type(of: self)
            .persistenceConflictPolicy
            .conflictResolutionForInsert
        let dao = try DAO(db, self)
        let statement = try dao.insertStatement(
            db,
            onConflict: conflictResolution,
            returning: selection)
        let returned = try fetch(statement)
        
        let rowIDColumn = dao.primaryKey.rowIDColumn
        let rowid = db.lastInsertedRowID
        
        // Update the persistenceContainer with the inserted rowid.
        // This allows the Record class to set its `hasDatabaseChanges` property
        // to false in its `aroundInsert` callback.
        var persistenceContainer = dao.persistenceContainer
        if let rowIDColumn {
            persistenceContainer[caseInsensitive: rowIDColumn] = rowid
        }
        
        let inserted = InsertionSuccess(
            rowID: rowid,
            rowIDColumn: rowIDColumn,
            persistenceContainer: persistenceContainer)
        return (inserted, returned)
    }
}
