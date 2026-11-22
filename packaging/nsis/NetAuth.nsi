Unicode true
Name "NetAuth"
OutFile "${SETUP_EXE}"
InstallDir "$LOCALAPPDATA\Programs\NetAuth"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "NetAuth"
SetFont "Malgun Gothic" 9

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\NetAuth"
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!define MUI_BGCOLOR FCFDFE
!define MUI_TEXTCOLOR 152B46
!define MUI_WELCOMEFINISHPAGE_BITMAP "${APP_WIZARD_BITMAP}"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "${APP_HEADER_BITMAP}"
!define MUI_HEADERIMAGE_BITMAP_STRETCH AspectFitHeight
!include "MUI2.nsh"
!include "LogicLib.nsh"

!define MUI_WELCOMEPAGE_TITLE "$(NetAuthWelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(NetAuthWelcomeText)"
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_HEADER_TEXT "$(NetAuthInstallTitle)"
!define MUI_PAGE_HEADER_SUBTEXT "$(NetAuthInstallText)"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "$(NetAuthFinishTitle)"
!define MUI_FINISHPAGE_TEXT "$(NetAuthFinishText)"
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

LangString NetAuthWelcomeTitle ${LANG_ENGLISH} "Set up PClient access"
LangString NetAuthWelcomeTitle ${LANG_KOREAN} "PClient 로그인 준비"
LangString NetAuthWelcomeText ${LANG_ENGLISH} "Save your account in NetAuth to fill in the PClient sign-in fields.$\r$\n$\r$\nNetAuth installs for your Windows account. After setup, open it from the Start menu."
LangString NetAuthWelcomeText ${LANG_KOREAN} "PClient 계정을 등록해 로그인 입력란을 채울 수 있습니다.$\r$\n$\r$\n현재 Windows 사용자에게 설치됩니다.$\r$\n설치 후 시작 메뉴에서 NetAuth를 열 수 있습니다."
LangString NetAuthInstallTitle ${LANG_ENGLISH} "Installing NetAuth"
LangString NetAuthInstallTitle ${LANG_KOREAN} "NetAuth 설치 중"
LangString NetAuthInstallText ${LANG_ENGLISH} "Setting up the app and its Start menu shortcut."
LangString NetAuthInstallText ${LANG_KOREAN} "앱 파일과 시작 메뉴 바로가기를 준비하고 있습니다."
LangString NetAuthFinishTitle ${LANG_ENGLISH} "NetAuth is ready"
LangString NetAuthFinishTitle ${LANG_KOREAN} "NetAuth 설치 완료"
LangString NetAuthFinishText ${LANG_ENGLISH} "Open NetAuth from the Start menu to manage your PClient account."
LangString NetAuthFinishText ${LANG_KOREAN} "시작 메뉴에서 NetAuth를 열어 계정을 관리하세요."

LangString InstallFailed ${LANG_ENGLISH} "NetAuth could not be installed. Close NetAuth and retry."
LangString InstallFailed ${LANG_KOREAN} "NetAuth를 설치하지 못했습니다. NetAuth를 종료한 뒤 다시 시도해 주세요."
LangString UninstallFailed ${LANG_ENGLISH} "NetAuth could not be removed. Close NetAuth and retry."
LangString UninstallFailed ${LANG_KOREAN} "NetAuth를 제거하지 못했습니다. NetAuth를 종료한 뒤 다시 시도해 주세요."
LangString InstallCleanupPending ${LANG_ENGLISH} "NetAuth is installed, but previous files could not be removed. Close any app using them and run setup again."
LangString InstallCleanupPending ${LANG_KOREAN} "NetAuth는 설치되어 있지만 이전 파일을 정리하지 못했습니다. 파일을 사용 중인 프로그램을 종료한 뒤 설치를 다시 실행해 주세요."
LangString SetupBusy ${LANG_ENGLISH} "Another NetAuth setup operation is already running."
LangString SetupBusy ${LANG_KOREAN} "NetAuth 설치 또는 제거가 진행 중입니다. 완료된 뒤 다시 시도해 주세요."

