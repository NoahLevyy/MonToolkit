#Requires AutoHotkey v2.0
#SingleInstance Force
A_IconTip := "Mon Toolkit"
if FileExist(A_ScriptDir "\icone.ico")
    TraySetIcon A_ScriptDir "\icone.ico"

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
global g_options := Map()                ; autres réglages de config.ini (ex. "Barre.position")
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
    global CONFIG, CONFIG_EXEMPLE, g_options
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
        if (section != "Raccourcis" && (p := InStr(ligne, "="))) {
            g_options[section "." Trim(SubStr(ligne, 1, p - 1))] := Trim(SubStr(ligne, p + 1))
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
;     Barre fixe sur la barre des tâches : clic / glisser / molette
;     Clic sur l'icône du toolkit ou Ctrl + Alt + L  →  afficher / masquer la barre
;     Ctrl + Alt + ↑ / ↓                            →  +10 % / -10 %
;     Molette sur la barre des tâches               →  +5 % / -5 %
;     Marche sur l'écran d'un portable ET sur les écrans externes
;     (DDC/CI, à activer dans le menu de l'écran s'il est désactivé).
; =====================================================================
global g_mode := "", g_valeur := 0, g_niveau := -1
global g_barre := 0, g_barreProg := 0, g_barrePiste := 0, g_barreTxt := 0, g_barreIcone := 0, g_pisteW := 0
global g_barreW := 0, g_barreH := 0, g_barreX := -99999, g_barreY := -99999
global g_barreActive := RegRead("HKCU\Software\MonToolkit", "BarreLuminosite", 1)

^!Up::AjusterLuminosite(10)
^!Down::AjusterLuminosite(-10)
^!l::BasculerBarre()

#HotIf SourisSurBarreDesTaches()
WheelUp::AjusterLuminosite(5)
WheelDown::AjusterLuminosite(-5)
#HotIf

SourisSurBarreDesTaches() {
    MouseGetPos(, , &win)
    if (g_barre && win = g_barre.Hwnd)
        return true
    return WinExist("ahk_class Shell_TrayWnd ahk_id " win)
        || WinExist("ahk_class Shell_SecondaryTrayWnd ahk_id " win)
}

AjusterLuminosite(delta) {
    niveau := Luminosite("relatif", delta)
    if (niveau >= 0 && g_barreActive && g_barre) {
        MajBarre(niveau)
        return
    }
    ToolTip niveau >= 0 ? "☀ " niveau " %" : "Aucun écran compatible (active DDC/CI dans le menu de l'écran)"
    SetTimer () => ToolTip(), -1200
}

; mode : "lire" (renvoie le niveau actuel), "relatif" (+/- valeur), "absolu" (= valeur)
Luminosite(mode, valeur := 0) {
    global g_mode, g_valeur, g_niveau
    g_mode := mode, g_valeur := valeur, g_niveau := -1

    ; Écrans externes (DDC/CI)
    cb := CallbackCreate(_EcranExterne, "F", 4)
    DllCall("EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)

    ; Écran intégré d'un portable (WMI)
    try {
        wmi := ComObjGet("winmgmts:\\.\root\WMI")
        for m in wmi.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness WHERE Active=TRUE")
            actuel := m.CurrentBrightness
        niveau := (mode = "relatif") ? actuel + valeur : (mode = "absolu") ? valeur : actuel
        niveau := Max(0, Min(100, niveau))
        if mode != "lire"
            for m in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE")
                m.WmiSetBrightness(1, niveau)
        g_niveau := niveau
    }
    return g_niveau
}

_EcranExterne(hMon, hdc, pRect, lParam) {
    global g_mode, g_valeur, g_niveau
    nb := 0
    if !DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt*", &nb) || !nb
        return 1
    taille := A_PtrSize + 256          ; struct PHYSICAL_MONITOR
    buf := Buffer(taille * nb, 0)
    if DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt", nb, "Ptr", buf) {
        loop nb {
            h := NumGet(buf, (A_Index - 1) * taille, "Ptr")
            bas := 0, actuel := 0, haut := 0
            if DllCall("dxva2\GetMonitorBrightness", "Ptr", h, "UInt*", &bas, "UInt*", &actuel, "UInt*", &haut) && haut > bas {
                pct := Round((actuel - bas) * 100 / (haut - bas))
                cible := (g_mode = "relatif") ? pct + g_valeur : (g_mode = "absolu") ? g_valeur : pct
                cible := Max(0, Min(100, cible))
                if g_mode != "lire"
                    DllCall("dxva2\SetMonitorBrightness", "Ptr", h, "UInt", bas + Round((haut - bas) * cible / 100))
                g_niveau := cible
            }
        }
        DllCall("dxva2\DestroyPhysicalMonitors", "UInt", nb, "Ptr", buf)
    }
    return 1
}

; ---------- barre fixe sur la barre des tâches ----------
;  Position réglable dans config.ini :  [Barre]  position=auto | gauche | <pixels depuis la droite>
CreerBarre() {
    global g_barre, g_barreProg, g_barrePiste, g_barreTxt, g_barreIcone, g_barreW, g_barreH, g_pisteW
    DetectHiddenWindows true
    tb := WinExist("ahk_class Shell_TrayWnd")
    if !tb
        return false
    WinGetPos &tx, &ty, &tw, &th, tb
    f := A_ScreenDPI / 96
    g_barreW := Round(144 * f), g_barreH := th
    PositionBarre(&x, &y)

    ; Fond = couleur de la barre des tâches, rendu ensuite transparent
    CoordMode "Pixel", "Screen"
    fond := SubStr(PixelGetColor(x + g_barreW // 2, ty + th // 2), 3)
    piste := Melanger(fond, "FFFFFF", 0.30)

    g_barre := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")   ; E0x08000000 = ne prend pas le focus
    g_barre.BackColor := fond
    g_barre.MarginX := 0, g_barre.MarginY := 0

    g_barre.SetFont("s11 cFFFFFF", "Segoe MDL2 Assets")
    g_barre.SetFont(, "Segoe Fluent Icons")
    g_barreIcone := g_barre.AddText("x0 y0 w" Round(24 * f) " h" th " 0x200 Center", Chr(0xE706))

    ; Piste (fond clair) + remplissage (blanc) : deux simples rectangles, sans bordure
    hp := Max(4, Round(4 * f)), g_pisteW := Round(72 * f), px := Round(28 * f), py := (th - hp) // 2
    g_barrePiste := g_barre.AddText("x" px " y" py " w" g_pisteW " h" hp " Background" piste)
    g_barreProg := g_barre.AddText("x" px " y" py " w0 h" hp " BackgroundFFFFFF")

    g_barre.SetFont("s9 cFFFFFF", "Segoe UI")
    g_barreTxt := g_barre.AddText("x" Round(106 * f) " y0 w" Round(38 * f) " h" th " 0x200", "")

    g_barre.Show("NA Hide x" x " y" y " w" g_barreW " h" g_barreH)
    WinSetTransColor fond, g_barre
    OnMessage 0x201, ClicBarre          ; WM_LBUTTONDOWN
    return true
}

PositionBarre(&x, &y) {
    tb := WinExist("ahk_class Shell_TrayWnd")
    WinGetPos &tx, &ty, &tw, &th, tb
    f := A_ScreenDPI / 96
    pos := g_options.Has("Barre.position") ? g_options["Barre.position"] : "auto"
    y := ty
    if (pos = "gauche") {
        x := tx + Round(16 * f)
    } else if IsNumber(pos) {
        x := tx + tw - Round(pos * f) - g_barreW
    } else {
        x := tx + tw - Round(330 * f) - g_barreW          ; estimation si la zone de notification est introuvable
        try {
            ControlGetPos &cx, , &cw, , "TrayNotifyWnd1", tb
            if (cw > 0 && cx > 0)
                x := tx + cx - g_barreW - Round(8 * f)
        }
    }
}

MajBarre(niveau) {
    if !g_barre
        return
    g_barreProg.Move(, , Round(g_pisteW * niveau / 100))
    g_barreTxt.Value := niveau " %"
}

SurveillerBarre() {
    global g_barreX, g_barreY
    if !g_barreActive {
        if g_barre
            g_barre.Hide()
        return
    }
    if (!g_barre && !CreerBarre())
        return
    tb := WinExist("ahk_class Shell_TrayWnd")
    if (!tb || PleinEcran()) {
        g_barre.Hide()
        g_barreX := -99999
        return
    }
    PositionBarre(&x, &y)
    if (x != g_barreX || y != g_barreY || !DllCall("IsWindowVisible", "Ptr", g_barre.Hwnd)) {
        g_barre.Show("NA x" x " y" y)
        g_barreX := x, g_barreY := y
    }
    ; reste au-dessus de la barre des tâches (HWND_TOPMOST, sans bouger ni activer)
    DllCall("SetWindowPos", "Ptr", g_barre.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

RafraichirNiveau() {
    if (g_barreActive && g_barre && DllCall("IsWindowVisible", "Ptr", g_barre.Hwnd)) {
        niveau := Luminosite("lire")
        if niveau >= 0
            MajBarre(niveau)
    }
}

PleinEcran() {
    try {
        hwnd := WinGetID("A")
        classe := WinGetClass(hwnd)
        if (classe = "Progman" || classe = "WorkerW" || classe = "Shell_TrayWnd")
            return false
        WinGetPos &x, &y, &w, &h, hwnd
        return (x <= 0 && y <= 0 && w >= A_ScreenWidth && h >= A_ScreenHeight)
    }
    return false
}

ClicBarre(wParam, lParam, msg, hwnd) {
    if (!g_barre || hwnd != g_barre.Hwnd)
        return
    CoordMode "Mouse", "Screen"
    WinGetPos &gx, , , , g_barre
    g_barrePiste.GetPos(&px, , &pw)
    MouseGetPos &mx
    if (mx < gx + px - 10 || mx > gx + px + pw + 10)   ; clic hors de la piste
        return
    dernier := -1
    while GetKeyState("LButton", "P") {
        MouseGetPos &mx
        v := Max(0, Min(100, Round((mx - gx - px) * 100 / pw)))
        if (v != dernier) {
            MajBarre(v)
            Luminosite("absolu", v)
            dernier := v
        }
        Sleep 20
    }
    return 0
}

BasculerBarre(*) {
    global g_barreActive
    g_barreActive := !g_barreActive
    RegWrite g_barreActive, "REG_DWORD", "HKCU\Software\MonToolkit", "BarreLuminosite"
    if g_barreActive {
        A_TrayMenu.Check "Barre de luminosité"
        SurveillerBarre()
        RafraichirNiveau()
    } else {
        A_TrayMenu.Uncheck "Barre de luminosité"
        if g_barre
            g_barre.Hide()
    }
}

Melanger(c1, c2, t) {
    r := Round(Integer("0x" SubStr(c1, 1, 2)) * (1 - t) + Integer("0x" SubStr(c2, 1, 2)) * t)
    g := Round(Integer("0x" SubStr(c1, 3, 2)) * (1 - t) + Integer("0x" SubStr(c2, 3, 2)) * t)
    b := Round(Integer("0x" SubStr(c1, 5, 2)) * (1 - t) + Integer("0x" SubStr(c2, 5, 2)) * t)
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}

SetTimer SurveillerBarre, 500
SetTimer RafraichirNiveau, 5000
SurveillerBarre()
RafraichirNiveau()


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

A_TrayMenu.Insert "1&", "Barre de luminosité", BasculerBarre
A_TrayMenu.Insert "2&", "Aide (Ctrl+Alt+H)", (*) => Aide()
A_TrayMenu.Insert "3&", "Modifier mes raccourcis texte", (*) => Run('notepad "' CONFIG '"')
A_TrayMenu.Insert "4&", "Recharger", (*) => Reload()
A_TrayMenu.Insert "5&", "Lancer au démarrage de Windows", BasculerDemarrage
A_TrayMenu.Insert "6&"
A_TrayMenu.Default := "Barre de luminosité"     ; un simple clic sur l'icône affiche / masque la barre
A_TrayMenu.ClickCount := 1
if g_barreActive
    A_TrayMenu.Check "Barre de luminosité"
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
    texte .= "   Barre sur la barre des tâches : clic, glisser ou molette`n"
    texte .= "   Clic sur l'icône du toolkit ou Ctrl + Alt + L  →  afficher / masquer`n"
    texte .= "   Ctrl + Alt + ↑ / ↓               →  +10 % / -10 %`n"
    texte .= "   Molette sur la barre des tâches  →  +5 % / -5 %`n`n"
    texte .= "CONVERTISSEUR`n"
    texte .= "   Sélectionne des fichiers, puis Ctrl + Alt + C`n`n"
    texte .= "AIDE`n"
    texte .= "   Ctrl + Alt + H"
    MsgBox texte, "Mon Toolkit"
}
