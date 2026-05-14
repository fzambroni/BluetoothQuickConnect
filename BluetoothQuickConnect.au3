#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_UseUpx=n
#AutoIt3Wrapper_Res_CompanyName=Fabricio Zambroni
#AutoIt3Wrapper_Res_Fileversion=1.1.1.5
#AutoIt3Wrapper_Res_ProductVersion=1.0.0.0
#AutoIt3Wrapper_Res_LegalCopyright=Copyright © 2026 Fabricio Zambroni
#AutoIt3Wrapper_Icon=bt1.ico
#AutoIt3Wrapper_Res_Description=Bluetooth Quick Connect
#AutoIt3Wrapper_Res_ProductName=Bluetooth Quick Connect
#AutoIt3Wrapper_Res_File_Add=E:\GitHub\BluetoothQuickConnect\Updater.exe
#AutoIt3Wrapper_Run_After=E:\GitHub\BluetoothQuickConnect\FileUpdate.exe

#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <ListViewConstants.au3>
#include <GuiListView.au3>
#include <StaticConstants.au3>
#include <ButtonConstants.au3>
#include <EditConstants.au3>
#include <MsgBoxConstants.au3>
#include <WinAPI.au3>
#include <WinAPISys.au3>
#include <WinAPITheme.au3>
#include <TrayConstants.au3>
#include <SendMessage.au3>
#include <Misc.au3>
#include <InetConstants.au3>
#include "Updater_lib.au3"

; ======================================================================================================================
; Bluetooth Quick Connect  (v2)
; ----------------------------------------------------------------------------------------------------------------------
; Lightweight tray app to manage Bluetooth devices:
;   - A single click on the tray icon opens a borderless floating window, anchored near the tray
;   - Lists every paired / remembered device (Win32 BluetoothFindFirstDevice API)
;   - Visually highlights what is currently connected; double-click to connect / disconnect
;   - Quick action buttons: Connect, Disconnect, Remove, Pair New, Refresh
;   - Keyboard shortcuts: Esc = hide, F5 = refresh, Enter = connect, Del = remove
;   - The popup auto-hides when it loses focus (click outside). The tray icon stays.
;
; Technical note (same caveat as v1):
;   Windows does not expose a clean public "generic connect" API. We use BluetoothSetServiceState on the common
;   audio profiles (Handsfree / AudioSink / Headset). This works great for headsets, earbuds and speakers.
;   Pure BLE devices may not show up here nor be controllable through this path.
; ======================================================================================================================

Opt("TrayMenuMode", 3)          ; do not add default items
Opt("TrayOnEventMode", 1)       ; event-based tray
Opt("GUIOnEventMode", 0)        ; GUI in message mode (GUIGetMsg)
TraySetClick($TRAY_CLICK_SECONDARYDOWN)



; ----------------------------------------------------------------------------------------------------------------------
; Updater - GitHub based
; ----------------------------------------------------------------------------------------------------------------------
; This updater no longer uses a shared network folder. It reads the latest version from GitHub version.txt,
; downloads the published Toolbox.exe only when a newer version is available, then lets Updater.exe replace the file.
Global Const $g_sGitHubDefaultRawBase = "https://raw.githubusercontent.com/fzambroni/BluetoothQuickConnect/main"
Global $g_sGitHubRawBase = IniRead(@ScriptDir & "\settings.ini", "Update", "github_raw_base", $g_sGitHubDefaultRawBase)
If StringStripWS($g_sGitHubRawBase, 3) = "" Then $g_sGitHubRawBase = $g_sGitHubDefaultRawBase

; Keep settings.ini explicit and self-documenting. The old [Update] path entry is intentionally ignored.
IniWrite(@ScriptDir & "\settings.ini", "Update", "source", "github")
IniWrite(@ScriptDir & "\settings.ini", "Update", "github_raw_base", $g_sGitHubRawBase)

; Skip automatic update checks when running the .au3 directly from SciTE/dev mode.
If Not StringInStr(StringLower(@ScriptName), ".au3") Then
    _CheckGitHubUpdate()
EndIf


; ----------------------------------------------------------------------------------------------------------------------
; General constants
; ----------------------------------------------------------------------------------------------------------------------
Global Const $APP_TITLE = "Bluetooth Quick Connect"
Global Const $APP_VERSION = "2.0"
Global Const $WIN_W = 460
Global Const $WIN_H = 420

Global $UpdatePath = "\\lp16-fzi1-dsa\BluetoothQuickConnect"
Global $UpdatePath = IniRead(@ScriptDir & "\settings.ini","Update","path","") ;Update Path
If $UpdatePath = "" Then
	IniWrite(@ScriptDir & "\settings.ini","Update","path","\\lp16-fzi1-dsa\BluetoothQuickConnect")
	$UpdatePath = "\\lp16-fzi1-dsa\BluetoothQuickConnect"
EndIf

; Autostart registry location (per-user, no admin required)
Global Const $AUTOSTART_KEY = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
Global Const $AUTOSTART_NAME = "BluetoothQuickConnect"

Global Const $BT_SERVICE_DISABLE = 0
Global Const $BT_SERVICE_ENABLE = 1
Global Const $E_INVALIDARG_UNSIGNED = 2147942487 ; 0x80070057
Global Const $ERROR_SERVICE_DOES_NOT_EXIST = 1060

; Bluetooth audio profile GUIDs
Global Const $GUID_HANDSFREE = "{0000111e-0000-1000-8000-00805f9b34fb}"
Global Const $GUID_AUDIOSINK = "{0000110b-0000-1000-8000-00805f9b34fb}"
Global Const $GUID_HEADSET = "{00001108-0000-1000-8000-00805f9b34fb}"

; Bluetooth structures
Global Const $TAG_BLUETOOTH_FIND_RADIO_PARAMS = "dword dwSize"
Global Const $TAG_BLUETOOTH_DEVICE_SEARCH_PARAMS_32 = _
		"dword dwSize;bool fReturnAuthenticated;bool fReturnRemembered;bool fReturnUnknown;" & _
		"bool fReturnConnected;bool fIssueInquiry;ubyte cTimeoutMultiplier;byte _pad[3];handle hRadio"
