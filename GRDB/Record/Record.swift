// MARK: - Record

/// Record is a class that wraps a table row, or the result of any query. It is
/// designed to be subclassed.
open class Record: FetchableRecord, TableRecord, PersistableRecord {
    
    // MARK: - Initializers
    
    /// Creates a Record.
    public init() {
    }
    
    /// Creates a Record from a row.
    public required init(row: Row) throws {
        if row.isFetched {
            // Take care of the hasDatabaseChanges flag.
            //
            // Row may be a reused row which will turn invalid as soon as the
            // SQLite statement is iterated. We need to store an
            // immutable copy.
            referenceRow = row.copy()
        }
    }
    
    
    // MARK: - Core methods
    
    /// The name of a database table.
    ///
    /// This table name is required by the insert, update, save, delete,
    /// and exists methods.
    ///
    ///     class Player : Record {
    ///         override class var databaseTableName: String {
    ///             return "player"
    ///         }
    ///     }
    ///
    /// The implementation of the base class Record raises a fatal error.
    ///
    /// - returns: The name of a database table.
    open class var databaseTableName: String {
        // Programmer error
        fatalError("subclass must override")
    }
    
    /// The policy that handles SQLite conflicts when records are inserted
    /// or updated.
    ///
    /// The default implementation uses the ABORT policy for both insertions and
    /// updates, and has GRDB generate regular INSERT and UPDATE queries.
    ///
    /// See <https://www.sqlite.org/lang_conflict.html>
    open class var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .abort, update: .abort)
    }
    
    /// The default request selection.
    ///
    /// Unless this method is overridden, requests select all columns:
    ///
    ///     // SELECT * FROM player
    ///     try Player.fetchAll(db)
    ///
    /// You can override this property and provide an explicit list
    /// of columns:
    ///
    ///     class RestrictedPlayer : Record {
    ///         override static var databaseSelection: [any SQLSelectable] {
    ///             return [Column("id"), Column("name")]
    ///         }
    ///     }
    ///
    ///     // SELECT id, name FROM player
    ///     try RestrictedPlayer.fetchAll(db)
    ///
    /// You can also add extra columns such as the `rowid` column:
    ///
    ///     class ExtendedPlayer : Player {
    ///         override static var databaseSelection: [any SQLSelectable] {
    ///             return [AllColumns(), Column.rowID]
    ///         }
    ///     }
    ///
    ///     // SELECT *, rowid FROM player
    ///     try ExtendedPlayer.fetchAll(db)
    open class var databaseSelection: [any SQLSelectable] {
        [AllColumns()]
    }
    
    
    /// Defines the values persisted in the database.
    ///
    /// Store in the *container* parameter all values that should be stored in
    /// the columns of the database table (see Record.databaseTableName()).
    ///
    /// Primary key columns, if any, must be included.
    ///
    ///     class Player : Record {
    ///         var id: Int64?
    ///         var name: String?
    ///
    ///         override func encode(to container: inout PersistenceContainer) throws {
    ///             container["id"] = id
    ///             container["name"] = name
    ///         }
    ///     }
    ///
    /// The implementation of the base class Record does not store any value in
    /// the container.
    open func encode(to container: inout PersistenceContainer) throws { }
    
    // MARK: - Compare with Previous Versions
    
    /// A boolean that indicates whether the record has changes that have not
    /// been saved.
    ///
    /// This flag is purely informative, and does not prevent insert(),
    /// update(), and save() from performing their database queries.
    ///
    /// A record is *edited* if has been changed since last database
    /// synchronization (fetch, update, insert). Comparison
    /// is performed between *values* (values stored in the `encode(to:)`
    /// method, and values loaded from the database). Property setters do not
    /// trigger this flag.
    ///
    /// You can rely on the Record base class to compute this flag for you, or
    /// you may set it to true or false when you know better. Setting it to
    /// false does not prevent it from turning true on subsequent modifications
    /// of the record.
    public var hasDatabaseChanges: Bool {
        do {
            return try databaseChangesIterator().next() != nil
        } catch {
            // Can't encode the record: surely it can't be saved.
            return true
        }
    }
    
    /// A dictionary of changes that have not been saved.
    ///
    /// Its keys are column names, and values the old values that have been
    /// changed since last fetching or saving of the record.
    ///
    /// Unless the record has actually been fetched or saved, the old values
    /// are nil.
    ///
    /// See `hasDatabaseChanges` for more information.
    ///
    /// - throws: An error is thrown if the record can't be encoded to its
    ///   database representation.
    public var databaseChanges: [String: DatabaseValue?] {
        get throws {
            try Dictionary(uniqueKeysWithValues: databaseChangesIterator())
        }
    }
    
    /// Sets hasDatabaseChanges to true
    private func setHasDatabaseChanges() {
        referenceRow = nil
    }
    
    /// Sets hasDatabaseChanges to false
    private func resetDatabaseChanges() throws {
        referenceRow = try Row(self)
    }
    
    /// Sets hasDatabaseChanges to false
    private func resetDatabaseChanges(with persistenceContainer: PersistenceContainer) {
        referenceRow = Row(persistenceContainer)
    }
    
    // A change iterator that is used by both hasDatabaseChanges and
    // persistentChangedValues properties.
    private func databaseChangesIterator() throws -> AnyIterator<(String, DatabaseValue?)> {
        let oldRow = referenceRow
        var newValueIterator = try PersistenceContainer(self).makeIterator()
        return AnyIterator {
            // Loop until we find a change, or exhaust columns:
            while let (column, newValue) = newValueIterator.next() {
                let newDbValue = newValue?.databaseValue ?? .null
                guard let oldRow = oldRow, let oldDbValue: DatabaseValue = oldRow[column] else {
                    return (column, nil)
                }
                if newDbValue != oldDbValue {
                    return (column, oldDbValue)
                }
            }
            return nil
        }
    }
    
    
    /// Reference row for the *hasDatabaseChanges* property.
    var referenceRow: Row?
    
    // MARK: Persistence Callbacks
    
    /// Called before the record is inserted.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter db: A database connection.
    open func willInsert(_ db: Database) throws { }
    
    /// Called around the record insertion.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation (this calls the `insert` parameter).
    ///
    /// For example:
    ///
    ///     class Player: Record {
    ///         func aroundInsert(_ db: Database, insert: () throws -> InsertionSuccess) throws {
    ///             print("Player will insert")
    ///             try super.aroundInsert(db, insert: insert)
    ///             print("Player did insert")
    ///         }
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter insert: A function that inserts the record, and returns
    ///   information about the inserted row.
    open func aroundInsert(_ db: Database, insert: () throws -> InsertionSuccess) throws {
        let inserted = try insert()
        resetDatabaseChanges(with: inserted.persistenceContainer)
    }
    
    /// Called upon successful insertion.
    ///
    /// You can override this method in order to grab the auto-incremented id:
    ///
    ///     class Player: Record {
    ///         var id: Int64?
    ///         var name: String
    ///
    ///         override func didInsert(_ inserted: InsertionSuccess) {
    ///             super.didInsert(inserted)
    ///             id = inserted.rowID
    ///         }
    ///     }
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter inserted: Information about the inserted row.
    open func didInsert(_ inserted: InsertionSuccess) { }
    
    /// Called before the record is updated.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter db: A database connection.
    open func willUpdate(_ db: Database, columns: Set<String>) throws { }
    
    // swiftlint:disable line_length
    /// Called around the record update.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation (this calls the `update` parameter).
    ///
    /// For example:
    ///
    ///     class Player: Record {
    ///         override func aroundUpdate(_ db: Database, columns: Set<String>, update: () throws -> PersistenceSuccess) throws {
    ///             print("Player will update")
    ///             try super.aroundUpdate(db, columns: columns, update: update)
    ///             print("Player did update")
    ///         }
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter columns: The updated columns.
    /// - parameter update: A function that updates the record. Its result is
    ///   reserved for GRDB usage.
    open func aroundUpdate(_ db: Database, columns: Set<String>, update: () throws -> PersistenceSuccess) throws {
        let updated = try update()
        resetDatabaseChanges(with: updated.persistenceContainer)
    }
    // swiftlint:enable line_length
    
    /// Called upon successful update.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter updated: Reserved for GRDB usage.
    open func didUpdate(_ updated: PersistenceSuccess) { }
    
    /// Called before the record is updated or inserted.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter db: A database connection.
    open func willSave(_ db: Database) throws { }
    
    /// Called around the record update or insertion.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation (this calls the `update` parameter).
    ///
    /// For example:
    ///
    ///     class Player: Record {
    ///         override func aroundSave(_ db: Database, save: () throws -> PersistenceSuccess) throws {
    ///             print("Player will save")
    ///             try super.aroundSave(db, save: save)
    ///             print("Player did save")
    ///         }
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter update: A function that updates the record. Its result is
    ///   reserved for GRDB usage.
    open func aroundSave(_ db: Database, save: () throws -> PersistenceSuccess) throws {
        _ = try save()
    }
    
    /// Called upon successful update or insertion.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter saved: Reserved for GRDB usage.
    open func didSave(_ saved: PersistenceSuccess) { }

    /// Called before the record is deleted.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter db: A database connection.
    open func willDelete(_ db: Database) throws { }
    
    /// Called around the destruction of the record.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation (this calls the `delete` parameter).
    ///
    /// For example:
    ///
    ///     class Player: Record {
    ///         override func aroundDelete(_ db: Database, delete: () throws -> Bool) throws {
    ///             print("Player will delete")
    ///             try super.aroundDelete(db, delete: delete)
    ///             print("Player did delete")
    ///         }
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter delete: A function that deletes the record and returns
    ///   whether a row was deleted in the database.
    open func aroundDelete(_ db: Database, delete: () throws -> Bool) throws {
        _ = try delete()
        setHasDatabaseChanges()
    }
    
    /// Called upon successful deletion.
    ///
    /// If you override this method, you must call `super` at some point in
    /// your implementation.
    ///
    /// - parameter deleted: Whether a row was deleted in the database.
    open func didDelete(deleted: Bool) { }
    
    // MARK: - CRUD
    
    /// If the record has been changed, executes an UPDATE statement so that
    /// those changes and only those changes are saved in the database.
    ///
    /// On success, this method sets the *hasDatabaseChanges* flag to false.
    ///
    /// This method is guaranteed to have saved the eventual changes in the
    /// database if it returns without error.
    ///
    /// - parameter db: A database connection.
    /// - parameter columns: The columns to update.
    /// - returns: Whether the record had changes.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    ///   PersistenceError.recordNotFound is thrown if the primary key does not
    ///   match any row in the database and record could not be updated.
    @discardableResult
    public final func updateChanges(_ db: Database) throws -> Bool {
        let changedColumns = try Set(databaseChanges.keys)
        if changedColumns.isEmpty {
            return false
        } else {
            try update(db, columns: changedColumns)
            return true
        }
    }
}
