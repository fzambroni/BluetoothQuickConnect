#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_UseX64=n
#AutoIt3Wrapper_UseUpx=n
#AutoIt3Wrapper_Icon=bt1.ico
#AutoIt3Wrapper_Res_Description=Updater
#AutoIt3Wrapper_Res_CompanyName=Fabricio Zambroni
#AutoIt3Wrapper_Res_LegalCopyright=Copyright © 2026 Fabricio Zambroni
#AutoIt3Wrapper_Res_Fileversion=1.1.1.1
#AutoIt3Wrapper_Res_ProductVersion=1.1.1.1
#AutoIt3Wrapper_Res_ProductName=Updater
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#cs ----------------------------------------------------------------------------

	 AutoIt Version: 3.3.18.0
	 Author:         myName

	 Script Function:
		Template AutoIt script.

#ce ----------------------------------------------------------------------------

$sFilePath = @ScriptDir & "\version.txt"
$sExecPath = @ScriptDir & "\BluetoothQuickConnect.exe"
Local $hFileOpen = FileOpen($sFilePath, 10)
If $hFileOpen <> -1 Then
	; Write data to the file using the handle returned by FileOpen.
	FileWrite($hFileOpen, FileGetVersion($sExecPath))
EndIf
