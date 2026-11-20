# NetAuth 개발 계획 및 진행표

개발 PC에는 PClient가 설치되어 있지 않으므로, 테스트용 Windows 앱에서 로그인 화면과 결과를 재현한 뒤 NetAuth를 별도 프로세스로 실행해 검증함. 첫 개발 목표는 **더미 창을 띄우고 NetAuth가 로그아웃 상태를 읽는 것**임. 제품 요구사항과 TC 번호는 [개발 기획서](DEVELOPMENT_PLAN.md)를 따름.

## 현재 위치

- [x] Windows용 .NET 10 프로젝트 구성. 기존 환경 준비 단계에서 Debug 빌드, 시작 테스트, Release 실행을 확인함.
- [x] 시작 프로그램에서 UI Automation 어셈블리 로드 확인. 검증 위치는 `src/NetAuth/Program.cs`와 `tests/Startup.Tests.ps1`임.
- [x] 더미 창 구현 및 별도 프로세스에서 NetAuth의 읽기 전용 상태 탐지 확인.
- [ ] 다음 작업은 가상 자격 증명을 사용한 NetAuth의 로그인 요청 및 결과 처리 구현임.

작업을 마칠 때 해당 항목에 체크하고, 문서 하단에 날짜·환경·관찰 결과를 기록함. 더미 테스트가 통과해도 실환경 항목은 해당 PC에서 검증할 때까지 열린 상태로 유지함.

## 1단계 · 더미 로그인 창 구현

제공된 화면에서 확인되는 요소는 ‘창원대 네트워크 접근제어’ 문구, ‘로그아웃 상태입니다.’ 표시, 값이 채워진 ID 입력란, 빈 비밀번호 입력란, ‘로그인’ 버튼임. ‘ID 저장’은 선택, ‘자동 로그인’은 해제 상태임. 화면 내부 문구만으로 Windows 창 제목이나 접근성 속성을 확정할 수 없음.

- [x] `tests/NetAuth.DummyClient/`에 별도 WPF 실행 프로젝트를 추가함. 창에 ‘NetAuth 테스트용’ 제목과 NA 표식을 두고 가상 ID와 마스킹되는 비밀번호 입력란을 사용함. 인증 요청은 프로세스 내부에서 처리함.
- [x] 참고 화면의 세로 배치에 맞춰 상단 상태 문구, 밑줄 입력란, 그라데이션 로그인 버튼, 체크박스를 배치함. UI Automation으로 역할과 상태를 읽을 수 있도록 더미 전용 식별자를 부여함.
- [x] 성공, 이미 인증됨, 자격 증명 거부, 응답 지연, 연결 오류, 추가 인증, 필수 컨트롤 누락을 시작 인수로 선택할 수 있게 함. 창에서 시나리오, 제출 횟수, 현재 상태를 확인함.

**완료 기준** — 개발자가 가상 값으로 한 번 제출하면 선택한 결과와 제출 횟수 1회를 확인할 수 있음. 이미 인증된 시나리오는 제출 횟수 0회에서 시작함.

### 실행 방법

저장소 루트에서 빌드한 뒤 두 PowerShell 세션에서 아래 명령을 실행함. 더미 창에서 가상 ID `demo-user`와 가상 비밀번호 `demo-pass`로 로그인할 수 있음. 기본 시나리오는 `Success`이며, 다른 시나리오는 마지막 인수로 전달함.

```powershell
dotnet build NetAuth.slnx
dotnet run --project tests/NetAuth.DummyClient --no-build -- Success
```

```powershell
dotnet run --project src/NetAuth --no-build -- --probe-dummy
```

