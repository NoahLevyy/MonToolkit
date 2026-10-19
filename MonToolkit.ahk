#Requires AutoHotkey v2.0
#SingleInstance Force
A_IconTip := "Mon Toolkit"

; =====================================================================
;  MON TOOLKIT — Espanso + Twinkle Tray + File Converter, en un script
;  Ctrl + Alt + H  →  affiche l'aide
;
;  Tes infos perso (adresses e-mail, nom…) sont dans config.ini,
;  qui n'est jamais envoyé sur GitHub (voir .gitignore).
; =====================================================================


; =====================================================================
;  1. RACCOURCIS TEXTE (façon Espanso)
;     Tape ;raccourci n'importe où, il est remplacé tout de suite.
;     Les raccourcis se règlent dans config.ini, section [Raccourcis].
;     ;date et ;heure sont intégrés au script.
; =====================================================================
global CONFIG := A_ScriptDir "\config.ini"
global CONFIG_EXEMPLE := A_ScriptDir "\config.exemple.ini"
global g_raccourcis := ChargerRaccourcis()

for paire in g_raccourcis {
    try Hotstring(":*?T:;" paire[1], paire[2])
    catch
        TrayTip "Raccourci invalide dans config.ini : " paire[1], "Mon Toolkit"
}

:*?:;date::
{
    SendText FormatTime(, "dd/MM/yyyy")
}

:*?:;heure::
{
    SendText FormatTime(, "HH:mm")
}

ChargerRaccourcis() {
    global CONFIG, CONFIG_EXEMPLE
    if !FileExist(CONFIG) {
        if FileExist(CONFIG_EXEMPLE) {
            FileCopy CONFIG_EXEMPLE, CONFIG
            MsgBox "Premier lancement : config.ini vient d'être créé.`n`n"
                . "Remplace les exemples par tes vraies infos, enregistre,`n"
                . "puis clic droit sur l'icône du toolkit → Recharger.", "Mon Toolkit", "Iconi"
            Run 'notepad "' CONFIG '"'
        } else {
            return []
        }
    }
    liste := [], section := ""
    for ligne in StrSplit(FileRead(CONFIG, "UTF-8"), "`n", "`r") {
        ligne := Trim(ligne)
        if (ligne = "" || SubStr(ligne, 1, 1) = ";" || SubStr(ligne, 1, 1) = "#")
            continue
        if RegExMatch(ligne, "^\[(.+)\]$", &m) {
            section := m[1]
            continue
        }
        if (section = "Raccourcis" && (p := InStr(ligne, "="))) {
            cle := Trim(SubStr(ligne, 1, p - 1))
            valeur := StrReplace(Trim(SubStr(ligne, p + 1)), "\n", "`n")
            if (cle != "" && valeur != "")
                liste.Push([cle, valeur])
        }
    }
    return liste
}


; =====================================================================
;  2. LUMINOSITÉ DES ÉCRANS (façon Twinkle Tray)
;     Ctrl + Alt + ↑ / ↓        →  +10 % / -10 %
;     Molette sur la barre des tâches  →  +5 % / -5 %
;     Marche sur l'écran d'un portable ET sur les écrans externes
;     (DDC/CI, à activer dans le menu de l'écran s'il est désactivé).
; =====================================================================
global g_delta := 0, g_niveau := -1

^!Up::AjusterLuminosite(10)
^!Down::AjusterLuminosite(-10)

#HotIf SourisSurBarreDesTaches()
WheelUp::AjusterLuminosite(5)
WheelDown::AjusterLuminosite(-5)
#HotIf

SourisSurBarreDesTaches() {
    MouseGetPos(, , &win)
    return WinExist("ahk_class Shell_TrayWnd ahk_id " win)
        || WinExist("ahk_class Shell_SecondaryTrayWnd ahk_id " win)
}

