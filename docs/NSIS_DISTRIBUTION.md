# NetAuth NSIS 배포

## 설치본 빌드

Windows x64와 저장소의 `global.json`에 맞는 .NET SDK가 필요함. 저장소 루트에서 다음 명령을 실행함.

```powershell
.\tools\Build-Nsis.ps1
```

- 최신 소스를 자체 포함 Windows x64 앱으로 게시한 뒤 `artifacts/nsis/NetAuth-Setup-<버전>-win-x64.exe`를 생성함. 배포 시 이 설치 파일 하나를 전달함.
- 기본 버전은 .NET 프로젝트의 제품 버전을 사용함. 배포 버전을 지정하려면 `.\tools\Build-Nsis.ps1 -Version 1.1.0`을 실행함. 새 버전도 같은 설치 경로에서 기존 파일을 교체함.
- 첫 빌드에서 공식 NSIS 3.13 ZIP을 내려받아 SHA-256을 검증하고 `artifacts/nsis`에 캐시함. 이미 설치한 NSIS가 있다면 `-MakeNsisPath`에 `makensis.exe` 경로를 지정할 수 있음.

## 설치 및 배포 전 검증

- 현재 사용자 권한으로 `%LOCALAPPDATA%\Programs\NetAuth`에 설치함. 앱, 시작 메뉴, 설치된 앱 목록, 설치·제거 마법사에서 `src/NetAuth/Assets/netauth.ico`의 NA 아이콘을 사용함.
- 설치 옵션에서 **Windows 로그인 시 NetAuth 실행**과 **바탕 화면에 바로가기 만들기**를 각각 선택할 수 있음. 새 설치에서는 둘 다 기본 해제이며, 업데이트 시 기존 선택을 표시함. NetAuth의 **자동 로그인**을 켜면 Windows 시작 등록과 PClient 자동 로그인을 함께 설정함. 해당 선택을 켠 상태로 업데이트하면 자동 로그인 설정도 유지됨.
- 빌드 시 `src/NetAuth/Assets/netauth.png`에서 마법사 시작·완료 화면의 브랜드 이미지와 진행 화면 헤더를 생성함. 안내 문구는 Windows 표시 언어에 따라 한국어 또는 영어로 표시됨.
- NetAuth 창을 닫으면 트레이에 유지됨. 업데이트나 제거 전 트레이의 NetAuth 아이콘을 우클릭해 **종료**를 선택함. Windows **설정 → 앱 → 설치된 앱**에서 제거하면 현재 Windows 사용자의 저장된 PClient 계정, NetAuth 시작 항목 및 바로가기를 삭제함. 무인 제거에도 동일하게 적용함. 기존 설치 위에 업데이트하면 저장 계정을 유지하고 시작 옵션에는 기존 선택을 표시함.
- `tests/NsisInstaller.Tests.ps1 -PreviousInstallerPath <이전 설치본> -InstallerPath <새 설치본>`으로 덮어쓰기 시 계정·시작 설정 보존, 제거 시 계정 삭제, 파일 잠금 후 재시도를 확인함.

## v1.0.0 배포 검증

- v1.0.0과 기능이 같은 v0.0.9를 실제 PClient 설치 PC에서 검증함. 재부팅 후 자동 로그인과 사용 중 로그아웃 후 재로그인을 사용자 보고로 확인함.
- 2026-11-25 개발 PC에서 Smart App Control을 켠 상태로 v1.0.0 설치, 계정 설정 창 실행 및 제거를 확인함. 관련 Code Integrity 차단 이벤트(3077·3033)는 0건임. 설치본과 앱은 서명되지 않아 다른 PC에서는 실행이 제한될 수 있음.
