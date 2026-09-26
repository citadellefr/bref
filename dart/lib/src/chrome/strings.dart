/// The words of the editors, as the French version of Office has them.
class BrefStrings {
  const BrefStrings();

  // ribbon tabs
  String get file => 'Fichier';
  String get home => 'Accueil';
  String get insert => 'Insertion';
  String get design => 'Création';
  String get transitions => 'Transitions';
  String get slideShow => 'Diaporama';
  String get review => 'Révision';
  String get view => 'Affichage';

  // groups and commands
  String get clipboard => 'Presse-papiers';
  String get paste => 'Coller';
  String get cut => 'Couper';
  String get copy => 'Copier';
  String get slides => 'Diapositives';
  String get newSlide => 'Nouvelle diapositive';
  String get duplicateSlide => 'Dupliquer la diapositive';
  String get deleteSlide => 'Supprimer la diapositive';
  String get hideSlide => 'Masquer la diapositive';
  String get layout => 'Disposition';
  String get font => 'Police';
  String get fontSize => 'Taille de police';
  String get growFont => 'Augmenter la taille de police';
  String get shrinkFont => 'Réduire la taille de police';
  String get bold => 'Gras';
  String get italic => 'Italique';
  String get underline => 'Souligné';
  String get strikethrough => 'Barré';
  String get fontColor => 'Couleur de police';
  String get highlight => 'Couleur de surbrillance du texte';
  String get paragraph => 'Paragraphe';
  String get bullets => 'Puces';
  String get numbering => 'Numérotation';
  String get decreaseLevel => 'Diminuer le niveau de liste';
  String get increaseLevel => 'Augmenter le niveau de liste';
  String get alignLeft => 'Aligner à gauche';
  String get center => 'Centrer';
  String get alignRight => 'Aligner à droite';
  String get justify => 'Justifier';
  String get drawing => 'Dessin';
  String get shapes => 'Formes';
  String get textBox => 'Zone de texte';
  String get shapeFill => 'Remplissage de forme';
  String get shapeOutline => 'Contour de forme';
  String get noFill => 'Aucun remplissage';
  String get noOutline => 'Sans contour';
  String get arrange => 'Organiser';
  String get bringForward => 'Avancer';
  String get sendBackward => 'Reculer';
  String get bringToFront => 'Mettre au premier plan';
  String get sendToBack => 'Mettre à l’arrière-plan';
  String get startSlideShow => 'Lancer le diaporama';
  String get fromBeginning => 'À partir du début';
  String get fromCurrentSlide => 'À partir de la diapositive actuelle';
  String get presentationViews => 'Affichages des présentations';
  String get normal => 'Normal';
  String get slideSorter => 'Trieuse de diapositives';
  String get notes => 'Commentaires';
  String get show => 'Afficher';
  String get undo => 'Annuler';
  String get redo => 'Rétablir';
  String get delete => 'Supprimer';
  String get themeColors => 'Couleurs du thème';
  String get standardColors => 'Couleurs standard';
  String get automatic => 'Automatique';

  // backstage
  String get info => 'Informations';
  String get close => 'Fermer';
  String get back => 'Retour';
  String get editedBy => 'Modifié par';

  // status
  String slideOf(int n, int of) => 'Diapositive $n sur $of';
  String get language => 'Français (France)';
  String get saved => 'Enregistré';
  String get saving => 'Enregistrement…';
  String get offline => 'Hors connexion : vos modifications seront envoyées au retour de la connexion';
  String get connecting => 'Connexion…';
  String saveFailed(String reason) => 'Échec de l’enregistrement : $reason';
  String get readOnly => 'Lecture seule';
  String get retry => 'Réessayer';
  String get notesPrompt => 'Cliquez pour ajouter des commentaires';
  String get refused => 'Modification refusée';

  // placeholders
  String prompt(String kind) => switch (kind) {
    'title' => 'Cliquez pour ajouter un titre',
    'ctrTitle' => 'Cliquez pour ajouter un titre',
    'subTitle' => 'Cliquez pour ajouter un sous-titre',
    'dt' || 'ftr' || 'sldNum' || 'hdr' => '',
    _ => 'Cliquez pour ajouter du texte',
  };
  String get table => 'Tableau';
  String get chart => 'Graphique';
  String get diagram => 'SmartArt';
  String get object => 'Objet';
  String get shapeName => 'Forme';
  String get textBoxName => 'ZoneTexte';
  String get endOfShow => 'Fin du diaporama, cliquez pour quitter.';
}
