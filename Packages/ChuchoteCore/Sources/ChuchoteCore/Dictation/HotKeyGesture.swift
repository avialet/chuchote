import Foundation

/// Machine a etats du raccourci hybride.
///
/// - Maintenir la touche : on ecoute tant qu'elle est enfoncee ; le relachement
///   apres au moins `holdThreshold` termine la dictee.
/// - Appui bref (moins de `holdThreshold`) : l'ecoute reste verrouillee ; un
///   nouvel appui termine (son relachement est ignore).
/// - Pendant la transcription (apres `.finish`, avant `finished()`), les appuis
///   sont ignores.
/// - Un appui alors que la touche est deja enfoncee (repetition automatique) est
///   toujours ignore, meme apres une annulation ou une fin de transcription
///   survenues touche enfoncee. Un relachement manque se rattrape au cycle suivant.
///
/// L'horloge est injectee : chaque evenement porte son instant (secondes,
/// n'importe quelle origine monotone, par exemple `ProcessInfo.systemUptime`).
public struct HotKeyGesture: Sendable, Equatable {
    /// Duree minimale d'appui pour un maintien (en dessous : ecoute verrouillee).
    public static let holdThreshold: TimeInterval = 0.3

    public enum Action: Sendable, Equatable {
        case none, startListening, finish, cancel
    }

    public enum State: Sendable, Equatable {
        /// Rien en cours.
        case idle
        /// Touche enfoncee depuis `since`, ecoute en cours.
        case holding(since: TimeInterval)
        /// Appui bref relache, ecoute en cours jusqu'au prochain appui.
        case locked
        /// Ecoute terminee, transcription en cours jusqu'a `finished()`.
        case transcribing
    }

    public private(set) var state: State = .idle
    /// Touche physiquement enfoncee (dernier evenement recu : appui).
    public private(set) var isKeyDown = false

    public init() {}

    /// Vrai pendant l'ecoute (maintien ou verrouillage).
    public var isListening: Bool {
        switch state {
        case .holding, .locked: true
        case .idle, .transcribing: false
        }
    }

    public mutating func press(at time: TimeInterval) -> Action {
        // Repetition automatique : la touche n'a pas ete relachee.
        if isKeyDown { return .none }
        isKeyDown = true
        switch state {
        case .idle:
            state = .holding(since: time)
            return .startListening
        case .holding, .transcribing:
            return .none
        case .locked:
            state = .transcribing
            return .finish
        }
    }

    public mutating func release(at time: TimeInterval) -> Action {
        isKeyDown = false
        guard case .holding(let since) = state else { return .none }
        if time - since >= Self.holdThreshold {
            state = .transcribing
            return .finish
        }
        state = .locked
        return .none
    }

    /// Annule l'ecoute (Echap). Sans effet hors ecoute.
    public mutating func cancel() -> Action {
        guard isListening else { return .none }
        state = .idle
        return .cancel
    }

    /// La transcription est terminee (ou a echoue) : pret pour une nouvelle dictee.
    public mutating func finished() {
        state = .idle
    }
}