Var PreviousInstall
Var PreviousVersion
Var AppReplaced
Var UninstallerReplaced
Var ShortcutReplaced

!macro ReplaceInstalledFile PATH STAGED REPLACED
    ClearErrors
    ${If} ${FileExists} "${PATH}"
        Rename "${PATH}" "${PATH}.netauth-backup"
        IfErrors install_failed
    ${EndIf}
    Rename "${STAGED}" "${PATH}"
    IfErrors install_failed
    StrCpy ${REPLACED} 1
!macroend

!macro RestoreInstalledFile PATH REPLACED
    ${If} ${FileExists} "${PATH}.netauth-backup"
        System::Call 'kernel32::MoveFileExW(w "${PATH}.netauth-backup", w "${PATH}", i 1) i .r0'
    ${ElseIf} ${REPLACED} == 1
        Delete "${PATH}"
    ${EndIf}
!macroend

!macro IfBackupExists TARGET
    IfFileExists "$INSTDIR\NetAuth.exe.netauth-backup" ${TARGET}
    IfFileExists "$INSTDIR\Uninstall.exe.netauth-backup" ${TARGET}
    IfFileExists "$SMPROGRAMS\NetAuth.lnk.netauth-backup" ${TARGET}
!macroend

!macro RemoveCommittedBackups FAILURE
    ReadRegDWORD $0 HKCU "${UNINSTALL_KEY}" "BackupsCommitted"
    ${If} $0 == 1
        ClearErrors
        Delete "$INSTDIR\NetAuth.exe.netauth-backup"
        Delete "$INSTDIR\Uninstall.exe.netauth-backup"
        Delete "$SMPROGRAMS\NetAuth.lnk.netauth-backup"
        IfErrors ${FAILURE}
        DeleteRegValue HKCU "${UNINSTALL_KEY}" "BackupsCommitted"
        IfErrors ${FAILURE}
    ${EndIf}
!macroend

!macro WriteInstallRegistration VERSION
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "NetAuth"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "NetAuth"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\NetAuth.exe,0"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
!macroend

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
    ReadRegStr $PreviousInstall HKCU "${UNINSTALL_KEY}" "InstallLocation"
    ${If} $PreviousInstall != ""
    ${AndIf} $PreviousInstall != "$INSTDIR"
        Goto install_report_failure
    ${EndIf}
    ${If} $PreviousInstall == "$INSTDIR"
        !insertmacro RemoveCommittedBackups install_cleanup_pending
    ${EndIf}
    !insertmacro IfBackupExists install_report_failure

    ClearErrors
    SetOutPath "$INSTDIR"
    IfErrors install_report_failure
    ClearErrors
    File /oname=NetAuth.exe.new "${APP_EXE}"
    IfErrors install_failed
    WriteUninstaller "$INSTDIR\Uninstall.exe.new"
    IfErrors install_failed
    CreateShortcut "$SMPROGRAMS\NetAuth.pending.lnk" "$INSTDIR\NetAuth.exe" "" "$INSTDIR\NetAuth.exe" 0
    IfErrors install_failed

    !insertmacro ReplaceInstalledFile "$INSTDIR\Uninstall.exe" "$INSTDIR\Uninstall.exe.new" $UninstallerReplaced
    !insertmacro ReplaceInstalledFile "$SMPROGRAMS\NetAuth.lnk" "$SMPROGRAMS\NetAuth.pending.lnk" $ShortcutReplaced
    !insertmacro ReplaceInstalledFile "$INSTDIR\NetAuth.exe" "$INSTDIR\NetAuth.exe.new" $AppReplaced

    ClearErrors
    ${If} $PreviousInstall == ""
        !insertmacro WriteInstallRegistration "${APP_VERSION}"
    ${Else}
        WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
    ${EndIf}
    IfErrors install_failed
    !insertmacro IfBackupExists install_mark_committed
    Goto install_done
