import CoreData

/// Core Data stack + document CRUD operations.
/// All mutations run on the view context on the main actor.
@Observable
@MainActor
final class DocumentStore {
    private(set) var documents: [SplineDocument] = []
    private let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "Persistence")
        container.loadPersistentStores { _, error in
            if let error {
                // A fatal error here means the store schema is unreadable
                // (e.g. after a breaking migration). Surface clearly rather than crashing silently.
                fatalError("Core Data store failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Fetch

    func loadAllDocuments() async {
        let request = DocumentEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        do {
            let entities = try container.viewContext.fetch(request)
            documents = entities.compactMap(SplineDocument.init(entity:))
        } catch {
            print("Failed to fetch documents: \(error.localizedDescription)")
        }
    }

    // MARK: - Create

    func createDocument(title: String = "Untitled") async -> SplineDocument {
        let context = container.viewContext
        let entity = DocumentEntity(context: context)
        entity.id = UUID()
        entity.title = title
        entity.createdAt = .now
        entity.modifiedAt = .now
        saveContext(context)
        let doc = SplineDocument(id: entity.id!, title: title)
        documents.insert(doc, at: 0)
        return doc
    }

    // MARK: - Save strokes

    func saveStrokes(_ strokes: [Stroke], for documentID: UUID) async {
        let context = container.viewContext
        let request = DocumentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }

        // Remove old strokes and replace wholesale — simpler than diffing.
        let existingStrokes = entity.strokes as? Set<StrokeEntity> ?? []
        existingStrokes.forEach { context.delete($0) }

        for stroke in strokes {
            let strokeEntity = StrokeEntity(context: context)
            strokeEntity.populate(from: stroke, document: entity)
        }

        entity.modifiedAt = .now
        saveContext(context)
    }

    // MARK: - Delete

    func deleteDocument(_ document: SplineDocument) async {
        let context = container.viewContext
        let request = DocumentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", document.id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        context.delete(entity)
        saveContext(context)
        documents.removeAll { $0.id == document.id }
    }

    // MARK: - Helpers

    private func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Core Data save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - SplineDocument ← DocumentEntity

private extension SplineDocument {
    /// Converts a Core Data entity into the in-memory document model.
    init?(entity: DocumentEntity) {
        guard let id = entity.id, let title = entity.title,
              let createdAt = entity.createdAt, let modifiedAt = entity.modifiedAt else {
            return nil
        }
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.canvasOrigin = CGPoint(x: entity.canvasOriginX, y: entity.canvasOriginY)
        self.canvasScale = entity.canvasScale == 0 ? 1.0 : CGFloat(entity.canvasScale)

        let strokeEntities = (entity.strokes as? Set<StrokeEntity> ?? [])
            .sorted { ($0.startTime ?? .distantPast) < ($1.startTime ?? .distantPast) }
        self.strokes = strokeEntities.compactMap(Stroke.init(entity:))
    }
}

// MARK: - Stroke ← StrokeEntity

private extension Stroke {
    init?(entity: StrokeEntity) {
        guard let id = entity.id, let sessionID = entity.sessionID,
              let startTime = entity.startTime, let endTime = entity.endTime,
              let tool = entity.tool, let toolType = ToolType(rawValue: tool),
              let pointsData = entity.pointsData else {
            return nil
        }
        self.id = id
        self.sessionID = sessionID
        self.startTime = startTime
        self.endTime = endTime
        self.isComplete = true
        self.style = StrokeStyle(
            color: SIMD4(entity.colorR, entity.colorG, entity.colorB, entity.colorA),
            lineWidth: CGFloat(entity.lineWidth),
            opacity: CGFloat(entity.opacity),
            tool: toolType
        )
        // Decode the binary point array. If decoding fails the stroke is discarded.
        guard let points = try? JSONDecoder().decode([StrokePoint].self, from: pointsData) else {
            return nil
        }
        self.points = points
        self.canvasBounds = points.reduce(CGRect.null) { acc, pt in
            acc == .null ? CGRect(origin: pt.position, size: .zero) : acc.union(CGRect(origin: pt.position, size: .zero))
        }
    }
}

// MARK: - StrokeEntity population

private extension StrokeEntity {
    func populate(from stroke: Stroke, document: DocumentEntity) {
        id = stroke.id
        sessionID = stroke.sessionID
        startTime = stroke.startTime
        endTime = stroke.endTime
        colorR = stroke.style.color.x
        colorG = stroke.style.color.y
        colorB = stroke.style.color.z
        colorA = stroke.style.color.w
        lineWidth = Float(stroke.style.lineWidth)
        opacity = Float(stroke.style.opacity)
        tool = stroke.style.tool.rawValue
        // Encode points as binary — individual Core Data entities would be extremely slow
        // for the thousands of points a single stroke can produce.
        pointsData = try? JSONEncoder().encode(stroke.points)
        self.document = document
    }
}
