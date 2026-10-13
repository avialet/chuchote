import Foundation

/// Acces au micro, tel que le systeme le donne.
public enum MicrophoneAccess: Sendable, Equatable {
    case authorized
    case notDetermined
    case denied
}

/// Etat de la langue de dictee (ressources du moteur).
public enum LanguageReadiness: Sendable, Equatable {
    case ready
    case preparing
    case needsInstall
    case installing(Double)
    case unsupported
    case failed(String)

    /// Avancement 0-1 de l'installation ; nil hors installation.
    public var progress: Double? {
        guard case .installing(let fraction) = self else { return nil }
        return min(max(fraction, 0), 1)
    }
}

/// Point a regler avant de dicter (carte d'accueil).
public enum SetupStep: Sendable, Equatable {
    case microphone(denied: Bool)
    case accessibility
    case language(LanguageReadiness)
}

public enum SetupChecklist {
    /// Points manquants, dans l'ordre de la carte : micro, Accessibilite (seulement si le collage
    /// direct est voulu), langue (a installer, en cours, non prise en charge ou en echec).
    public static func steps(microphone: MicrophoneAccess, accessibilityTrusted: Bool, directPaste: Bool,
                             language: LanguageReadiness) -> [SetupStep] {
        var steps: [SetupStep] = []
        switch microphone {
        case .authorized: break
        case .notDetermined: steps.append(.microphone(denied: false))
        case .denied: steps.append(.microphone(denied: true))
        }
        if directPaste && !accessibilityTrusted { steps.append(.accessibility) }
        switch language {
        case .ready, .preparing: break
        case .needsInstall, .installing, .unsupported, .failed: steps.append(.language(language))
        }
        return steps
    }
}

/// Langues de dictee : identifiants, noms affiches, listes du menu et des Reglages.
public enum LanguageChoices {
    /// Langues proposees d'abord (menu de la barre des menus et de la barre laterale).
    public static let preferred = ["fr_FR", "en_US", "en_GB", "es_ES", "de_DE", "it_IT"]

    /// << fr-FR >> et << fr_FR >> : meme langue, ecrite << fr_FR >>.
    public static func canonical(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "-", with: "_")
    }

    /// Nom en francais, majuscule initiale : << Anglais (Etats-Unis) >>.
    public static func displayName(_ identifier: String) -> String {
        let id = canonical(identifier)
        let name = Locale(identifier: "fr_FR").localizedString(forIdentifier: id) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Liste courte : la langue courante si elle n'est pas parmi les preferees, puis les preferees
    /// prises en charge. Liste encore inconnue : la langue courante seule.
    public static func short(supported: [String], current: String) -> [String] {
        let available = Set(supported.map(canonical))
        let current = canonical(current)
        var list = preferred.filter(available.contains)
        if !list.contains(current) { list.insert(current, at: 0) }
        return list
    }

    /// Toutes les langues prises en charge (et la courante), triees par nom affiche.
    public static func all(supported: [String], current: String) -> [String] {
        var ids = Set(supported.map(canonical))
        ids.insert(canonical(current))
        return ids.sorted {
            displayName($0).compare(displayName($1), options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: Locale(identifier: "fr_FR")) == .orderedAscending
        }
    }
}
