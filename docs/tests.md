# Tests

Les Command Line Tools n'embarquent ni XCTest ni Swift Testing. En attendant
Xcode, les tests du noyau vivent dans
`Packages/ChuchoteCore/Sources/chuchotecore-check/` et tournent avec :

    make test        # = swift run chuchotecore-check [filtre]

API du harnais (`Check.swift`) : `Test("nom") { ... }`, `expect(cond)`,
`expectEqual(a, b)`, `expectThrows { ... }`.

Règle : toute fonction du noyau a un test, écrit avant le code, que l'on a vu
échouer puis réussir.

## Migration vers Swift Testing (dès que Xcode est installé)

1. Déplacer les fichiers de tests vers `Packages/ChuchoteCore/Tests/ChuchoteCoreTests/`.
2. Remplacer `Test("x") {` par `@Test func x() throws {`, `expect(` par
   `#expect(`, `expectEqual(a, b)` par `#expect(a == b)`.
3. Supprimer `Check.swift`, `main.swift` et la cible `chuchotecore-check`,
   ajouter un `testTarget` dans `Package.swift`.
