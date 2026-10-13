import Foundation

/// Mise au propre du texte dicte avant collage. Idempotente : l'appliquer deux
/// fois donne le meme resultat qu'une seule.
///
/// 1. Espaces : suites d'espaces et de tabulations reduites a une espace, espaces
///    autour des retours a la ligne et aux bords retirees.
/// 2. Typographie francaise (langue `fr*` et option active) :
///    guillemets droits `"..."` -> `\u{00AB}\u{00A0}...\u{00A0}\u{00BB}`, espaces internes des
///    guillemets francais normalisees, espace fine insecable (U+202F) avant `? ! ;`,
///    insecable (U+00A0) avant `:`, apostrophe typographique (U+2019) entre lettres.
///    La ponctuation n'est traitee que suivie d'une espace, de la fin du texte ou
///    d'une autre ponctuation haute : `10:30`, `https://`, `?x=1` restent intacts ;
///    rien non plus juste apres une adresse (`https://exemple.fr?`, `jean@exemple.fr!`).
/// 3. Majuscule initiale, sauf si le texte commence par un nombre, une adresse
///    (`@`, `://`, `www.`) ou un mot a majuscule interne (`iPhone`), examinee apres la
///    derniere apostrophe (`l'Europe` prend sa majuscule).
/// 4. Point final si le texte finit par une lettre ou un chiffre, sauf apres une
///    adresse (lien ou e-mail), pour qu'elle reste copiable telle quelle.
public enum Polish {
    public static func apply(_ text: String, locale: String, frenchTypography: Bool) -> String {
        var s = cleanSpaces(text)
        guard !s.isEmpty else { return s }
        if frenchTypography && isFrench(locale) { s = frenchTypographyApplied(s) }
        s = capitalizingFirstLetter(s)
        s = addingFinalPeriod(s)
        return s
    }

    /// `fr`, `fr-FR`, `fr_CA`... (insensible a la casse).
    public static func isFrench(_ locale: String) -> Bool {
        let l = locale.lowercased()
        return l == "fr" || l.hasPrefix("fr-") || l.hasPrefix("fr_")
    }

    // MARK: - Etapes

    private static func cleanSpaces(_ text: String) -> String {
        text
            .regexReplacing(#"[ \t]+"#, with: " ")
            .regexReplacing(#" ?\n ?"#, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func frenchTypographyApplied(_ text: String) -> String {
        let nbsp = "\u{00A0}"
        let nnbsp = "\u{202F}"
        // Espaces ordinaires ou insecables, a remplacer par la bonne.
        let spaces = #"[ \u00A0\u202F]*"#
        // Apres la ponctuation : espace, fin, ou autre ponctuation haute.
        let after = #"(?=\s|$|[?!;:\u00BB])"#
        return text
            .regexReplacing(#"""# + spaces + #"([^"\n]+?)"# + spaces + #"""#, with: "\u{00AB}\(nbsp)$1\(nbsp)\u{00BB}")
            .regexReplacing(#"\u00AB"# + spaces, with: "\u{00AB}\(nbsp)")
            .regexReplacing(spaces + #"\u00BB"#, with: "\(nbsp)\u{00BB}")
            .regexReplacing(#"([^\s?!;:])"# + spaces + #"([?!;])"# + after, with: "$1\(nnbsp)$2",
                            unlessTokenBefore: isAddress)
            .regexReplacing(#"([^\s?!;:])"# + spaces + ":" + after, with: "$1\(nbsp):",
                            unlessTokenBefore: isAddress)
            .regexReplacing(#"(\p{L})'(?=\p{L})"#, with: "$1\u{2019}")
    }

    private static func capitalizingFirstLetter(_ text: String) -> String {
        if let first = text.split(whereSeparator: \.isWhitespace).first, isAddress(first) { return text }
        guard let index = text.firstIndex(where: { $0.isLetter || $0.isNumber }),
              text[index].isLetter, text[index].isLowercase else { return text }
        // Majuscule interne (iPhone) : seulement apres la derniere apostrophe (l'Europe).
        let word = text[index...].prefix { !$0.isWhitespace }
        let stem = word.split(whereSeparator: { $0 == "'" || $0 == "\u{2019}" }).last ?? word
        if stem.dropFirst().contains(where: \.isUppercase) { return text }
        var result = text
        result.replaceSubrange(index...index, with: text[index].uppercased())
        return result
    }

    private static func addingFinalPeriod(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        if let token = text.split(whereSeparator: \.isWhitespace).last, isAddress(token) { return text }
        return text + "."
    }

    /// Lien ou e-mail : a laisser tel quel.
    private static func isAddress(_ token: Substring) -> Bool {
        token.contains("@") || token.contains("://") || token.lowercased().hasPrefix("www.")
    }
}

private extension String {
    /// Remplacement par expression reguliere ICU (gabarit avec `$1`...).
    func regexReplacing(_ pattern: String, with template: String) -> String {
        replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Idem, mais une occurrence reste intacte si le mot qui la precede (du dernier
    /// blanc jusqu'a la fin du premier groupe) verifie `skip`.
    func regexReplacing(_ pattern: String, with template: String,
                        unlessTokenBefore skip: (Substring) -> Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let ns = self as NSString
        let result = NSMutableString(string: self)
        // De la fin vers le debut : les plages deja lues restent valides.
        for match in regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).reversed() {
            let groupEnd = match.range(at: 1).upperBound
            let head = ns.substring(to: groupEnd)
            let token = head.split(whereSeparator: \.isWhitespace).last ?? ""
            if skip(token) { continue }
            let replacement = regex.replacementString(for: match, in: self, offset: 0, template: template)
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }
}
