Unicode true
Name "NetAuth"
OutFile "${SETUP_EXE}"
InstallDir "$LOCALAPPDATA\Programs\NetAuth"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "NetAuth"

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\NetAuth"
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!include "MUI2.nsh"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Korean"

VIProductVersion "${APP_FILE_VERSION}"
VIAddVersionKey /LANG=0 "ProductName" "NetAuth"
VIAddVersionKey /LANG=0 "FileDescription" "NetAuth Setup"
VIAddVersionKey /LANG=0 "CompanyName" "NetAuth"
VIAddVersionKey /LANG=0 "LegalCopyright" ""
VIAddVersionKey /LANG=0 "FileVersion" "${APP_FILE_VERSION}"
VIAddVersionKey /LANG=0 "ProductVersion" "${APP_VERSION}"

LangString InstallFailed ${LANG_ENGLISH} "NetAuth could not be installed. Close NetAuth and retry."
LangString InstallFailed ${LANG_KOREAN} "NetAuth를 설치하지 못했습니다. NetAuth를 종료한 뒤 다시 시도해 주세요."
LangString UninstallFailed ${LANG_ENGLISH} "NetAuth could not be removed. Close NetAuth and retry."
LangString UninstallFailed ${LANG_KOREAN} "NetAuth를 제거하지 못했습니다. NetAuth를 종료한 뒤 다시 시도해 주세요."
LangString SetupBusy ${LANG_ENGLISH} "Another NetAuth setup operation is already running."
LangString SetupBusy ${LANG_KOREAN} "NetAuth 설치 또는 제거가 진행 중입니다. 완료된 뒤 다시 시도해 주세요."

!macro LockSetup
    System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\NetAuth.Setup") p .r0 ?e'
    Pop $1
    StrCmp $0 0 setup_busy
    StrCmp $1 183 setup_busy setup_ready
setup_busy:
    MessageBox MB_OK|MB_ICONSTOP "$(SetupBusy)" /SD IDOK
    SetErrorLevel 1
    Abort
setup_ready:
!macroend

Function .onInit
    !insertmacro LockSetup
FunctionEnd

Function un.onInit
    !insertmacro LockSetup
FunctionEnd

Section "NetAuth"
    SetShellVarContext current
    SetRegView 64
    SetOutPath "$INSTDIR"
    ClearErrors
    File /oname=NetAuth.exe.new "${APP_EXE}"
    IfErrors install_failed
    System::Call 'kernel32::MoveFileExW(w "$INSTDIR\NetAuth.exe.new", w "$INSTDIR\NetAuth.exe", i 1) i .r0'
    StrCmp $0 0 install_failed

    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateShortcut "$SMPROGRAMS\NetAuth.lnk" "$INSTDIR\NetAuth.exe" "" "$INSTDIR\NetAuth.exe" 0
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "NetAuth"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "NetAuth"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\NetAuth.exe,0"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
    IfErrors install_failed
    Goto install_done

install_failed:
    Delete "$INSTDIR\NetAuth.exe.new"
    MessageBox MB_OK|MB_ICONSTOP "$(InstallFailed)" /SD IDOK
    SetErrorLevel 1
    Abort
install_done:
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    SetRegView 64
    ClearErrors
    Delete "$INSTDIR\NetAuth.exe"
    IfErrors uninstall_failed
    Delete "$SMPROGRAMS\NetAuth.lnk"
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
    Delete "$INSTDIR\Uninstall.exe"
    SetOutPath "$TEMP"
    RMDir "$INSTDIR"
    Goto uninstall_done

uninstall_failed:
    MessageBox MB_OK|MB_ICONSTOP "$(UninstallFailed)" /SD IDOK
    SetErrorLevel 1
    Abort
uninstall_done:
SectionEnd
