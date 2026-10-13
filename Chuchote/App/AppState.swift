import Foundation
import Observation
import ChuchoteCore

/// Etat partage de l'app : la base, et ce que les vues observent.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let database: AppDatabase

    private init() {
        do {
            database = try AppDatabase.open()
        } catch {
            fatalError("Impossible d'ouvrir la base \(AppDatabase.defaultURL.path) : \(error)")
        }
    }
}
