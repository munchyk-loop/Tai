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
}
