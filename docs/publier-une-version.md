# Publier une version

Tout part de git : un tag `vX.Y.Z` suffit. Les utilisateurs reçoivent ensuite
la mise à jour depuis l'application.

## Étapes

1. Mettre à jour `VERSION` (par exemple `0.2.0`). C'est le seul endroit où la
   version est écrite : `scripts/bundle.sh` la copie dans l'Info.plist
   (`CFBundleShortVersionString`) et l'app la lit dans son bundle. Le numéro de
   build (`CFBundleVersion`) est le nombre de commits (`git rev-list --count HEAD`),
   à défaut un horodatage : le panneau À propos affiche « Version 0.2.0 (42) ».
2. Écrire les notes de version dans `docs/notes/vX.Y.Z.md` (affichées dans l'app
   et sur GitHub ; sans ce fichier, elles sont générées depuis les commits).
3. `make test` : tout doit passer.
4. Commit, puis :

       git tag v0.2.0
       git push && git push --tags

5. Le workflow `Release` (`.github/workflows/release.yml`) vérifie que le tag
   égale `VERSION`, lance les tests, construit `Chuchote-0.2.0.dmg` et son
   empreinte `Chuchote-0.2.0.dmg.sha256`, puis crée la Release GitHub avec
   les deux fichiers.

Le DMG s'ouvre sur un volume « Chuchote » (sans version) : l'app, un lien
Applications, le fond et la disposition de `scripts/dmg` (`fond.png`, `DS_Store`,
produits par `make dmg-layout` et committés) et l'icône de l'app comme icône de
volume. L'app reste à la racine sous le nom `Chuchote.app` : la mise à jour
intégrée la cherche là.

## Sans passer par GitHub Actions

    make release
    gh release create v0.2.0 build/Chuchote-0.2.0.dmg build/Chuchote-0.2.0.dmg.sha256 \
      --title "Chuchote 0.2.0" --generate-notes

## Ce que l'application vérifie avant d'installer

- La Release n'est ni un brouillon ni une pré-version, et son tag est une version.
- Elle contient `Chuchote-X.Y.Z.dmg` (même version que le tag) et
  `Chuchote-X.Y.Z.dmg.sha256`, hébergés sur github.com ou son CDN, en HTTPS.
- L'empreinte SHA-256 du DMG téléchargé est celle du fichier `.sha256`.
- L'app contenue dans le DMG porte l'identifiant `fr.vialet.chuchote`, la version
  annoncée, et une signature valide.

Si une étape échoue, l'application installée n'est pas touchée. Ce code vit dans
[VialetKit](https://github.com/avialet/vialetkit) : il n'est pas copié dans l'app.

## Limite

Chuchote est signé ad hoc, sans certificat Apple Developer. L'empreinte
publiée dans la même Release protège d'un fichier corrompu, pas d'un compte GitHub
compromis. Signer et notariser avec un Developer ID supprimerait cette limite et
l'étape « Ouvrir quand même » du premier lancement : il suffit de définir
`CODESIGN_IDENTITY` pour `scripts/bundle.sh` et d'ajouter la notarisation au workflow.
