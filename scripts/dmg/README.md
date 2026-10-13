# Habillage du DMG

`scripts/make-dmg.sh` (appelé par `make release`) copie ici :

- `fond.png` : fond de la fenêtre (660 × 400 pt à 144 dpi), dessiné par `scripts/plaque.swift dmg-bg`
  du dépôt vialetapps aux couleurs de `Brand.swift` ;
- `DS_Store` : disposition de la fenêtre enregistrée par le Finder (vue icônes, icônes de 128,
  l'app à gauche, Applications à droite, fond ci-dessus).

Les deux fichiers se régénèrent ensemble, après un changement de nom affiché, de teintes ou de
disposition :

```bash
make dmg-layout   # construit l'app, monte un DMG de travail, le Finder règle la fenêtre
git add scripts/dmg && git commit -m "DMG : fond et disposition"
```

La première fois, macOS demande d'autoriser le Terminal à piloter le Finder (Réglages Système ›
Confidentialité et sécurité › Automatisation). Sans `DS_Store`, le DMG reste valide : le Finder
l'ouvre en disposition par défaut (sans fond visible), avec l'icône de volume.

Le nom du volume (le nom affiché, sans version) doit rester celui du `DS_Store` : changer le nom
affiché impose de relancer `make dmg-layout`.
