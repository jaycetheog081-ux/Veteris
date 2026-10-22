Game Center Ressourcen vom iPhone 5 / iOS 6

Vollständige Geräte-Kopien unter device-copy/:
- Applications/Game Center~iphone.app
- Applications/GameCenterUIService.app
- System/Library/Frameworks/GameKit.framework
- System/Library/PrivateFrameworks/GameKitServices.framework
- System/Library/PrivateFrameworks/AppStoreUI.framework/GameCenterIcon@2x.png

Das TAR.GZ der Geräte-Kopien liegt bei device-copy/GameCenter-ios6.tar.gz.

Zusätzlich einzeln extrahierte PNGs:
- GameKit/Artwork/: alle 22 Bilder aus GameKit@2x~iphone.artwork
- GameKit/Framework-PNG/: lose PNG-Dateien aus GameKit.framework, darunter button,
  defaultbutton und network_button in Normal- und Pressed-Varianten
- UIKit-NavigationBar/: UINavigationBar-Hintergründe, Zurück-, Done-, Remove-,
  Add- und Zustandsbilder aus UIKit Shared@2x.artwork
- UIKit-TabBar/: UITabBar-Hintergründe, Zustände und Vorlagen für Tab-Symbole
- UIKit-ButtonBar/: UIKit ButtonBar-Grafiken und -Symbole, darunter Aktion,
  Kamera, Compose, Add, Suche, Refresh, Play/Pause, More und Zustandsbilder

Die UIKit-Bilder sind allgemeine Systemressourcen, nicht exklusiv für Game Center.
Die GameKit-Dateien stammen aus den Game-Center-bezogenen Frameworks.
Aus UIKit sind die passenden Leisten- und ButtonBar-Bilder aus Shared@2x.artwork
enthalten; das gesamte UIKit.framework ist nicht Teil dieser Kopie.
