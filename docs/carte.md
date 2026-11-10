# Carte de bref

## But et place
Notes Markdown éditées à plusieurs en temps réel : analyseur Markdown Go (CommonMark + GFM), hub de notes
au-dessus de trame, éditeur Flutter (maths, graphiques, commentaires, historique).
Dépend de **trame** (Go et Dart, `v0.5.0`). Dépendants : **server** (`go.mod`) et **app** (`pubspec.yaml`, ref `v0.10.1`).

## Arborescence
- `.` : paquet Go `bref`, hub de notes (`bref.go`), fils de commentaires et métadonnées (`meta.go`).
- `md/` : analyseur Markdown Go (blocs, inline, tableaux, HTML), tests de spécification et fuzz.
- `testdata/md/` : cas de référence rejoués par Go et Dart.
- `dart/lib/` : éditeur Flutter ; `src/md/` analyseur Dart, `src/math/` composition de formules, `src/chart/` graphiques.
- `dart/test/` : tests Dart, un fichier par domaine.
- `dart/fonts/` : police des maths (`latinmodern-math.otf`).

## Où est X ?
- Session (liaison au hub) : celle de trame, `trame/dart/lib/src/session.dart` ; le contrôleur ici : `dart/lib/src/controller.dart`
- Hub de notes Go : `bref.go` ; commentaires et métadonnées : `meta.go`
- Présence (curseurs des autres) : `dart/lib/src/handles.dart` ; trames : `trame/frames.go`
- Brouillon hors ligne : `dart/lib/src/local.dart`, `dart/lib/src/host_cache.dart`
- Format sur le fil : celui de trame (`trame/README.md` § Protocol) ; texte = nœud `Body` (`bref.go`)
- Analyseur Markdown Go / Dart : `md/block.go`, `md/inline.go` / `dart/lib/src/md/block.dart`, `dart/lib/src/md/inline.dart`
- Éditeur et rendu : `dart/lib/src/editor.dart`, `dart/lib/src/render.dart`
- Versions : tags `vX.Y.Z` ; `dart/pubspec.yaml` (`version:`)
- Changelog : `CHANGELOG.md`
- Épinglage de trame : `go.mod` (`require trame v0.5.0`) et `dart/pubspec.yaml` (`ref: v0.5.0`)
- Épinglage de bref chez les dépendants : `server/go.mod`, `app/pubspec.yaml`

## Construire et tester vite
Go (`GOWORK=off`) :
- vet : `GOWORK=off go vet ./...` (~1 s)
- un test : `GOWORK=off go test -run TestCommonMark ./md` (1 s, `ok`)
Dart (via nix-shell, `flutter test`, pas `dart test`) :
- analyse : `cd dart && TMPDIR=/data/tmp nix-shell ../../app/shell.nix --run 'flutter analyze'`
- un fichier : `cd dart && TMPDIR=/data/tmp nix-shell ../../app/shell.nix --run 'flutter test test/md_test.dart'`
  mesuré : 63 s au total (nix-shell compris, 1 s de test), `+1: All tests passed!`
- voie rapide (4 à 5 s au lieu de 22 s pour un fichier, mêmes sorties) : `TMPDIR=/data/tmp nix-shell ../../app/shell.nix --run 'export -p' > /data/tmp/app-env.sh` une fois, puis `cd dart && bash -c '. /data/tmp/app-env.sh; export TMPDIR=/data/tmp; flutter test -r failures-only test/<fichier>.dart'` ; détail dans app/docs/carte.md, « Construire et tester vite »
- banc : `BREF_BENCH=1 flutter test test/bench_test.dart`
Contre un trame local : `dart/pubspec_overrides.yaml` non suivi (`dependency_overrides`).

## Publier
Lecture seule, rien n'est poussé sans l'humain. 1. Si trame change, passer son tag dans `go.mod` et
`dart/pubspec.yaml`. 2. Entrée en tête de `CHANGELOG.md`. 3. `version:` de `dart/pubspec.yaml`.
4. Commit puis `git tag vX.Y.Z`. 5. Server (`go.mod`) et app (`pubspec.yaml`) changent ensuite leur version.

## Renvois
`README.md` (principes, serveur, client, blocs, maths, graphiques, Markdown, tests), `dart/README.md`, `CHANGELOG.md`.
