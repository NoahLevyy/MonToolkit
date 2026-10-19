# Mon Toolkit

Un seul script [AutoHotkey v2](https://www.autohotkey.com/) léger (≈ 3 Mo de RAM, 0 % de CPU au repos) qui regroupe trois outils du quotidien sous Windows :

| Outil | Inspiré de | Ce qu'il fait |
|---|---|---|
| **Raccourcis texte** | Espanso | Tape `;mail` → ton adresse e-mail s'écrit toute seule |
| **Luminosité** | Twinkle Tray | Règle la luminosité de tous tes écrans au clavier ou à la molette |
| **Convertisseur** | File Converter | Convertit images, vidéos et sons en deux touches |

## Raccourcis

| Raccourci | Action |
|---|---|
| `;mail`, `;ecole`, `;nom`, `;cordia`… | Raccourcis texte définis dans `config.ini` |
| `;date` | Date du jour (`19/10/2026`) |
| `;heure` | Heure actuelle (`14:32`) |
| Barre ☀ sur la barre des tâches | Clic, glisser ou molette pour régler la luminosité |
| Clic sur l'icône du toolkit ou `Ctrl` + `Alt` + `L` | Afficher / masquer la barre |
| `Ctrl` + `Alt` + `↑` / `↓` | Luminosité +10 % / -10 % |
| Molette sur la barre des tâches | Luminosité +5 % / -5 % |
| `Ctrl` + `Alt` + `C` (fichiers sélectionnés) | Menu de conversion |
| `Ctrl` + `Alt` + `H` | Aide |

### Conversions disponibles

- **Images** → PNG, JPG, WEBP, PDF, ICO, compression JPG, fusion de plusieurs images en un PDF
- **Vidéos** → MP4, MP3 (extraire le son), GIF, compression
- **Audio** → MP3, WAV, M4A

Le fichier converti est créé à côté de l'original, qui n'est jamais modifié.

## Installation

1. Installe les dépendances (Terminal en administrateur) :
   ```powershell
   winget install AutoHotkey.AutoHotkey Gyan.FFmpeg ImageMagick.ImageMagick
   ```
   FFmpeg et ImageMagick ne servent qu'au convertisseur.
2. Redémarre le PC pour que FFmpeg et ImageMagick soient trouvés.
3. Clone ou télécharge ce dépôt, puis double-clique sur `MonToolkit.ahk`.
4. Au premier lancement, `config.ini` est créé à partir de `config.exemple.ini` et s'ouvre dans le Bloc-notes : mets tes vraies infos, enregistre, puis clic droit sur l'icône du toolkit → **Recharger**.
5. Clic droit sur l'icône → **Lancer au démarrage de Windows**.

## Personnaliser ses raccourcis texte

Dans `config.ini`, section `[Raccourcis]`, une ligne par raccourci :

```ini
[Raccourcis]
mail=prenom.nom@gmail.com
cordia=Cordialement,\nPrénom Nom
```

`\n` crée un retour à la ligne. Le `;` devant le raccourci est ajouté automatiquement.

`config.ini` est listé dans `.gitignore` : tes données personnelles restent sur ton PC et ne sont jamais publiées.

## Barre de luminosité

Une petite barre est posée en permanence sur la barre des tâches, juste à gauche des icônes. Elle se cache toute seule quand une appli passe en plein écran. Sa position se règle dans `config.ini`, section `[Barre]` (`auto`, `gauche`, ou une distance en pixels depuis le bord droit).

## Luminosité des écrans externes

Les écrans externes sont pilotés en DDC/CI. Si rien ne bouge, active l'option **DDC/CI** dans le menu intégré de l'écran (boutons physiques).

## Licence

[MIT](LICENSE)