Global Const $TAG_BLUETOOTH_DEVICE_SEARCH_PARAMS_64 = _
		"dword dwSize;bool fReturnAuthenticated;bool fReturnRemembered;bool fReturnUnknown;" & _
		"bool fReturnConnected;bool fIssueInquiry;ubyte cTimeoutMultiplier;byte _pad[7];handle hRadio"
Global Const $TAG_BLUETOOTH_DEVICE_INFO = _
		"dword dwSize;byte _align[4];uint64 Address;dword ulClassofDevice;bool fConnected;" & _
		"bool fRemembered;bool fAuthenticated;ushort stLastSeen[8];ushort stLastUsed[8];wchar szName[248]"
Global Const $TAG_GUID = "byte Data[16]"
Global Const $TAG_UINT64 = "uint64 Value"

; NM_CUSTOMDRAW values come from the includes (GuiListView.au3 / StructureConstants.au3):
;   $CDDS_PREPAINT, $CDDS_ITEMPREPAINT, $CDRF_NEWFONT, $CDRF_NOTIFYITEMDRAW, $NM_CUSTOMDRAW

; Palette (RGB - AutoIt uses 0xRRGGBB for GUICtrlSet*)
Global Const $CLR_BG = 0x1E1E2A
Global Const $CLR_BG_HEADER = 0x151520
Global Const $CLR_BG_CARD = 0x252535
Global Const $CLR_BG_LIST = 0x1A1A26
Global Const $CLR_BG_LIST_ALT = 0x20202E
Global Const $CLR_BG_LIST_CONN = 0x1D3A52    ; subtle blue tint for connected rows
Global Const $CLR_BG_SELECTED = 0x3A3A55
Global Const $CLR_TEXT = 0xE8E8F0
Global Const $CLR_TEXT_DIM = 0xA0A0B0
Global Const $CLR_TEXT_MUTED = 0x70707F
Global Const $CLR_ACCENT = 0x2E8BFF
Global Const $CLR_ACCENT_DARK = 0x1F5FB2
Global Const $CLR_SUCCESS = 0x4CD964
Global Const $CLR_DANGER = 0xE55353
Global Const $CLR_WARN = 0xF5B041
Global Const $CLR_BORDER = 0x353545


; ----------------------------------------------------------------------------------------------------------------------
; Instance
; ----------------------------------------------------------------------------------------------------------------------
Sleep(500)
Local $aList = ProcessList(@ScriptName)
Local $n = 0
For $i = 1 To $aList[0][0]
	If $aList[$i][0] = @ScriptName Then
		$n += 1
		If $n > 1 Then
			ConsoleWrite("Closing process..." & @CRLF)
			ProcessClose(@ScriptName)
			Sleep(500)
			Run(@ScriptFullPath)
			Sleep(100)
			Exit
		EndIf
	EndIf
Next