AjusterLuminosite(delta) {
    global g_delta, g_niveau
    g_delta := delta, g_niveau := -1

    ; Écrans externes (DDC/CI)
    cb := CallbackCreate(_EcranExterne, "F", 4)
    DllCall("EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)

    ; Écran intégré d'un portable (WMI)
    try {
        wmi := ComObjGet("winmgmts:\\.\root\WMI")
        for m in wmi.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness WHERE Active=TRUE")
            niveau := Max(0, Min(100, m.CurrentBrightness + delta))
        for m in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE")
            m.WmiSetBrightness(1, niveau)
        g_niveau := niveau
    }

    ToolTip g_niveau >= 0 ? "☀ " g_niveau " %" : "Aucun écran compatible (active DDC/CI dans le menu de l'écran)"
    SetTimer () => ToolTip(), -1200
}

_EcranExterne(hMon, hdc, pRect, lParam) {
    global g_delta, g_niveau
    nb := 0
    if !DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt*", &nb) || !nb
        return 1
    taille := A_PtrSize + 256          ; struct PHYSICAL_MONITOR
    buf := Buffer(taille * nb, 0)
    if DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt", nb, "Ptr", buf) {
        loop nb {
            h := NumGet(buf, (A_Index - 1) * taille, "Ptr")
            bas := 0, actuel := 0, haut := 0
            if DllCall("dxva2\GetMonitorBrightness", "Ptr", h, "UInt*", &bas, "UInt*", &actuel, "UInt*", &haut) {
                niveau := Max(bas, Min(haut, actuel + g_delta))
                DllCall("dxva2\SetMonitorBrightness", "Ptr", h, "UInt", niveau)
                g_niveau := niveau
            }
        }
        DllCall("dxva2\DestroyPhysicalMonitors", "UInt", nb, "Ptr", buf)
    }
    return 1
}


; =====================================================================
;  3. CONVERTISSEUR DE FICHIERS (façon File Converter)
;     Sélectionne un ou plusieurs fichiers dans l'Explorateur ou sur le
;     Bureau, puis  Ctrl + Alt + C  →  menu de conversion.
;     Le résultat est créé à côté de l'original (l'original est gardé).
;     Nécessite FFmpeg (vidéo/audio) et ImageMagick (images).
; =====================================================================
#HotIf WinActive("ahk_class CabinetWClass") || WinActive("ahk_class Progman") || WinActive("ahk_class WorkerW")
^!c::MenuConversion()
#HotIf

MenuConversion() {
    fichiers := FichiersSelectionnes()
    if !fichiers.Length {
        ToolTip "Sélectionne d'abord un ou plusieurs fichiers"
        SetTimer () => ToolTip(), -1500
        return
    }

    SplitPath fichiers[1], , , &ext
    ext := StrLower(ext)
    m := Menu()

    if EstImage(ext) {
        for cible in ["png", "jpg", "webp", "pdf", "ico"]
            if (cible != ext && !(cible = "jpg" && ext = "jpeg"))
                m.Add "Image → " StrUpper(cible), Convertir.Bind(fichiers, "image", cible)
        m.Add "Compresser (JPG qualité 80 %)", Convertir.Bind(fichiers, "image", "compresser")
        if fichiers.Length > 1
            m.Add "Fusionner en un seul PDF", FusionnerPdf.Bind(fichiers)
    } else if EstVideo(ext) {
        if ext != "mp4"
            m.Add "Vidéo → MP4", Convertir.Bind(fichiers, "video", "mp4")
        m.Add "Vidéo → MP3 (extraire le son)", Convertir.Bind(fichiers, "video", "mp3")
        m.Add "Vidéo → GIF", Convertir.Bind(fichiers, "video", "gif")
        m.Add "Compresser la vidéo (MP4 plus léger)", Convertir.Bind(fichiers, "video", "compresser")
    } else if EstAudio(ext) {
        for cible in ["mp3", "wav", "m4a"]
            if cible != ext
                m.Add "Audio → " StrUpper(cible), Convertir.Bind(fichiers, "audio", cible)
    } else {
        ToolTip "Format ." ext " pas pris en charge"
        SetTimer () => ToolTip(), -1500
        return
    }
    m.Show()
}

