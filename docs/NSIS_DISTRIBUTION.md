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
- 빌드 시 `src/NetAuth/Assets/netauth.png`에서 마법사 시작·완료 화면의 브랜드 이미지와 진행 화면 헤더를 생성함. 안내 문구는 Windows 표시 언어에 따라 한국어 또는 영어로 표시됨.
- 업데이트나 제거 전 NetAuth를 종료함. Windows **설정 → 앱 → 설치된 앱**에서 제거할 수 있음. 제거 시 별도로 보관된 계정은 유지되며 앱의 계정 관리 화면에서 삭제할 수 있음.
- 연구실 PC에서 Smart App Control을 켠 상태로 설치, 시작 메뉴 실행, 버전 갱신 및 제거를 확인함. 무서명 설치본의 실행 여부는 배포본과 대상 PC에서 확인이 필요함. PClient 연동 검증은 [개발 진행표](DEVELOPMENT_TRACKER.md)의 실환경 단계에 따름.

## 개발 PC 검증 기록

- 2026-11-21 Smart App Control이 켜진 개발 PC에서 `1.0.0` 신규 설치, 시작 진단, `1.0.1-test` 업데이트, 제거를 확인함. 설치·제거 EXE 및 앱의 NA 아이콘 일치, 시작 메뉴와 설치된 앱 목록의 아이콘 경로를 확인함.
- 설치 동시 실행 시 중복 작업을 거부함. 실행 파일이 잠긴 상태에서는 업데이트를 중단하고 기존 파일과 버전을 유지함. 검증용 설치에서 관련 Code Integrity 차단 기록이 없었음. 실제 PClient PC에서 이 배포본을 사용한 설치와 연동 결과는 확인 대기 상태임.
