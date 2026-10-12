import SwiftUI
@preconcurrency import CloudKit
import GameCore

/// The online design market, stored in the game's iCloud public database. No server: designs,
/// purchases and reports are records anyone signed in can read; only their author can change
/// them. Creators are paid when their own game reads the purchase records of their designs.
///
/// Record types (fields):
///   Design   name, creatorID, creatorName, cells (bytes), price
///   Purchase designID, designName, creatorID, buyerID, price
///   Report   designID, reporterID, reason
@MainActor
@Observable
final class CloudMarket {
    enum Status: Equatable {
        case idle, loading, ready
        case unavailable(String)
    }

    static let containerID = "iCloud.com.phoronomicstudios.neongetaway"

    private(set) var designs: [MarketDesign] = []
    private(set) var status = Status.idle

    private var database: CKDatabase { CKContainer(identifier: Self.containerID).publicCloudDatabase }

    /// Loads the newest designs with their sales and report counts.
    func refresh() async {
        status = .loading
        do {
            let query = CKQuery(recordType: "Design", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let (results, _) = try await database.records(matching: query, resultsLimit: 60)
            var found: [MarketDesign] = results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return Self.design(from: record)
            }
            if !found.isEmpty {
                let ids = found.map(\.id)
                let sales = try await count("Purchase", designIDs: ids)
                let reports = try await count("Report", designIDs: ids)
                for i in found.indices {
                    found[i].sales = sales[found[i].id] ?? 0
                    found[i].reports = reports[found[i].id] ?? 0
                }
            }
            designs = found
            status = .ready
        } catch {
            status = .unavailable(Self.explain(error))
        }
    }

    /// Puts one of the player's own designs on the market. Returns the new record's name.
    func publish(_ design: PaintDesign, price: Int, creatorID: String, creatorName: String) async -> String? {
        let record = CKRecord(recordType: "Design")
        record["name"] = design.name
        record["creatorID"] = creatorID
        record["creatorName"] = creatorName
        record["cells"] = Data(design.cells)
        record["price"] = price
        do {
            let saved = try await database.save(record)
            return saved.recordID.recordName
        } catch {
            status = .unavailable(Self.explain(error))
            return nil
        }
    }

    /// Writes the purchase that pays the creator. Retried on the next launch if it fails.
    func recordPurchase(_ design: MarketDesign, buyerID: String) async -> Bool {
        let record = CKRecord(recordType: "Purchase")
        record["designID"] = design.id
        record["designName"] = design.name
        record["creatorID"] = design.creatorID
        record["buyerID"] = buyerID
        record["price"] = design.price
        do {
            _ = try await database.save(record)
            if let i = designs.firstIndex(where: { $0.id == design.id }) { designs[i].sales += 1 }
            return true
        } catch {
            return false
        }
    }

    func report(_ design: MarketDesign, reason: OnlineMarket.ReportReason, reporterID: String) async -> Bool {
        let record = CKRecord(recordType: "Report")
        record["designID"] = design.id
        record["reporterID"] = reporterID
        record["reason"] = reason.rawValue
        do {
            _ = try await database.save(record)
            if let i = designs.firstIndex(where: { $0.id == design.id }) { designs[i].reports += 1 }
            return true
        } catch {
            return false
        }
    }

    /// Every purchase of the player's designs (the app pays the ones not yet paid).
    func sales(of creatorID: String) async -> [MarketPurchase]? {
        do {
            let query = CKQuery(recordType: "Purchase", predicate: NSPredicate(format: "creatorID == %@", creatorID))
            let (results, _) = try await database.records(matching: query, resultsLimit: 200)
            return results.compactMap { _, result in
                guard let r = try? result.get(),
                      let designID = r["designID"] as? String,
                      let creator = r["creatorID"] as? String,
                      let buyer = r["buyerID"] as? String,
                      let price = r["price"] as? Int else { return nil }
                return MarketPurchase(id: r.recordID.recordName, designID: designID,
                                      designName: r["designName"] as? String ?? "Design", creatorID: creator,
                                      buyerID: buyer, price: price, created: r.creationDate ?? Date())
            }
        } catch {
            return nil
        }
    }

    private func count(_ type: String, designIDs: [String]) async throws -> [String: Int] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(format: "designID IN %@", designIDs))
        let (results, _) = try await database.records(matching: query, desiredKeys: ["designID"], resultsLimit: 400)
        var counts: [String: Int] = [:]
        for (_, result) in results {
            if let id = (try? result.get())?["designID"] as? String { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private static func design(from r: CKRecord) -> MarketDesign? {
        guard let name = r["name"] as? String,
              let creatorID = r["creatorID"] as? String,
              let data = r["cells"] as? Data,
              let price = r["price"] as? Int else { return nil }
        return MarketDesign(id: r.recordID.recordName, name: name, creatorID: creatorID,
                            creatorName: r["creatorName"] as? String ?? "Driver", cells: [UInt8](data),
                            price: price, created: r.creationDate ?? Date())
    }

    private static func explain(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return "Sign in to iCloud in Settings to use the online market."
            case .networkUnavailable, .networkFailure: return "No connection. The online market needs the internet."
            default: break
            }
        }
        return "The online market isn't reachable right now."
    }
}