; ----------------------------------------------------------------------------------------------------------------------
; Updater
; ----------------------------------------------------------------------------------------------------------------------
$UpdatedVersion = FileGetVersion($UpdatePath & "\" & @ScriptName)
$currentVersion = FileGetVersion(@ScriptFullPath)

If $UpdatedVersion > $currentVersion Then
	FileCopy($UpdatePath & "\" & @ScriptName, @ScriptDir & "\" & StringReplace(@ScriptName, ".exe", ".tmp"), 9)
EndIf
ConsoleWrite(@ScriptDir & "\" & StringReplace(@ScriptName, ".exe", ".tmp") & @CRLF)
If FileExists(@ScriptDir & "\" & StringReplace(@ScriptName, ".exe", ".tmp")) and not StringInStr(@ScriptName,".au3") Then
	ConsoleWrite("Updating..." & @CRLF)
	$Updater_File = @TempDir & "\Updater.exe"
	FileInstall("Updater.exe", $Updater_File, 1)
	Sleep(500)
	Run(@TempDir & "\Updater.exe '" & @ScriptDir & "'")
	Sleep(100)
	Exit
EndIf


; ----------------------------------------------------------------------------------------------------------------------
; Global state
; ----------------------------------------------------------------------------------------------------------------------
Global $g_hBth = DllOpen("bthprops.cpl")
If $g_hBth = -1 Then
	MsgBox($MB_ICONERROR, $APP_TITLE, "Could not load bthprops.cpl." & @CRLF & _
			"Is a Bluetooth adapter installed on this machine?")
	Exit
EndIf

Global $g_hRadio = _GetFirstRadioHandle()
Global $g_aDevices[0][6]          ; [Name, Address(uint64), AddressHex, Connected, Remembered, Authenticated]
Global $g_bAllowAutoHide = True   ; prevents auto-hide while a child MsgBox/dialog is open
Global $g_tLastHide = 0           ; timestamp of the last hide, used to debounce tray toggle

; ----------------------------------------------------------------------------------------------------------------------
; Tray
; ----------------------------------------------------------------------------------------------------------------------
; Resolve the icon path once. Priority:
;   1) bt.ico next to the script/exe (both compiled and dev use the file directly)
;   2) embedded resource of the compiled exe (from #AutoIt3Wrapper_Icon)
;   3) Windows' native Bluetooth icon as a last resort
Global $g_sIconPath = @ScriptDir & "\bt1.ico"
If Not FileExists($g_sIconPath) Then
	If @Compiled Then
		$g_sIconPath = @ScriptFullPath
	Else
		$g_sIconPath = "bthprops.cpl"
	EndIf
EndIf

TraySetIcon($g_sIconPath, 0)
TraySetToolTip($APP_TITLE & " — click to open" & @CRLF & @CRLF & "Version: " & FileGetVersion(@ScriptFullPath) & @CRLF & @CRLF & "Developed by Fabricio Zambroni")
TraySetOnEvent($TRAY_EVENT_PRIMARYUP, "_ShowPopupFromTray")
TraySetState($TRAY_ICONSTATE_SHOW)

Global $g_idTrayShow = TrayCreateItem("Open")
TrayItemSetOnEvent($g_idTrayShow, "_ShowPopupFromTray")
Global $g_idTrayRefresh = TrayCreateItem("Refresh devices")
TrayItemSetOnEvent($g_idTrayRefresh, "_RefreshDevices")
TrayCreateItem("")
Global $g_idTrayPair = TrayCreateItem("Pair new device...")
TrayItemSetOnEvent($g_idTrayPair, "_PairNewDevice")
TrayCreateItem("")
Global $g_idTrayAutostart = TrayCreateItem("Start with Windows")
TrayItemSetOnEvent($g_idTrayAutostart, "_ToggleAutostart")
_SyncAutostartMenu()
Global $g_idTrayAbout = TrayCreateItem("About")
TrayItemSetOnEvent($g_idTrayAbout, "_ShowAbout")
Global $g_idTrayExit = TrayCreateItem("Exit")
TrayItemSetOnEvent($g_idTrayExit, "_QuitApp")

; ----------------------------------------------------------------------------------------------------------------------
; GUI construction
; ----------------------------------------------------------------------------------------------------------------------
Global $g_hGui = GUICreate($APP_TITLE, $WIN_W, $WIN_H, -1, -1, _
		BitOR($WS_POPUP, $WS_BORDER), _
		BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
GUISetBkColor($CLR_BG, $g_hGui)
GUISetFont(9, 400, 0, "Segoe UI", $g_hGui)

; --- Header ---
Global $g_idHeader = GUICtrlCreateLabel("", 0, 0, $WIN_W, 48)
GUICtrlSetBkColor($g_idHeader, $CLR_BG_HEADER)

Global $g_idIcon = GUICtrlCreateIcon($g_sIconPath, 0, 14, 12, 24, 24)

Global $g_idHeaderTitle = GUICtrlCreateLabel($APP_TITLE, 48, 10, 300, 20)
GUICtrlSetFont($g_idHeaderTitle, 11, 600, 0, "Segoe UI")
GUICtrlSetColor($g_idHeaderTitle, $CLR_TEXT)
GUICtrlSetBkColor($g_idHeaderTitle, $CLR_BG_HEADER)

Global $g_idHeaderSub = GUICtrlCreateLabel("Quick connect for your paired devices", 48, 28, 300, 16)
GUICtrlSetFont($g_idHeaderSub, 8, 400, 0, "Segoe UI")
GUICtrlSetColor($g_idHeaderSub, $CLR_TEXT_DIM)
GUICtrlSetBkColor($g_idHeaderSub, $CLR_BG_HEADER)

; Close "button" — implemented as a Label with SS_NOTIFY for reliable clicks
; in a $WS_POPUP window. Clicks are double-caught: via GUIGetMsg on this label
; AND via a WM_LBUTTONDOWN hook on the parent that does a hit-test in the same
; rect (see _WM_LBUTTONDOWN below). This guarantees the X works even if the
; label swallows focus in unusual z-order situations.
Global Const $CLOSE_X = $WIN_W - 38
Global Const $CLOSE_Y = 10
Global Const $CLOSE_W = 24
Global Const $CLOSE_H = 24
Global $g_idBtnClose = GUICtrlCreateLabel("✕", $CLOSE_X, $CLOSE_Y, $CLOSE_W, $CLOSE_H, _
		BitOR($SS_CENTER, $SS_CENTERIMAGE, $SS_NOTIFY))
GUICtrlSetFont($g_idBtnClose, 12, 700, 0, "Segoe UI")
GUICtrlSetColor($g_idBtnClose, $CLR_TEXT_DIM)
GUICtrlSetBkColor($g_idBtnClose, $CLR_BG_HEADER)
GUICtrlSetCursor($g_idBtnClose, 0) ; arrow with system default (0) — just to force hit-test
GUICtrlSetTip($g_idBtnClose, "Close (Esc)")

; --- Section header ---
Global $g_idSection = GUICtrlCreateLabel("Paired devices", 14, 56, 300, 18)
GUICtrlSetFont($g_idSection, 9, 600, 0, "Segoe UI")
GUICtrlSetColor($g_idSection, $CLR_TEXT)
GUICtrlSetBkColor($g_idSection, $CLR_BG)

Global $g_idCount = GUICtrlCreateLabel("", $WIN_W - 100, 56, 86, 18, $SS_RIGHT)
GUICtrlSetFont($g_idCount, 8, 400, 0, "Segoe UI")
GUICtrlSetColor($g_idCount, $CLR_TEXT_MUTED)
GUICtrlSetBkColor($g_idCount, $CLR_BG)

; --- ListView ---
Global $g_idList = GUICtrlCreateListView("Device|Status|Address", 14, 80, $WIN_W - 28, 210, _
		BitOR($LVS_REPORT, $LVS_SINGLESEL, $LVS_SHOWSELALWAYS, $LVS_NOCOLUMNHEADER))
Global $g_hList = GUICtrlGetHandle($g_idList)
_GUICtrlListView_SetExtendedListViewStyle($g_hList, _
		BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_DOUBLEBUFFER))
_GUICtrlListView_SetColumnWidth($g_hList, 0, 240)
_GUICtrlListView_SetColumnWidth($g_hList, 1, 80)
_GUICtrlListView_SetColumnWidth($g_hList, 2, 105)
_GUICtrlListView_SetBkColor($g_hList, $CLR_BG_LIST)
_GUICtrlListView_SetTextBkColor($g_hList, $CLR_BG_LIST)
_GUICtrlListView_SetTextColor($g_hList, $CLR_TEXT)
_GUICtrlListView_SetView($g_hList, 1) ; report view
; Strip the visual theme so our custom-draw colors are honored
_WinAPI_SetWindowTheme($g_hList, "", "")

; --- Action buttons (custom flat label-buttons) ---
Global $g_idConnect = _CreateFlatButton("Connect", 14, 302, 96, 32, $CLR_ACCENT, 0xFFFFFF, True)
Global $g_idDisconnect = _CreateFlatButton("Disconnect", 118, 302, 104, 32, $CLR_BG_CARD, $CLR_TEXT)
Global $g_idRemove = _CreateFlatButton("Remove", 230, 302, 90, 32, $CLR_BG_CARD, $CLR_DANGER)
Global $g_idPairNew = _CreateFlatButton("＋ Pair", 328, 302, 120, 32, $CLR_BG_CARD, $CLR_TEXT)

Global $g_idRefresh = _CreateFlatButton("↻ Refresh", 14, 342, 120, 28, $CLR_BG, $CLR_TEXT_DIM)
Global $g_idExit = _CreateFlatButton("Exit", $WIN_W - 90, 342, 76, 28, $CLR_BG, $CLR_TEXT_DIM)
$Label_DevBy = GUICtrlCreateLabel("Developed by Fabricio Zambroni", 30, $WIN_H - 45, $WIN_W - 44, 16)
GUICtrlSetFont($Label_DevBy, 9, 400, 0, "Segoe UI")
GUICtrlSetColor($Label_DevBy, $CLR_TEXT_DIM)
GUICtrlSetBkColor($Label_DevBy, $CLR_BG)

; --- Status bar ---
Global $g_idStatusDot = GUICtrlCreateLabel("●", 14, $WIN_H - 22, 14, 14)
GUICtrlSetFont($g_idStatusDot, 9, 400, 0, "Segoe UI")
GUICtrlSetColor($g_idStatusDot, $CLR_SUCCESS)
GUICtrlSetBkColor($g_idStatusDot, $CLR_BG)

Global $g_idStatus = GUICtrlCreateLabel("Ready.", 30, $WIN_H - 22, $WIN_W - 44, 16)
GUICtrlSetFont($g_idStatus, 8, 400, 0, "Segoe UI")
GUICtrlSetColor($g_idStatus, $CLR_TEXT_DIM)
GUICtrlSetBkColor($g_idStatus, $CLR_BG)

; --- Keyboard accelerators ---
Global $g_aAccel[4][2] = [ _
		["{ESC}", $g_idBtnClose], _
		["{F5}", $g_idRefresh], _
		["{DELETE}", $g_idRemove], _
		["{ENTER}", $g_idConnect] _
		]
GUISetAccelerators($g_aAccel, $g_hGui)

; --- Message handlers ---
GUIRegisterMsg($WM_NOTIFY, "_WM_NOTIFY")
GUIRegisterMsg($WM_ACTIVATE, "_WM_ACTIVATE")
GUIRegisterMsg($WM_LBUTTONDOWN, "_WM_LBUTTONDOWN")
GUIRegisterMsg($WM_PARENTNOTIFY, "_WM_PARENTNOTIFY")

GUISetState(@SW_HIDE, $g_hGui)

; Initial load
_RefreshDevices()

; ======================================================================================================================
; Main loop
; ======================================================================================================================
While 1
	Local $msg = GUIGetMsg()
	Switch $msg
		Case $GUI_EVENT_CLOSE, $g_idBtnClose
			_HidePopup()

		Case $g_idConnect
			_ConnectSelected()

		Case $g_idDisconnect
			_DisconnectSelected()

		Case $g_idRemove
			_RemoveSelected()

		Case $g_idPairNew
			_PairNewDevice()

		Case $g_idRefresh
			_RefreshDevices()

		Case $g_idExit
			_QuitApp()
	EndSwitch
	Sleep(20)
WEnd

; ======================================================================================================================
; UI helpers
; ======================================================================================================================
Func _CreateFlatButton($sText, $x, $y, $w, $h, $iBgColor, $iFgColor, $bBold = False)
	Local $iStyle = BitOR($SS_CENTER, $SS_CENTERIMAGE, $SS_NOTIFY)
	Local $id = GUICtrlCreateLabel($sText, $x, $y, $w, $h, $iStyle)
	GUICtrlSetBkColor($id, $iBgColor)
	GUICtrlSetColor($id, $iFgColor)
	Local $iWeight = 400
	If $bBold Then $iWeight = 600
	GUICtrlSetFont($id, 9, $iWeight, 0, "Segoe UI")
	Return $id
EndFunc   ;==>_CreateFlatButton

Func _ShowPopupFromTray()
	; If we just hid via WA_INACTIVE (i.e. user clicked tray while popup was open),
	; don't reopen it. This gives a real toggle behavior without flicker.
	If $g_tLastHide <> 0 And TimerDiff($g_tLastHide) < 250 Then
		$g_tLastHide = 0
		Return
	EndIf

	If Not BitAND(WinGetState($g_hGui), 2) Then
		_PlacePopupNearTray()
		GUISetState(@SW_SHOW, $g_hGui)
	EndIf
	WinActivate($g_hGui)
	ControlFocus($g_hGui, "", $g_hList)
	_RefreshDevices()
EndFunc   ;==>_ShowPopupFromTray

Func _PlacePopupNearTray()
	Local $aTray = WinGetPos("[CLASS:Shell_TrayWnd]")
	Local $iX = @DesktopWidth - $WIN_W - 12
	Local $iY = @DesktopHeight - $WIN_H - 52

	If IsArray($aTray) Then
		; Bottom taskbar (most common)
		If $aTray[1] > (@DesktopHeight / 2) Then
			$iX = @DesktopWidth - $WIN_W - 12
			$iY = $aTray[1] - $WIN_H - 10
		ElseIf $aTray[0] > (@DesktopWidth / 2) Then     ; right
			$iX = $aTray[0] - $WIN_W - 10
			$iY = @DesktopHeight - $WIN_H - 12
		ElseIf $aTray[2] < (@DesktopWidth / 2) Then     ; left
			$iX = $aTray[2] + 10
			$iY = @DesktopHeight - $WIN_H - 12
		Else                                            ; top
			$iX = @DesktopWidth - $WIN_W - 12
			$iY = $aTray[3] + 10
		EndIf
	EndIf

	If $iX < 0 Then $iX = 10
	If $iY < 0 Then $iY = 10
	If $iX + $WIN_W > @DesktopWidth Then $iX = @DesktopWidth - $WIN_W - 8
	If $iY + $WIN_H > @DesktopHeight Then $iY = @DesktopHeight - $WIN_H - 8

	WinMove($g_hGui, "", $iX, $iY)
EndFunc   ;==>_PlacePopupNearTray

Func _HidePopup()
	GUISetState(@SW_HIDE, $g_hGui)
	$g_tLastHide = TimerInit()
EndFunc   ;==>_HidePopup

; 0 = info, 1 = success, 2 = error, 3 = progress
Func _ShowStatus($sText, $iKind = 0)
	GUICtrlSetData($g_idStatus, $sText)
	Switch $iKind
		Case 1
			GUICtrlSetColor($g_idStatus, $CLR_SUCCESS)
			GUICtrlSetColor($g_idStatusDot, $CLR_SUCCESS)
		Case 2
			GUICtrlSetColor($g_idStatus, $CLR_DANGER)
			GUICtrlSetColor($g_idStatusDot, $CLR_DANGER)
		Case 3
			GUICtrlSetColor($g_idStatus, $CLR_ACCENT)
			GUICtrlSetColor($g_idStatusDot, $CLR_ACCENT)
		Case Else
			GUICtrlSetColor($g_idStatus, $CLR_TEXT_DIM)
			GUICtrlSetColor($g_idStatusDot, $CLR_TEXT_MUTED)
	EndSwitch
EndFunc   ;==>_ShowStatus

Func _ShowAbout()
	$g_bAllowAutoHide = False
	MsgBox(BitOR($MB_ICONINFORMATION, $MB_OK), $APP_TITLE, _
			$APP_TITLE & "  v" & $APP_VERSION & @CRLF & @CRLF & _
			"Lightweight utility to connect or disconnect paired" & @CRLF & _
			"Bluetooth devices straight from the Windows tray." & @CRLF & @CRLF & _
			"Shortcuts:" & @CRLF & _
			"  • Double-click  →  toggle connection" & @CRLF & _
			"  • Enter         →  connect" & @CRLF & _
			"  • Del           →  remove" & @CRLF & _
			"  • F5            →  refresh" & @CRLF & _
			"  • Esc           →  hide window")
	$g_bAllowAutoHide = True
EndFunc   ;==>_ShowAbout

; ======================================================================================================================
; Message handlers (custom draw + auto-hide)
; ======================================================================================================================
Func _WM_NOTIFY($hWnd, $iMsg, $wParam, $lParam)
	Local $tNMHDR = DllStructCreate("hwnd hwndFrom;uint_ptr idFrom;int code", $lParam)
	Local $hFrom = DllStructGetData($tNMHDR, "hwndFrom")
	Local $iCode = DllStructGetData($tNMHDR, "code")

	; ListView custom draw: paint connected rows with a blue accent background
	If $hFrom = $g_hList And $iCode = $NM_CUSTOMDRAW Then
		Local $tCD = DllStructCreate( _
				"hwnd hdr_hwndFrom;uint_ptr hdr_idFrom;int hdr_code;" & _
				"dword dwDrawStage;handle hdc;long rcLeft;long rcTop;long rcRight;long rcBottom;" & _
				"dword_ptr dwItemSpec;uint uItemState;lparam lItemlParam;" & _
				"dword clrText;dword clrTextBk;int iSubItem", $lParam)

		Local $iStage = DllStructGetData($tCD, "dwDrawStage")
		Switch $iStage
			Case $CDDS_PREPAINT
				Return $CDRF_NOTIFYITEMDRAW
			Case $CDDS_ITEMPREPAINT
				Local $iItem = DllStructGetData($tCD, "dwItemSpec")
				If $iItem >= 0 And $iItem < UBound($g_aDevices) Then
					If $g_aDevices[$iItem][3] Then ; Connected
						DllStructSetData($tCD, "clrText", _RgbToBgr($CLR_SUCCESS))
						DllStructSetData($tCD, "clrTextBk", _RgbToBgr($CLR_BG_LIST_CONN))
					ElseIf Mod($iItem, 2) = 1 Then
						DllStructSetData($tCD, "clrText", _RgbToBgr($CLR_TEXT))
						DllStructSetData($tCD, "clrTextBk", _RgbToBgr($CLR_BG_LIST_ALT))
					Else
						DllStructSetData($tCD, "clrText", _RgbToBgr($CLR_TEXT))
						DllStructSetData($tCD, "clrTextBk", _RgbToBgr($CLR_BG_LIST))
					EndIf
				EndIf
				Return $CDRF_NEWFONT
		EndSwitch
	EndIf

	; Double-click on the list -> toggle connection
	If $hFrom = $g_hList And $iCode = -3 Then ; NM_DBLCLK
		_ToggleSelected()
		Return 0
	EndIf

	Return $GUI_RUNDEFMSG
EndFunc   ;==>_WM_NOTIFY

Func _WM_ACTIVATE($hWnd, $iMsg, $wParam, $lParam)
	If $hWnd = $g_hGui Then
		Local $iActivate = BitAND($wParam, 0xFFFF)
		If $iActivate = 0 And $g_bAllowAutoHide Then ; WA_INACTIVE
			_HidePopup()
		EndIf
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc   ;==>_WM_ACTIVATE

; Window-level click hook. Fires for clicks anywhere in the window's client
; area that don't hit a child control. (Clicks on child controls are absorbed
; by those controls; for that case we rely on WM_PARENTNOTIFY below.)
Func _WM_LBUTTONDOWN($hWnd, $iMsg, $wParam, $lParam)
	If $hWnd = $g_hGui Then
		Local $iX = BitAND($lParam, 0xFFFF)
		Local $iY = BitShift(BitAND($lParam, 0xFFFF0000), 16)
		If $iX > 32767 Then $iX -= 65536
		If $iY > 32767 Then $iY -= 65536
		If $iX >= $CLOSE_X And $iX < ($CLOSE_X + $CLOSE_W) _
				And $iY >= $CLOSE_Y And $iY < ($CLOSE_Y + $CLOSE_H) Then
			_HidePopup()
			Return 0
		EndIf
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc   ;==>_WM_LBUTTONDOWN

; WM_PARENTNOTIFY is sent to the parent whenever a child control receives
; a left-button-down message. This gives us a reliable way to detect a
; click on the X label even if its own STN_CLICKED event gets swallowed.
; wParam low word holds the event (WM_LBUTTONDOWN = 0x0201), and lParam
; holds the click x/y (in parent client coordinates).
Func _WM_PARENTNOTIFY($hWnd, $iMsg, $wParam, $lParam)
	If $hWnd = $g_hGui Then
		Local $iEvent = BitAND($wParam, 0xFFFF)
		If $iEvent = $WM_LBUTTONDOWN Then
			Local $iX = BitAND($lParam, 0xFFFF)
			Local $iY = BitShift(BitAND($lParam, 0xFFFF0000), 16)
			If $iX > 32767 Then $iX -= 65536
			If $iY > 32767 Then $iY -= 65536
			If $iX >= $CLOSE_X And $iX < ($CLOSE_X + $CLOSE_W) _
					And $iY >= $CLOSE_Y And $iY < ($CLOSE_Y + $CLOSE_H) Then
				_HidePopup()
				Return 0
			EndIf
		EndIf
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc   ;==>_WM_PARENTNOTIFY

; ======================================================================================================================
; Bluetooth enumeration
; ======================================================================================================================
Func _RefreshDevices()
	_ShowStatus("Loading devices...", 3)
	_GUICtrlListView_DeleteAllItems($g_hList)
	ReDim $g_aDevices[0][6]

	If $g_hRadio = 0 Then $g_hRadio = _GetFirstRadioHandle()

	If $g_hRadio = 0 Then
		GUICtrlSetData($g_idCount, "")
		_ShowStatus("No local Bluetooth radio was found.", 2)
		Return
	EndIf

	Local $sSearchTag = $TAG_BLUETOOTH_DEVICE_SEARCH_PARAMS_32
	If @AutoItX64 Then $sSearchTag = $TAG_BLUETOOTH_DEVICE_SEARCH_PARAMS_64
	Local $tSearch = DllStructCreate($sSearchTag)
	DllStructSetData($tSearch, "dwSize", DllStructGetSize($tSearch))
	DllStructSetData($tSearch, "fReturnAuthenticated", True)
	DllStructSetData($tSearch, "fReturnRemembered", True)
	DllStructSetData($tSearch, "fReturnUnknown", False)
	DllStructSetData($tSearch, "fReturnConnected", True)
	DllStructSetData($tSearch, "fIssueInquiry", False)
	DllStructSetData($tSearch, "cTimeoutMultiplier", 2)
	DllStructSetData($tSearch, "hRadio", $g_hRadio)

	Local $tInfo = DllStructCreate($TAG_BLUETOOTH_DEVICE_INFO)
	DllStructSetData($tInfo, "dwSize", DllStructGetSize($tInfo))

	Local $aFirst = DllCall($g_hBth, "handle", "BluetoothFindFirstDevice", "struct*", $tSearch, "struct*", $tInfo)
	If @error Or Not IsArray($aFirst) Or $aFirst[0] = 0 Then
		GUICtrlSetData($g_idCount, "0 devices")
		_ShowStatus("No paired devices found.", 0)
		Return
	EndIf

	Local $hFind = $aFirst[0]
	While 1
		_AddDeviceFromStruct($tInfo)
		DllStructSetData($tInfo, "dwSize", DllStructGetSize($tInfo))
		Local $aNext = DllCall($g_hBth, "bool", "BluetoothFindNextDevice", "handle", $hFind, "struct*", $tInfo)
		If @error Or Not IsArray($aNext) Or $aNext[0] = 0 Then ExitLoop
	WEnd
	DllCall($g_hBth, "bool", "BluetoothFindDeviceClose", "handle", $hFind)

	Local $iCount = UBound($g_aDevices)
	Local $iConnected = 0
	For $i = 0 To $iCount - 1
		If $g_aDevices[$i][3] Then $iConnected += 1
	Next

	If $iCount = 0 Then
		GUICtrlSetData($g_idCount, "0 devices")
		_ShowStatus("No paired devices found.", 0)
	Else
		GUICtrlSetData($g_idCount, $iCount & " device" & (($iCount > 1) ? "s" : ""))
		If $iConnected > 0 Then
			_ShowStatus($iConnected & " connected out of " & $iCount & ".", 1)
		Else
			_ShowStatus("Ready. " & $iCount & " device" & (($iCount > 1) ? "s" : "") & " available.", 0)
		EndIf
		_GUICtrlListView_SetItemSelected($g_hList, 0, True, True)
		_GUICtrlListView_SetSelectionMark($g_hList, 0)
	EndIf
EndFunc   ;==>_RefreshDevices

Func _AddDeviceFromStruct(ByRef $tInfo)
	Local $sName = StringStripWS(DllStructGetData($tInfo, "szName"), 3)
	If $sName = "" Then $sName = "(Unnamed device)"

	Local $uAddress = DllStructGetData($tInfo, "Address")
	Local $sAddressHex = _FormatBtAddress($uAddress)
	If _FindDeviceIndexByAddress($sAddressHex) <> -1 Then Return

	Local $bConnected = (DllStructGetData($tInfo, "fConnected") <> 0)
	Local $bRemembered = (DllStructGetData($tInfo, "fRemembered") <> 0)
	Local $bAuthenticated = (DllStructGetData($tInfo, "fAuthenticated") <> 0)

	Local $iSize = UBound($g_aDevices)
	ReDim $g_aDevices[$iSize + 1][6]
	$g_aDevices[$iSize][0] = $sName
	$g_aDevices[$iSize][1] = $uAddress
	$g_aDevices[$iSize][2] = $sAddressHex
	$g_aDevices[$iSize][3] = $bConnected
	$g_aDevices[$iSize][4] = $bRemembered
	$g_aDevices[$iSize][5] = $bAuthenticated

	; Unicode dot as a status glyph + short text label
	Local $sDot = $bConnected ? "● " : "○ "
	Local $sStatus = $bConnected ? "Connected" : ($bAuthenticated ? "Paired" : "Remembered")

	GUICtrlCreateListViewItem( _
			$sDot & $sName & "|" & _
			$sStatus & "|" & _
			$sAddressHex, _
			$g_idList)
EndFunc   ;==>_AddDeviceFromStruct

Func _GetFirstRadioHandle()
	Local $tParams = DllStructCreate($TAG_BLUETOOTH_FIND_RADIO_PARAMS)
	DllStructSetData($tParams, "dwSize", DllStructGetSize($tParams))

	Local $tRadio = DllStructCreate("handle hRadio")
	Local $aRet = DllCall($g_hBth, "handle", "BluetoothFindFirstRadio", "struct*", $tParams, "struct*", $tRadio)
	If @error Or Not IsArray($aRet) Or $aRet[0] = 0 Then Return 0

	Local $hFind = $aRet[0]
	Local $hRadio = DllStructGetData($tRadio, "hRadio")
	DllCall($g_hBth, "bool", "BluetoothFindRadioClose", "handle", $hFind)
	Return $hRadio
EndFunc   ;==>_GetFirstRadioHandle

; ======================================================================================================================
; Actions
; ======================================================================================================================
Func _ToggleSelected()
	Local $iIndex = _GetSelectedIndex()
	If $iIndex < 0 Then Return
	If $g_aDevices[$iIndex][3] Then
		_DisconnectSelected()
	Else
		_ConnectSelected()
	EndIf
EndFunc   ;==>_ToggleSelected

Func _ConnectSelected()
	Local $iIndex = _GetSelectedIndex()
	If $iIndex < 0 Then
		_ShowStatus("Select a device first.", 2)
		Return
	EndIf

	Local $tInfo = _GetDeviceInfoByIndex($iIndex)
	If @error Then
		_ShowStatus("Could not resolve the selected device.", 2)
		Return
	EndIf

	Local $sName = $g_aDevices[$iIndex][0]
	_ShowStatus("Connecting " & $sName & "...", 3)

	If _ApplyAudioProfiles($tInfo, True) Then
		Sleep(600)
		_RefreshDevices()
		_ShowStatus($sName & " — connected.", 1)
	Else
		_ShowStatus("No compatible audio profile on " & $sName & ".", 2)
	EndIf
EndFunc   ;==>_ConnectSelected

Func _DisconnectSelected()
	Local $iIndex = _GetSelectedIndex()
	If $iIndex < 0 Then
		_ShowStatus("Select a device first.", 2)
		Return
	EndIf

	Local $tInfo = _GetDeviceInfoByIndex($iIndex)
	If @error Then
		_ShowStatus("Could not resolve the selected device.", 2)
		Return
	EndIf

	Local $sName = $g_aDevices[$iIndex][0]
	_ShowStatus("Disconnecting " & $sName & "...", 3)

	If _ApplyAudioProfiles($tInfo, False) Then
		Sleep(500)
		_RefreshDevices()
		_ShowStatus($sName & " — disconnected.", 1)
	Else
		_ShowStatus("No profile to disconnect on " & $sName & ".", 2)
	EndIf
EndFunc   ;==>_DisconnectSelected

Func _RemoveSelected()
	Local $iIndex = _GetSelectedIndex()
	If $iIndex < 0 Then
		_ShowStatus("Select a device first.", 2)
		Return
	EndIf

	Local $sName = $g_aDevices[$iIndex][0]

	$g_bAllowAutoHide = False
	Local $iAns = MsgBox(BitOR($MB_ICONQUESTION, $MB_YESNO, $MB_DEFBUTTON2), $APP_TITLE, _
			"Remove this paired device from Windows?" & @CRLF & @CRLF & $sName)
	$g_bAllowAutoHide = True
	If $iAns <> $IDYES Then Return

	Local $tAddress = DllStructCreate($TAG_UINT64)
	DllStructSetData($tAddress, "Value", $g_aDevices[$iIndex][1])

	Local $aRet = DllCall($g_hBth, "dword", "BluetoothRemoveDevice", "struct*", $tAddress)
	If @error Or Not IsArray($aRet) Then
		_ShowStatus("Failed to remove device.", 2)
		Return
	EndIf

	If $aRet[0] = 0 Then
		_RefreshDevices()
		_ShowStatus($sName & " — removed.", 1)
	Else
		_ShowStatus("Windows returned error " & $aRet[0] & " while removing " & $sName & ".", 2)
	EndIf
EndFunc   ;==>_RemoveSelected

Func _PairNewDevice()
	_ShowStatus("Opening Windows Settings...", 3)
	; Prefer the modern Settings page; fall back to the legacy control panel dialog
	ShellExecute("ms-settings:bluetooth")
	If @error Then
		Run(@ComSpec & ' /c start "" bthprops.cpl', "", @SW_HIDE)
	EndIf
	; Hide our popup so it doesn't overlap Windows Settings
	_HidePopup()
EndFunc   ;==>_PairNewDevice

Func _QuitApp()
	If $g_hRadio <> 0 Then _WinAPI_CloseHandle($g_hRadio)
	If $g_hBth <> -1 Then DllClose($g_hBth)
	Exit
EndFunc   ;==>_QuitApp

; ----------------------------------------------------------------------------------------------------------------------
; Autostart (HKCU\...\Run) - toggles whether the app launches with Windows
; ----------------------------------------------------------------------------------------------------------------------
Func _IsAutostartEnabled()
	Local $sVal = RegRead($AUTOSTART_KEY, $AUTOSTART_NAME)
	If @error Then Return False
	Return ($sVal <> "")
EndFunc   ;==>_IsAutostartEnabled

Func _GetAutostartCommand()
	; When compiled, @ScriptFullPath is the .exe path. When running as .au3, include the AutoIt runtime.
	If @Compiled Then
		Return '"' & @ScriptFullPath & '"'
	Else
		Return '"' & @AutoItExe & '" "' & @ScriptFullPath & '"'
	EndIf
EndFunc   ;==>_GetAutostartCommand

Func _SetAutostart($bEnable)
	If $bEnable Then
		RegWrite($AUTOSTART_KEY, $AUTOSTART_NAME, "REG_SZ", _GetAutostartCommand())
		Return Not @error
	Else
		RegDelete($AUTOSTART_KEY, $AUTOSTART_NAME)
		; "Value didn't exist" is fine — end state is still 'disabled'
		Return True
	EndIf
EndFunc   ;==>_SetAutostart

Func _ToggleAutostart()
	Local $bCurrently = _IsAutostartEnabled()
	If _SetAutostart(Not $bCurrently) Then
		_SyncAutostartMenu()
		If Not $bCurrently Then
			_ShowStatus("Autostart enabled — app will launch with Windows.", 1)
		Else
			_ShowStatus("Autostart disabled.", 0)
		EndIf
	Else
		_ShowStatus("Failed to update autostart setting.", 2)
	EndIf
EndFunc   ;==>_ToggleAutostart

Func _SyncAutostartMenu()
	If _IsAutostartEnabled() Then
		TrayItemSetState($g_idTrayAutostart, $TRAY_CHECKED)
	Else
		TrayItemSetState($g_idTrayAutostart, $TRAY_UNCHECKED)
	EndIf
EndFunc   ;==>_SyncAutostartMenu

; ======================================================================================================================
; Bluetooth low-level helpers
; ======================================================================================================================
Func _GetDeviceInfoByIndex($iIndex)
	If $iIndex < 0 Or $iIndex >= UBound($g_aDevices) Then Return SetError(1, 0, 0)

	Local $tInfo = DllStructCreate($TAG_BLUETOOTH_DEVICE_INFO)
	DllStructSetData($tInfo, "dwSize", DllStructGetSize($tInfo))
	DllStructSetData($tInfo, "Address", $g_aDevices[$iIndex][1])

	Local $aRet = DllCall($g_hBth, "dword", "BluetoothGetDeviceInfo", "handle", $g_hRadio, "struct*", $tInfo)
	If @error Or Not IsArray($aRet) Or $aRet[0] <> 0 Then Return SetError(1, 0, 0)
	Return $tInfo
EndFunc   ;==>_GetDeviceInfoByIndex

Func _ApplyAudioProfiles(ByRef $tInfo, $bEnable)
	Local $aProfiles[3] = [$GUID_HANDSFREE, $GUID_AUDIOSINK, $GUID_HEADSET]
	Local $bAnySuccess = False

	For $i = 0 To UBound($aProfiles) - 1
		Local $sGuid = $aProfiles[$i]
		If $bEnable Then
			; Best effort: disable first, then enable, to force a reconnect when possible
			_SetServiceState($tInfo, $sGuid, False)
			If _SetServiceState($tInfo, $sGuid, True) Then $bAnySuccess = True
		Else
			If _SetServiceState($tInfo, $sGuid, False) Then $bAnySuccess = True
		EndIf
	Next
	Return $bAnySuccess
EndFunc   ;==>_ApplyAudioProfiles

Func _SetServiceState(ByRef $tInfo, $sGuid, $bEnable)
	Local $tGuid = DllStructCreate($TAG_GUID)
	Local $aGuid = DllCall("ole32.dll", "long", "CLSIDFromString", "wstr", $sGuid, "struct*", $tGuid)
	If @error Or Not IsArray($aGuid) Or $aGuid[0] <> 0 Then Return False

	Local $iFlag = $BT_SERVICE_DISABLE
	If $bEnable Then $iFlag = $BT_SERVICE_ENABLE

	Local $aRet = DllCall($g_hBth, "dword", "BluetoothSetServiceState", _
			"handle", $g_hRadio, _
			"struct*", $tInfo, _
			"struct*", $tGuid, _
			"dword", $iFlag)

	If @error Or Not IsArray($aRet) Then Return False
	If $aRet[0] = 0 Then Return True
	; Already enabled / already disabled -> good enough for UX
	If $aRet[0] = $E_INVALIDARG_UNSIGNED Then Return True
	If $aRet[0] = $ERROR_SERVICE_DOES_NOT_EXIST Then Return False
	Return False
EndFunc   ;==>_SetServiceState

; ======================================================================================================================
; Generic helpers
; ======================================================================================================================
Func _GetSelectedIndex()
	Local $iIndex = _GUICtrlListView_GetSelectionMark($g_hList)
	If $iIndex >= 0 Then
		If _GUICtrlListView_GetItemSelected($g_hList, $iIndex) Then Return $iIndex
	EndIf
	For $i = 0 To _GUICtrlListView_GetItemCount($g_hList) - 1
		If _GUICtrlListView_GetItemSelected($g_hList, $i) Then Return $i
	Next
	Return -1
EndFunc   ;==>_GetSelectedIndex

Func _FindDeviceIndexByAddress($sAddressHex)
	For $i = 0 To UBound($g_aDevices) - 1
		If $g_aDevices[$i][2] = $sAddressHex Then Return $i
	Next
	Return -1
EndFunc   ;==>_FindDeviceIndexByAddress

Func _FormatBtAddress($uValue)
	Local $sHex = Hex($uValue, 12)
	Local $sOut = ""
	For $i = 1 To StringLen($sHex) Step 2
		If $sOut <> "" Then $sOut &= ":"
		$sOut &= StringMid($sHex, $i, 2)
	Next
	Return $sOut
EndFunc   ;==>_FormatBtAddress

; Converts 0xRRGGBB (RGB) into 0xBBGGRR (BGR / COLORREF) used by custom draw
Func _RgbToBgr($iRgb)
	Local $r = BitAND(BitShift($iRgb, 16), 0xFF)
	Local $g = BitAND(BitShift($iRgb, 8), 0xFF)
	Local $b = BitAND($iRgb, 0xFF)
	Return BitOR(BitShift($b, -16), BitShift($g, -8), $r)
EndFunc   ;==>_RgbToBgr