install_mark_committed:
    ; 설치와 버전 등록이 모두 완료된 뒤에만 다음 실행에서 백업 삭제 허용
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "BackupsCommitted" 1
    IfErrors install_cleanup_pending
    !insertmacro RemoveCommittedBackups install_cleanup_pending
    Goto install_done
install_cleanup_pending:
    MessageBox MB_OK|MB_ICONSTOP "$(InstallCleanupPending)" /SD IDOK
    SetErrorLevel 1
    Abort

install_failed:
    ${If} $PreviousInstall == ""
    ${AndIf} $AppReplaced == 1
        DeleteRegKey HKCU "${UNINSTALL_KEY}"
    ${EndIf}
    !insertmacro RestoreInstalledFile "$INSTDIR\NetAuth.exe" $AppReplaced
    !insertmacro RestoreInstalledFile "$SMPROGRAMS\NetAuth.lnk" $ShortcutReplaced
    !insertmacro RestoreInstalledFile "$INSTDIR\Uninstall.exe" $UninstallerReplaced
    Delete "$INSTDIR\NetAuth.exe.new"
    Delete "$INSTDIR\Uninstall.exe.new"
    Delete "$SMPROGRAMS\NetAuth.pending.lnk"
install_report_failure:
    MessageBox MB_OK|MB_ICONSTOP "$(InstallFailed)" /SD IDOK
    SetErrorLevel 1
    Abort
install_done:
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    SetRegView 64
    ReadRegStr $PreviousInstall HKCU "${UNINSTALL_KEY}" "InstallLocation"
    ${If} $PreviousInstall != ""
    ${AndIf} $PreviousInstall != "$INSTDIR"
        Goto uninstall_report_failure
    ${EndIf}
    ReadRegStr $PreviousVersion HKCU "${UNINSTALL_KEY}" "DisplayVersion"
    ${If} $PreviousInstall == "$INSTDIR"
        !insertmacro RemoveCommittedBackups uninstall_report_failure
    ${EndIf}
    !insertmacro IfBackupExists uninstall_report_failure

    ClearErrors
    ${If} ${FileExists} "$SMPROGRAMS\NetAuth.lnk"
        Rename "$SMPROGRAMS\NetAuth.lnk" "$SMPROGRAMS\NetAuth.removing.lnk"
        IfErrors uninstall_report_failure
    ${EndIf}
    ${If} ${FileExists} "$INSTDIR\NetAuth.exe"
        ExecWait '"$INSTDIR\NetAuth.exe" --remove-pclient-preview-startup' $0
        IfErrors uninstall_failed
        StrCmp $0 0 +2
        Goto uninstall_failed
    ${EndIf}
    Delete "$INSTDIR\NetAuth.exe"
    IfErrors uninstall_failed
    Delete "$SMPROGRAMS\NetAuth.removing.lnk"
    IfErrors uninstall_failed
    ${If} $PreviousInstall != ""
        DeleteRegKey HKCU "${UNINSTALL_KEY}"
        IfErrors uninstall_failed
    ${EndIf}
    Delete "$INSTDIR\Uninstall.exe"
    ${If} ${Errors}
        ${If} $PreviousInstall != ""
            !insertmacro WriteInstallRegistration "$PreviousVersion"
        ${EndIf}
        Goto uninstall_failed
    ${EndIf}
    SetOutPath "$TEMP"
    RMDir "$INSTDIR"
    Goto uninstall_done

uninstall_failed:
    ${If} ${FileExists} "$INSTDIR\NetAuth.exe"
    ${AndIf} ${FileExists} "$SMPROGRAMS\NetAuth.removing.lnk"
        Rename "$SMPROGRAMS\NetAuth.removing.lnk" "$SMPROGRAMS\NetAuth.lnk"
    ${EndIf}
uninstall_report_failure:
    MessageBox MB_OK|MB_ICONSTOP "$(UninstallFailed)" /SD IDOK
    SetErrorLevel 1
    Abort
uninstall_done:
SectionEnd