Convertir(fichiers, genre, cible, *) {
    outil := (genre = "image") ? "magick" : "ffmpeg"
    if !OutilDispo(outil) {
        MsgBox outil " n'est pas installé (ou le PC n'a pas été redémarré depuis l'installation).", "Convertisseur", "Icon!"
        return
    }
    reussis := 0
    for src in fichiers {
        SplitPath src, , &dossier, &extSrc, &nom
        extSortie := (cible = "compresser") ? (genre = "image" ? "jpg" : "mp4") : cible
        sortie := CheminLibre(dossier "\" nom, extSortie)
        ToolTip "Conversion " A_Index " / " fichiers.Length "…"
        try {
            RunWait Commande(genre, cible, src, StrLower(extSrc), sortie), , "Hide"
            if FileExist(sortie)
                reussis++
        }
    }
    ToolTip
    TrayTip reussis " / " fichiers.Length " fichier(s) converti(s)", "Convertisseur"
}

Commande(genre, cible, src, extSrc, sortie) {
    entree := (extSrc = "gif" && genre = "image") ? src "[0]" : src
    if genre = "image" {
        if cible = "ico"
            return 'magick "' entree '" -resize 256x256 "' sortie '"'
        if cible = "compresser"
            return 'magick "' entree '" -background white -flatten -quality 80 "' sortie '"'
        if (cible = "jpg" || cible = "pdf")
            return 'magick "' entree '" -background white -flatten "' sortie '"'
        return 'magick "' entree '" "' sortie '"'
    }
    base := 'ffmpeg -hide_banner -loglevel error -y -i "' src '" '
    switch cible {
        case "mp4":        return base '-c:v libx264 -crf 23 -preset fast -c:a aac "' sortie '"'
        case "compresser": return base '-c:v libx264 -crf 28 -preset fast -c:a aac -b:a 128k "' sortie '"'
        case "mp3":        return base '-vn -q:a 2 "' sortie '"'
        case "wav":        return base '-vn "' sortie '"'
        case "m4a":        return base '-vn -c:a aac -b:a 192k "' sortie '"'
        case "gif":        return base '-vf "fps=12,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" "' sortie '"'
    }
}

FusionnerPdf(fichiers, *) {
    if !OutilDispo("magick") {
        MsgBox "ImageMagick n'est pas installé.", "Convertisseur", "Icon!"
        return
    }
    SplitPath fichiers[1], , &dossier
    sortie := CheminLibre(dossier "\fusion", "pdf")
    liste := ""
    for f in fichiers
        liste .= '"' f '" '
    ToolTip "Création du PDF…"
    try RunWait 'magick ' liste '-background white -flatten "' sortie '"', , "Hide"
    ToolTip
    TrayTip FileExist(sortie) ? "PDF créé : fusion.pdf" : "Échec de la fusion", "Convertisseur"
}

; ---------- utilitaires ----------
FichiersSelectionnes() {
    sauvegarde := ClipboardAll()
    A_Clipboard := ""
    Send "^c"
    fichiers := []
    if ClipWait(1) {
        for ligne in StrSplit(A_Clipboard, "`n", "`r") {
            attr := FileExist(ligne)
            if (ligne != "" && attr && !InStr(attr, "D"))
                fichiers.Push(ligne)
        }
    }
    A_Clipboard := sauvegarde
    return fichiers
}

CheminLibre(base, ext) {
    chemin := base "." ext, i := 1
    while FileExist(chemin)
        chemin := base " (" i++ ")." ext
    return chemin
}

OutilDispo(nom) {
    try return RunWait(nom " -version", , "Hide") = 0
    catch
        return false
}

EstImage(e) => e ~= "^(png|jpe?g|webp|bmp|gif|tiff?|heic|avif|ico)$"
EstVideo(e) => e ~= "^(mp4|mov|mkv|avi|webm|m4v|wmv)$"
EstAudio(e) => e ~= "^(mp3|wav|m4a|aac|flac|ogg|opus|wma)$"


; =====================================================================
;  MENU DE L'ICÔNE (en bas à droite) + AIDE
; =====================================================================
global lienDemarrage := A_Startup "\MonToolkit.lnk"

A_TrayMenu.Insert "1&", "Aide (Ctrl+Alt+H)", (*) => Aide()
A_TrayMenu.Insert "2&", "Modifier mes raccourcis texte", (*) => Run('notepad "' CONFIG '"')
A_TrayMenu.Insert "3&", "Recharger", (*) => Reload()
A_TrayMenu.Insert "4&", "Lancer au démarrage de Windows", BasculerDemarrage
A_TrayMenu.Insert "5&"
if FileExist(lienDemarrage)
    A_TrayMenu.Check "Lancer au démarrage de Windows"

BasculerDemarrage(nomItem, *) {
    global lienDemarrage
    if FileExist(lienDemarrage) {
        FileDelete lienDemarrage
        A_TrayMenu.Uncheck nomItem
    } else {
        FileCreateShortcut A_ScriptFullPath, lienDemarrage
        A_TrayMenu.Check nomItem
    }
}

^!h::Aide()

Aide() {
    global g_raccourcis
    texte := "RACCOURCIS TEXTE`n"
    for paire in g_raccourcis {
        apercu := StrReplace(paire[2], "`n", " ↵ ")
        if StrLen(apercu) > 40
            apercu := SubStr(apercu, 1, 40) "…"
        texte .= "   `;" Format("{:-10}", paire[1]) "  →  " apercu "`n"
    }
    texte .= "   `;date        →  date du jour`n"
    texte .= "   `;heure       →  heure actuelle`n`n"
    texte .= "LUMINOSITÉ`n"
    texte .= "   Ctrl + Alt + ↑ / ↓               →  +10 % / -10 %`n"
    texte .= "   Molette sur la barre des tâches  →  +5 % / -5 %`n`n"
    texte .= "CONVERTISSEUR`n"
    texte .= "   Sélectionne des fichiers, puis Ctrl + Alt + C`n`n"
    texte .= "AIDE`n"
    texte .= "   Ctrl + Alt + H"
    MsgBox texte, "Mon Toolkit"
}
