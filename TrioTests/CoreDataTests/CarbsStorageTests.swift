import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("CarbsStorage Tests", .serialized) struct CarbsStorageTests: Injectable {
    @Injected() var storage: CarbsStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        // Create test context
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()

        // Create assembler with test assembly
        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext)
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    @Test("Storage is correctly initialized") func testStorageInitialization() {
        #expect(storage != nil, "CarbsStorage should be injected")
        #expect(storage is BaseCarbsStorage, "Storage should be of type BaseCarbsStorage")
        #expect(storage.updatePublisher != nil, "Update publisher should be available")
    }

    @Test("Store and retrieve carbs entries") func testStoreAndRetrieveCarbs() async throws {
        // Given
        let testEntries = [
            CarbsEntry(
                id: UUID().uuidString,
                createdAt: Date(),
                actualDate: Date(),
                carbs: 20,
                fat: 0,
                protein: 0,
                note: "Test meal",
                enteredBy: "Test",
                isFPU: false,
                fpuID: nil
            )
        ]

        // When
        try await storage.storeCarbs(testEntries, areFetchedFromRemote: false)
        let recentEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        )

        guard let recentEntries = recentEntries as? [CarbEntryStored] else {
            throw TestError("Failed to get recent entries")
        }

        // Then
        #expect(!recentEntries.isEmpty, "Should have stored entries")
        #expect(recentEntries.count == 1, "Should have exactly one entry")
        #expect(recentEntries[0].carbs == 20, "Carbs value should match")
        #expect(recentEntries[0].fat == 0, "Fat value should match")
        #expect(recentEntries[0].protein == 0, "Protein value should match")
        #expect(recentEntries[0].note == "Test meal", "Note should match")
    }

    @Test("Delete carbs entry") func testDeleteCarbsEntry() async throws {
        // Given
        let testEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 30,
            fat: nil,
            protein: nil,
            note: "Delete test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )

        // When
        try await storage.storeCarbs([testEntry], areFetchedFromRemote: false)

        // Get the stored entry's ObjectID
        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 30"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        guard let objectID = storedEntries?.first?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }

        // Delete the entry
        await storage.deleteCarbsEntryStored(objectID)

        // Then - verify deletion
        let remainingEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "carbs == 30"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored]

        #expect(remainingEntries?.isEmpty == true, "Should have no entries after deletion")
    }

    @Test("Get carbs not yet uploaded to Nightscout") func testGetCarbsNotYetUploadedToNightscout() async throws {
        // Given
        let testEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 40,
            fat: nil,
            protein: nil,
            note: "NS test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )

        // When
        try await storage.storeCarbs([testEntry], areFetchedFromRemote: false)
        let notUploadedEntries = try await storage.getCarbsNotYetUploadedToNightscout()

        // Then
        #expect(!notUploadedEntries.isEmpty, "Should have entries not uploaded to NS")
        #expect(notUploadedEntries[0].carbs == 40, "Carbs value should match")
    }

    @Test("Get FPUs not yet uploaded to Nightscout") func testGetFPUsNotYetUploadedToNightscout() async throws {
        // Given
        let fpuID = UUID().uuidString
        let testEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: 30,
            fat: 20,
            protein: 10,
            note: "FPU test",
            enteredBy: "Test",
            isFPU: false,
            fpuID: fpuID
        )

        // When
        try await storage.storeCarbs([testEntry], areFetchedFromRemote: false)

        // First verify all stored entries
        let allStoredEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "fpuID == %@", fpuID),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        // Then verify the stored entries
        #expect(allStoredEntries?.isEmpty == false, "Should have stored entries")
        #expect(allStoredEntries?.count ?? 0 > 1, "Should have multiple entries due to FPU splitting")

        // Original carb-non-fpu entry should be stored with original fat and protein values and isFPU set to false
        let carbNonFpuEntry = allStoredEntries?.first(where: { $0.isFPU == false })
        #expect(carbNonFpuEntry != nil, "Should have one carb non-fpu entry")
        #expect(carbNonFpuEntry?.carbs == 30, "Original carbs should match")
        #expect(carbNonFpuEntry?.protein == 10, "Original carbs should match")
        #expect(carbNonFpuEntry?.fat == 20, "Original carbs should match")

        // Additional carb-fpu entries should be created for fat/protein with isFPU set to true and the carbs set to the amount of each carbEquivalent
        let carbFpuEntry = allStoredEntries?.filter { $0.isFPU == true }
        #expect(carbFpuEntry?.isEmpty == false, "Should have additional carb-fpu entries")

        // Now test the Nightscout upload function
        let notUploadedFPUs = try await storage.getFPUsNotYetUploadedToNightscout()

        // Then verify Nightscout entries
        #expect(!notUploadedFPUs.isEmpty, "Should have FPUs not uploaded to NS")
        let fpu = notUploadedFPUs[0]
        #expect(fpu.carbs ?? 0 < 30, "Original carbs value should match")
        #expect(fpu.protein == 0, "Protein value should match")
        #expect(fpu.fat == 0, "Fat value should match")

        // Verify all entries share the same fpuID
        #expect(
            allStoredEntries?.allSatisfy { $0.fpuID?.uuidString == fpuID } == true,
            "All entries should share the same fpuID"
        )
    }

    @Test("Non-UUID entry id is replaced by a fresh UUID") func testStoreReplacesNonUUIDID() async throws {
        let mealEntry = CarbsEntry(
            id: "66f1c4c8a1b2c3d4e5f60718",
            createdAt: Date(),
            actualDate: Date(),
            carbs: 15,
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: "Test",
            isFPU: false,
            fpuID: nil
        )

        try await storage.storeCarbs([mealEntry], areFetchedFromRemote: true)

        let storedEntries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored]

        #expect(storedEntries?.count == 1)
        #expect(storedEntries?.first?.id != nil, "Entry has a UUID id")
        #expect(storedEntries?.first?.fpuID == nil, "Carb-only entry has no fpuID")
    }

    @Test("fetchMealRoot resolves the root by its id") func testFetchMealRootByID() async throws {
        let rootID = UUID()
        let meal = CarbsEntry(
            id: rootID.uuidString, createdAt: Date(), actualDate: Date(), carbs: 25, fat: 0, protein: 0,
            note: nil, enteredBy: "Test", isFPU: false, fpuID: nil
        )
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)

        let result = try await storage.fetchMealRoot(handle: rootID)

        #expect(result?.snapshot.id == rootID)
        #expect(result?.snapshot.carbs == 25)
        #expect(result?.snapshot.fpuID == nil)
    }

    @Test("fetchMealRoot resolves the root from the fpuID handle") func testFetchMealRootByFPUID() async throws {
        let rootID = UUID()
        let fpuID = UUID()
        let meal = CarbsEntry(
            id: rootID.uuidString, createdAt: Date(), actualDate: Date(), carbs: 30, fat: 50, protein: 100,
            note: "root", enteredBy: "Test", isFPU: false, fpuID: fpuID.uuidString
        )
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)

        let result = try await storage.fetchMealRoot(handle: fpuID)

        #expect(result?.snapshot.id == rootID, "Handle resolves to the root, not a carb equivalent")
        #expect(result?.snapshot.fpuID == fpuID)
        #expect(result?.snapshot.fat == 50)
    }

    @Test("fetchMealRoot resolves a fat/protein-only meal from its fpuID") func testFetchMealRootZeroCarb() async throws {
        let fpuID = UUID()
        let meal = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 0, fat: 40, protein: 60,
            note: nil, enteredBy: "Test", isFPU: false, fpuID: fpuID.uuidString
        )
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)

        let result = try await storage.fetchMealRoot(handle: fpuID)

        #expect(result != nil)
        #expect(result?.snapshot.carbs == 0)
        #expect(result?.snapshot.protein == 60)
    }

    @Test("fetchMealRoot returns nil for an unknown handle") func testFetchMealRootUnknown() async throws {
        #expect(try await storage.fetchMealRoot(handle: UUID()) == nil)
    }

    @Test("Nightscout treatments carry the fpuID of root and carb equivalents") func testNightscoutTreatmentsCarryFPUID() async throws {
        let fpuID = UUID().uuidString
        let meal = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 30, fat: 50, protein: 100,
            note: nil, enteredBy: "Test", isFPU: false, fpuID: fpuID
        )
        try await storage.storeCarbs([meal], areFetchedFromRemote: false)

        let roots = try await storage.getCarbsNotYetUploadedToNightscout()
        let children = try await storage.getFPUsNotYetUploadedToNightscout()

        #expect(roots.count == 1)
        #expect(roots.first?.id == meal.id)
        #expect(roots.first?.fpuID == fpuID)
        #expect(!children.isEmpty)
        #expect(children.allSatisfy { $0.id == fpuID && $0.fpuID == fpuID })
    }

    // MARK: - replaceCarbs

    private func allStoredRows() async throws -> [CarbEntryStored] {
        guard let rows = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: testContext,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: true
        ) as? [CarbEntryStored] else {
            throw TestError("Failed to fetch stored rows")
        }
        return rows
    }

    @Test("Replace swaps the stored values") func testReplaceCarbs() async throws {
        let original = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 25, fat: nil, protein: nil,
            note: "Before edit", enteredBy: "Test", isFPU: false, fpuID: nil
        )
        try await storage.storeCarbs([original], areFetchedFromRemote: false)
        guard let objectID = try await allStoredRows().first?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }

        let editedDate = Date(timeIntervalSince1970: 1_700_003_000)
        let edited = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: editedDate, carbs: 45, fat: 0, protein: 0,
            note: "After edit", enteredBy: "Test", isFPU: false, fpuID: nil
        )
        try await storage.replaceCarbs(objectID, with: edited)

        let rows = try await allStoredRows()
        #expect(rows.count == 1, "Edit must not duplicate or drop the entry")
        #expect(rows.first?.carbs == 45)
        #expect(rows.first?.note == "After edit")
        #expect(rows.first?.date == editedDate)
        #expect(rows.first?.id?.uuidString == edited.id)
    }

    @Test("Replace rebuilds the carb equivalents") func testReplaceCarbsRebuildsCarbEquivalents() async throws {
        let originalFpuID = UUID().uuidString
        let baseDate = Date(timeIntervalSince1970: 1_700_002_000)
        let original = CarbsEntry(
            id: UUID().uuidString, createdAt: baseDate, actualDate: baseDate, carbs: 30, fat: 200, protein: 200,
            note: "Before edit", enteredBy: "Test", isFPU: false, fpuID: originalFpuID
        )
        try await storage.storeCarbs([original], areFetchedFromRemote: false)
        guard let objectID = try await allStoredRows().first(where: { !$0.isFPU })?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }

        // Fat and protein are reduced, so the carb equivalents have to be recalculated
        let editedFpuID = UUID().uuidString
        let edited = CarbsEntry(
            id: UUID().uuidString, createdAt: baseDate, actualDate: baseDate, carbs: 30, fat: 50, protein: 100,
            note: "After edit", enteredBy: "Test", isFPU: false, fpuID: editedFpuID
        )
        try await storage.replaceCarbs(objectID, with: edited)

        let rows = try await allStoredRows()
        #expect(rows.allSatisfy { $0.fpuID?.uuidString != originalFpuID }, "Old meal and its carb equivalents are gone")

        let roots = rows.filter { !$0.isFPU }
        #expect(roots.count == 1, "Edit must leave exactly one meal root")
        #expect(roots.first?.fat == 50)
        #expect(roots.first?.protein == 100)
        #expect(roots.first?.fpuID?.uuidString == editedFpuID)

        // Tai keeps the time-cap spread: 850 kcal -> 42.5g over 8h at 30m steps -> 16 entries of 2.7g
        let carbEquivalents = rows.filter(\.isFPU)
        #expect(carbEquivalents.count == 16)
        #expect(carbEquivalents.allSatisfy { abs($0.carbs - 2.7) < 0.001 })
        #expect(carbEquivalents.allSatisfy { $0.fpuID?.uuidString == editedFpuID })
        #expect(carbEquivalents.allSatisfy { $0.isUploadedToNS == false })
    }

    @Test("Replace commits the delete and the insert in one transaction") func testReplaceCarbsIsAtomic() async throws {
        let original = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 25, fat: nil, protein: nil,
            note: nil, enteredBy: "Test", isFPU: false, fpuID: nil
        )
        try await storage.storeCarbs([original], areFetchedFromRemote: false)
        guard let objectID = try await allStoredRows().first?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }

        let saves = SaveCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: testContext,
            queue: nil
        ) { _ in saves.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let edited = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 45, fat: 0, protein: 0,
            note: nil, enteredBy: "Test", isFPU: false, fpuID: nil
        )
        try await storage.replaceCarbs(objectID, with: edited)

        #expect(saves.count == 1, "A separate delete commit would leave the meal gone if the insert then failed")
    }

    @Test("Replace of a missing meal throws and keeps the other entries") func testReplaceCarbsMissingRoot() async throws {
        let other = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 12, fat: nil, protein: nil,
            note: "Keep me", enteredBy: "Test", isFPU: false, fpuID: nil
        )
        let doomed = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: Date().addingTimeInterval(60), carbs: 25,
            fat: nil, protein: nil, note: nil, enteredBy: "Test", isFPU: false, fpuID: nil
        )
        try await storage.storeCarbs([other], areFetchedFromRemote: false)
        try await storage.storeCarbs([doomed], areFetchedFromRemote: false)
        guard let objectID = try await allStoredRows().first(where: { $0.id?.uuidString == doomed.id })?.objectID else {
            throw TestError("Failed to get stored entry's ObjectID")
        }
        await storage.deleteCarbsEntryStored(objectID)

        await #expect(throws: CoreDataError.self) {
            let replacement = CarbsEntry(
                id: UUID().uuidString, createdAt: Date(), actualDate: Date(), carbs: 99, fat: nil, protein: nil,
                note: nil, enteredBy: "Test", isFPU: false, fpuID: nil
            )
            try await storage.replaceCarbs(objectID, with: replacement)
        }

        let rows = try await allStoredRows()
        #expect(rows.count == 1)
        #expect(rows.first?.id?.uuidString == other.id, "A failed replace must not touch other meals")
    }
}

private final class SaveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
