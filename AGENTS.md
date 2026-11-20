# Repository Guidelines

## 프로젝트 구조

- `NetAuth.slnx`는 Windows용 C# 솔루션임. `src/NetAuth/Program.cs`는 CLI와 WPF 계정 설정 화면의 진입점임. 화면은 `UI/`, 사용자별 자격 증명 저장은 `Security/`에서 관리함.
- 기능 범위와 단계별 완료 조건은 [개발 기획서](docs/DEVELOPMENT_PLAN.md)에서 확인함. PClient 탐지 코드는 구현 시 `src/NetAuth/PClient/`에 두고, 자격 증명 저장은 `Security/`로 분리함.
- `tests/`에는 개발자가 로컬에서 실행할 검증 스크립트를 둠.

## 개발 환경과 명령

Windows x64와 .NET 10 SDK를 사용함. SDK 선택 기준은 `global.json`에서 관리함. 이 작업 폴더에 설치된 SDK를 사용하려면 새 PowerShell 세션에서 저장소 루트로 이동한 뒤 아래 명령을 실행함. 다른 PC에서는 같은 버전대의 SDK를 설치하고 `dotnet --version`으로 확인함.

```powershell
$env:PATH = "$PWD\.dotnet;$env:PATH"
dotnet --version
dotnet build NetAuth.slnx
dotnet run --project src/NetAuth --no-build
& ./tests/Startup.Tests.ps1
```

빌드 명령은 복원과 Debug 컴파일을 수행함. 실행 명령은 계정 설정 창을 시작함. 인수 `-- --settings-dummy`를 추가하면 가상 계정용 설정 창을 시작함. 배포 파일은 `dotnet publish src/NetAuth -c Release -o artifacts/publish`로 생성함.

## 코드 스타일과 검증

- C# 들여쓰기는 `.editorconfig`에 따라 공백 4칸을 사용함. 타입과 메서드는 `PascalCase`, 매개변수와 지역 변수는 `camelCase`로 작성함. 서식은 `dotnet format NetAuth.slnx --verify-no-changes`로 확인함.
- 시작 테스트는 Debug 빌드 후 `--check-ui-automation`의 종료 코드와 UI Automation 어셈블리 이름을 확인함. PowerShell 테스트 파일은 `Startup.Tests.ps1`처럼 검증 대상 이름 뒤에 `.Tests.ps1`을 붙임.
- PClient 연동을 변경할 때는 기획서 7장의 관련 시나리오 번호, 사용한 PClient 버전, 관찰 결과를 기록함. 창이 사라진 경우에도 인증 성공을 판정하려면 별도의 상태 신호를 확인해야 함.

## 보안과 기여 절차

- 실제 계정을 사용하는 기능 개발 전 학교의 자동 인증 및 계정 보관 정책을 확인함. 비밀번호는 Windows 보호 저장소에서만 관리하고 로그와 PR 첨부 자료에서 제외함.
- 초기 저장소로 커밋 이력이 없어 커밋 제목에는 변경 대상과 동작을 간결하게 기재함. PR 본문에는 변경 목적, 실행한 검증 명령과 결과를 적고 관련 이슈가 있으면 연결함.