더미 시나리오 인수는 `Success`, `AlreadyAuthenticated`, `Rejected`, `Delayed`, `ConnectionError`, `AdditionalVerification`, `MissingControl`임. 더미 창을 닫은 뒤 Debug 빌드 상태에서 아래 명령으로 시나리오를 검증함.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/DummyClient.Tests.ps1
```

## 2단계 · NetAuth 구현 순서

- [x] **읽기 전용 탐지** — `--probe-dummy`로 실행 중인 더미 프로세스의 창과 상태를 한 번 조회함. 대상 없음·창 미준비·미확인 상태는 각각 결과 코드로 반환함. 주기 감시는 아래 감시 작업에서 구현 예정임.
- [ ] **입력과 결과 판정** — 대상 창과 로그아웃 상태를 확인한 경우에만 테스트 값을 입력하고 한 번 제출함. 저장된 ID가 있는 경우 값을 교체하며 두 체크박스의 선택 상태를 보존함. 제출 후 명시적인 결과 신호를 확인함.
- [ ] **자격 증명과 로그** — Windows 보호 저장소에 더미 전용 항목을 저장·조회·삭제함. 저장된 값이 없으면 입력을 중단함. 로그에는 상태 전환과 오류 사유를 남기고 입력값은 제외함.
- [ ] **감시와 재시도** — 일시 장애에 대한 대기 간격과 시도 상한을 적용함. 결과 대기 중 중복 요청을 막고, 추가 인증·UI 불일치·계정 잠금 징후에서는 수동 조치 상태로 전환함.
- [ ] **자동 시작과 배포** — Release 배포본을 준비하고 대화형 사용자 로그온을 기준으로 작업 스케줄러 등록·해제를 검증함.

## 3단계 · 개발 PC 통합 테스트

더미를 별도 프로세스로 실행하고 NetAuth가 Windows UI Automation을 통해 조작하도록 검증함. 결과는 더미의 제출 횟수·화면 상태와 NetAuth 로그를 대조하여 판정함.

| 완료 | 기획서 항목 | 실행 조건 | 통과 기준 |
| --- | --- | --- | --- |
| [ ] | TC-01 | 저장된 가상 ID가 있는 로그아웃 화면에서 성공 응답 | ID 중복 입력 없이 제출 1회, 두 체크박스 상태 유지, 성공 신호 수신 후 인증됨으로 기록 |
| [ ] | TC-02 | 이미 인증된 화면에서 감시 주기 반복 | 입력·제출 0회, 인증 상태 유지 |
| [ ] | TC-03 | NetAuth 시작 후 더미를 지연 실행 | 대기 중 제출 0회, 창 표시 후 로그아웃 상태 탐지 |
| [ ] | TC-04, TC-06 | 자격 증명 거부와 일시 단절을 각각 모의 | 거부 시 설정한 상한 이내 중단, 일시 장애 시 대기 간격 준수, 응답 대기 중 중복 제출 0회 |
| [ ] | TC-05, TC-10 | 필수 컨트롤 누락 또는 추가 인증 표시 | 자동 입력 중단, 수동 조치 사유 기록 |
| [ ] | TC-07 | NetAuth를 두 번 실행 | 같은 로그인 요청의 총 제출 횟수 1회 |
| [ ] | TC-11 | 식별 가능한 가상 비밀값을 저장·사용·삭제 | 로그와 설정에 해당 값 없음, 삭제 후 다시 실행하면 제출 0회 |
| [ ] | 결과 판정 경계 | 제출 직후 결과 표시 없이 창을 닫음 | 인증 여부 미확인으로 기록, 성공 처리 없음 |

## 4단계 · 실제 PClient 설치 PC 검증

- [ ] **실행 전제** — 학교의 자동 인증·계정 보관 허용 범위, PClient 버전·경로·프로세스명, 사용자 로그온 및 원격 접속 조건을 확인함.
- [ ] **읽기 전용 조사** — 일반 사용자 세션에서 실제 창 제목과 접근성 트리를 확인함. 로그아웃·인증 성공·실패 각각의 관찰 신호를 기록하고 더미와 다른 항목을 반영함. 성공 신호를 식별하기 어려우면 결과 판정을 미확인으로 유지함.
- [ ] **정상 인증** — 허용 범위 확인 후 실환경에서 TC-01, TC-02를 검증함. 실제 계정의 비밀번호와 화면 속 ID는 결과 기록에서 제외함.
- [ ] **재부팅과 세션 전환** — TC-08, TC-09, TC-12에 따라 로그온 전 대기, 바탕화면 진입 후 시작, 잠금·원격 세션 해제 및 복귀를 각각 확인함. 세션별 실행 여부와 인증 결과를 기록함.

### 로그아웃 상태 먼저 조사

1. `tools/Inspect-PClient.ps1`을 PClient 설치 PC로 복사하고, PClient 로그인 창을 화면에 표시함.
2. PClient 창과 같은 Windows 데스크톱 세션에서 Windows PowerShell을 열고, 파일이 있는 폴더에서 아래 명령을 실행함. 현재 세션의 `PClientUI` 프로세스에서 PID를 자동으로 얻음.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inspect-PClient.ps1
```

- `LoginRequired` 및 `VisibleLogoutText`는 대상 창에서 로그아웃 문구가 읽혔음을 의미함. `ProcessName`, `StatusName`, `AutomationId`, `ControlType`을 기록함.
- `UnknownState` 및 `LogoutTextNotExposed`는 예상 문구를 가진 화면 요소가 확인되지 않았음을 의미함. 이 경우 Live Inspect로 문구가 노출되는 위치나 실제 속성을 조사함.
- `PClientUiNotInSession`이면 PClient 창을 연 데스크톱에서 다시 실행함. `MultiplePClientUiProcesses` 또는 프로세스명 변경으로 자동 선택을 할 수 없으면 작업 관리자에서 창의 PID를 찾아 `-ProcessId <PID>`로 지정함. `WindowNotFound`이면 창을 표시한 후 다시 실행함.
- 진단은 상태 문구만 검사하며 로그인이나 입력을 수행하지 않음. 가입 계정이나 자격 증명 입력 없이 실행할 수 있음.

## 검증 기록

| 날짜 | 환경 | 항목 | 결과 및 근거 |
| --- | --- | --- | --- |
| 2026-11-21 | 개발 PC | 환경 준비 | 기존 검증에서 `Startup.Tests.ps1` 통과 및 Release 실행 확인. UI Automation 어셈블리 로드까지 확인됨 |
| 2026-11-21 | 개발 PC | 더미 창 및 읽기 전용 탐지 | Debug 빌드 경고·오류 0건, 시작 테스트 및 서식 검사 통과. Windows 대화형 세션에서 더미 상태 7개, 제출 횟수, 비밀번호 마스킹 속성, 체크박스 기본값 확인. 테스트 스크립트에서 제출을 수행하고 NetAuth는 상태를 조회함 |
| 2026-11-21 | 개발 PC | PID 기반 진단 | Windows PowerShell로 더미 창을 검사하여 로그아웃 문구가 노출되면 `LoginRequired`, 문구가 없으면 `UnknownState`가 반환됨을 확인함 |
| 2026-11-21 | PClient 설치 PC | 로그아웃 상태 조사 | 수동 PID 지정으로 `PClientUI`의 창 1개에서 `로그아웃 상태입니다.`를 읽어 `LoginRequired` 확인. 상태 요소는 `AutomationId=1013`, `ControlType.Pane`임. 별도 세션의 `SPAgent`를 지정하면 `DifferentSession` 반환됨 |
| 2026-11-21 | 개발 PC | 프로세스 자동 선택 | 더미를 `PClientUI.exe` 이름으로 실행해 PID 자동 선택 및 `LoginRequired` 확인. 기존 더미 시나리오 7개 통과 |
