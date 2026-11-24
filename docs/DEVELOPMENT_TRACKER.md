# NetAuth 개발 계획 및 진행표

개발 PC에는 PClient가 설치되어 있지 않으므로, 테스트용 Windows 앱에서 로그인 화면과 결과를 재현한 뒤 NetAuth를 별도 프로세스로 실행해 검증함. 첫 개발 목표는 **더미 창을 띄우고 NetAuth가 로그아웃 상태를 읽는 것**임. 제품 요구사항과 TC 번호는 [개발 기획서](DEVELOPMENT_PLAN.md)를 따름.

## 현재 위치

- [x] Windows용 .NET 10 프로젝트 구성. 기존 환경 준비 단계에서 Debug 빌드, 시작 테스트, Release 실행을 확인함.
- [x] 시작 프로그램에서 UI Automation 어셈블리 로드 확인. 검증 위치는 `src/NetAuth/Program.cs`와 `tests/Startup.Tests.ps1`임.
- [x] 더미 창 구현 및 별도 프로세스에서 NetAuth의 읽기 전용 상태 탐지 확인.
- [x] NetAuth CLI에서 가상 계정 로그인 요청, 중복 실행 방지, 결과 판정 구현 및 검증.
- [x] 첫 실행 계정 설정, 계정 변경·삭제, Windows 사용자별 암호화 저장 구현.
- [ ] 실제 PClient 로그인 결과 신호 확인 및 운영용 로그인 연동.

작업을 마칠 때 해당 항목에 체크하고, 문서 하단에 날짜·환경·관찰 결과를 기록함. 더미 테스트가 통과해도 실환경 항목은 해당 PC에서 검증할 때까지 열린 상태로 유지함.

## 1단계 · 더미 로그인 창 구현

제공된 화면에서 확인되는 요소는 ‘창원대 네트워크 접근제어’ 문구, ‘로그아웃 상태입니다.’ 표시, 값이 채워진 ID 입력란, 빈 비밀번호 입력란, ‘로그인’ 버튼임. ‘ID 저장’은 선택, ‘자동 로그인’은 해제 상태임. 화면 내부 문구만으로 Windows 창 제목이나 접근성 속성을 확정할 수 없음.

- [x] `tests/NetAuth.DummyClient/`에 별도 WPF 실행 프로젝트를 추가함. 창에 ‘NetAuth 테스트용’ 제목과 NA 표식을 두고 가상 ID와 마스킹되는 비밀번호 입력란을 사용함. 인증 요청은 프로세스 내부에서 처리함.
- [x] 참고 화면의 세로 배치에 맞춰 상단 상태 문구, 밑줄 입력란, 그라데이션 로그인 버튼, 체크박스를 배치함. UI Automation으로 역할과 상태를 읽을 수 있도록 더미 전용 식별자를 부여함.
- [x] 성공, 이미 인증됨, 자격 증명 거부, 응답 지연, 응답 없음, 연결 오류, 추가 인증, 필수 컨트롤 누락을 시작 인수로 선택할 수 있게 함. 창에서 시나리오, 제출 횟수, 현재 상태를 확인함.

**완료 기준** — 개발자가 가상 값으로 한 번 제출하면 선택한 결과와 제출 횟수 1회를 확인할 수 있음. 이미 인증된 시나리오는 제출 횟수 0회에서 시작함.

### 실행 방법

저장소 루트에서 빌드한 뒤 두 PowerShell 세션에서 아래 명령을 실행함. 더미 창에서 가상 ID `demo-user`와 가상 비밀번호 `demo-pass`로 로그인할 수 있음. 기본 시나리오는 `Success`이며, 다른 시나리오는 마지막 인수로 전달함.

```powershell
dotnet build NetAuth.slnx
dotnet run --project tests/NetAuth.DummyClient --no-build -- Success
```

```powershell
dotnet run --project src/NetAuth --no-build -- --probe-dummy
dotnet run --project src/NetAuth --no-build -- --login-dummy
```

`--login-dummy`는 가상 계정으로 최대 한 번 제출하는 테스트 명령임. 더미 시나리오 인수는 `Success`, `AlreadyAuthenticated`, `Rejected`, `Delayed`, `NoResponse`, `ConnectionError`, `AdditionalVerification`, `MissingControl`임. 더미 창을 닫은 뒤 Debug 빌드 상태에서 아래 명령으로 시나리오를 검증함.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/DummyClient.Tests.ps1
```

## 2단계 · NetAuth 구현 순서

- [x] **읽기 전용 탐지** — `--probe-dummy`로 실행 중인 더미 프로세스의 창과 상태를 한 번 조회함. 대상 없음·창 미준비·미확인 상태는 각각 결과 코드로 반환함. 주기 감시는 아래 감시 작업에서 구현 예정임.
- [x] **입력과 결과 판정** — 더미 창과 로그아웃 상태를 확인한 경우에만 가상 계정으로 한 번 제출함. ID를 교체하고 체크박스 상태를 보존함. 실행이 겹치면 `LoginInProgress`를 반환함. 제출 후 8초 안에 결과 신호를 확인하지 못하거나 창이 사라지면 `UnknownState`를 반환함.
- [x] **자격 증명 저장** — 계정 정보를 Windows DPAPI의 현재 사용자 범위로 암호화해 저장·조회·삭제함. 운영용과 더미용은 파일과 암호화 범위 식별값을 각각 적용함.
- [x] **첫 실행 계정 설정** — 미등록 상태에서 ID와 마스킹된 비밀번호 입력란을 표시함. 저장, 재실행 시 복원, 변경, 삭제 확인, 입력 취소를 구현함. 더미 설정 화면에서 저장한 가상 계정으로 로그인 검증이 가능함.
- [ ] **운영 로그** — 시간과 상태 전환, 오류 사유를 기록하고 자격 증명을 제외함.
- [ ] **감시와 재시도** — 일시 장애에 대한 대기 간격과 시도 상한을 적용함. 결과 대기 중 중복 요청을 막고, 추가 인증·UI 불일치·계정 잠금 징후에서는 수동 조치 상태로 전환함.
- [ ] **실환경 자동 시작과 배포** — Windows 로그온 시 트레이에서 시작하는 앱에 PClient 자동 로그인을 연결함. 실제 PC 재부팅 후 실행과 인증을 검증할 예정임.

## 3단계 · 개발 PC 통합 테스트

더미를 별도 프로세스로 실행하고 NetAuth가 Windows UI Automation을 통해 조작하도록 검증함. 결과는 더미의 제출 횟수·화면 상태와 NetAuth 로그를 대조하여 판정함.

| 완료 | 기획서 항목 | 실행 조건 | 통과 기준 |
| --- | --- | --- | --- |
| [x] | TC-01 | 저장된 가상 ID가 있는 로그아웃 화면에서 성공 응답 | ID 중복 입력 없이 제출 1회, 두 체크박스 상태 유지, 성공 신호 수신 후 인증됨으로 표시 |
| [ ] | TC-02 | 이미 인증된 화면에서 감시 주기 반복 | 입력·제출 0회, 인증 상태 유지 |
| [ ] | TC-03 | NetAuth 시작 후 더미를 지연 실행 | 대기 중 제출 0회, 창 표시 후 로그아웃 상태 탐지 |
| [ ] | TC-04, TC-06 | 자격 증명 거부와 일시 단절을 각각 모의 | 거부 시 설정한 상한 이내 중단, 일시 장애 시 대기 간격 준수, 응답 대기 중 중복 제출 0회 |
| [ ] | TC-05, TC-10 | 필수 컨트롤 누락 또는 추가 인증 표시 | 자동 입력 중단, 수동 조치 사유 기록 |
| [x] | TC-07 | NetAuth를 두 번 실행 | 같은 로그인 요청의 총 제출 횟수 1회 |
| [x] | TC-11 | 식별 가능한 가상 비밀값을 저장·사용·삭제 | 계정 파일에 평문 없음, 재실행 후 저장 계정으로 더미 로그인 가능, 삭제 후 로그인 동작 비활성 |
| [x] | 결과 판정 경계 | 결과 없이 8초를 기다리거나 제출 직후 창을 닫음 | 두 경우 모두 `UnknownState` 반환 |

### 계정 설정 화면 실행

기본 실행은 PClient 계정 설정 창을 표시함. 첫 실행에는 입력란을 열고, 저장 이후에는 등록된 ID와 관리 버튼을 표시함. 현재 기본 창에서 계정을 저장하는 동작은 실제 PClient 로그인을 시작하지 않음.

```powershell
dotnet run --project src/NetAuth --no-build
dotnet run --project src/NetAuth --no-build -- --settings-dummy
```

- **UI와 색상** — 네이비 `#12365E`와 청록 `#60D9EB`으로 NA 모노그램을 구성하고, 밝은 청회색 안내 영역과 흰색 작업 영역에 파란 주요 동작을 배치함. 색상과 버튼 상태는 `src/NetAuth/UI/AccountTheme.xaml`에서 관리함.
- **등록 후 표시** — 저장된 PClient ID와 ‘이 PC에 저장됨’을 프로필 카드에 표시함. 인증 확인 여부는 별도 행에 표시하며 계정 변경·삭제 버튼은 카드 아래에 둠. 더미 모드에서만 저장 계정의 로그인 확인이 가능함. [1Password 계정 관리](https://support.1password.com/add-account/), [Bitwarden 데스크톱 계정 관리](https://bitwarden.com/help/getting-started-desktop/)
- **제목 표시줄과 아이콘** — WPF `WindowChrome`으로 드래그 영역을 두고 최소화·최대화·복원·닫기 버튼을 구성함. VectorCraft 원본 `src/NetAuth/Assets/netauth.vectorcraft`에서 내보낸 로고를 앱과 실행 파일에 적용함. [Microsoft WPF WindowChrome](https://learn.microsoft.com/en-us/dotnet/api/system.windows.shell.windowchrome)
- **저장 위치** — 운영용은 `%LOCALAPPDATA%\NetAuth\Account\account.dat`, 더미용은 `%LOCALAPPDATA%\NetAuth\Dummy\account.dat`임. 파일에는 Windows 사용자별 DPAPI 암호문을 보관함.
- **더미 검증** — 더미 로그인 창을 실행하고 더미 설정 창에 `demo-user`와 `demo-pass`를 저장한 뒤 **인증 확인**을 선택함. Debug 빌드 후 `tests/AccountSettings.Tests.ps1`로 동일 흐름을 검증할 수 있음.

## 4단계 · 실제 PClient 설치 PC 검증

- [ ] **실행 전제** — 학교의 자동 인증·계정 보관 허용 범위, PClient 버전·경로·프로세스명, 사용자 로그온 및 원격 접속 조건을 확인함.
- [ ] **읽기 전용 조사** — 일반 사용자 세션에서 실제 창 제목과 접근성 트리를 확인함. 로그아웃·인증 성공·실패 각각의 관찰 신호를 기록하고 더미와 다른 항목을 반영함. 성공 신호를 식별하기 어려우면 결과 판정을 미확인으로 유지함.
- [ ] **정상 인증** — 허용 범위 확인 후 실환경에서 TC-01, TC-02를 검증함. 실제 계정의 비밀번호와 화면 속 ID는 결과 기록에서 제외함.
- [ ] **재부팅과 세션 전환** — TC-08, TC-09, TC-12에 따라 로그온 전 대기, 바탕화면 진입 후 시작, 잠금·원격 세션 해제 및 복귀를 각각 확인함. 세션별 실행 여부와 인증 결과를 기록함.

### 실제 연동 전 확보할 UI 신호

- [x] 설치 PC의 Windows 대화형 세션에서 PID 없이 `PClientUI`를 찾고 로그아웃 신호를 재현함.
- [x] 로그인 창의 접근성 속성과 창 기준 좌표를 수집함. 첨부 화면의 상하 배치와 대조해 ID 입력란 후보는 `1024`(Y=363), 비밀번호 입력란 후보는 `1022`(Y=425), 로그인 버튼 후보는 `1029`(Y=485, 로그인 문구 일치)로 식별함.
- [x] 실제 `1024`와 `1022`가 네이티브 `Edit`이며 읽기 전용이 아님을 확인함. `1024`는 일반 입력란, `1022`는 마스킹 입력란으로 확인됨. 두 필드 모두 수동으로 한 글자를 입력·삭제할 때 길이 변화와 원래 길이 복구가 감지됨.
- [x] 실제 `1024`·`1022`에서 Win32 방식으로 한 글자 자동 입력·제거에 성공함. 두 필드가 빈 상태에서 가상 숫자 8자리를 각각 순서대로 입력·제거했으며, 원래 글자 수와 선택 범위 복구를 확인함.
- [x] 실제 ID 입력란 `1024`에서 시작 값이 비어 있거나 다른 ID인 경우 모두 입력값 전체를 등록 ID로 교체하고, 원래 ID와 선택 범위를 복구함.
- [x] ID 채우기 배포본으로 실제 PClient에 ID가 입력됨을 설치 PC 사용자가 확인함. PClient 버전은 미기록 상태임.
- [x] NetAuth의 계정 관리에 **PClient 계정 채우기**를 연결함. 같은 Windows 세션의 로그아웃 창에서 저장된 ID와 비밀번호 입력을 수행함.
- [x] 설치 PC 사용자가 배포본의 계정 채우기 버튼으로 실제 PClient 입력란이 채워짐을 보고함. 빈 ID·기존 ID 각각의 결과와 PClient 버전은 미기록 상태임.
- [x] 실제 PClient의 숫자 컨트롤 ID를 재현한 네이티브 검증 창에서 저장된 가상 계정을 입력하고 로그인 버튼 1회 호출 및 명시적인 결과 판정을 검증함.
- [x] 현재 Windows 사용자 전용 작업 스케줄러 로그온 작업을 등록하고 검증 창의 실행 지연, 중복 요청 및 재제출 없이 종료되는 조건을 확인함.
- [ ] 실제 설치 버전을 기록하고 로그인 버튼 제출 동작을 검증함. 관찰한 후보 3개는 UI Automation에서 `Pane`으로 노출됨. 입력란은 `ValuePattern`을, 버튼은 `InvokePattern`을 제공하지 않음.
- [x] 실제 PClient 5.16.0.93에서 직접 로그인 후 창을 다시 열어 상태 컨트롤 `1013`의 `[ID] 님으로 로그인 상태입니다.` 문구를 읽음. 창이 닫히기만 하면 결과를 `UnknownState`로 처리함.
- [ ] 관찰 가능한 오류와 추가 인증 상태를 확인함. 승인된 검증 범위에서 일반 사용자 권한, PClient 설치 버전 차이, 잠금·원격 세션에서의 UI 접근 여부를 확인함.

### 로그아웃 상태와 입력 컨트롤 조사

1. `tools/Inspect-PClient.ps1`을 PClient 설치 PC로 복사하고, PClient 로그인 창을 화면에 표시함.
2. PClient 창과 같은 Windows 데스크톱 세션에서 Windows PowerShell을 열고, 파일이 있는 폴더에서 아래 명령을 실행함. 현재 세션의 `PClientUI` 프로세스에서 PID를 자동으로 얻음.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inspect-PClient.ps1 -AsJson
```

- `LoginRequired` 및 `VisibleLogoutText`는 대상 창에서 로그아웃 문구가 읽혔음을 의미함. `ProcessName`, `StatusName`, `AutomationId`, `ControlType`을 기록함.
- `ControlCandidates`에서 `StatusWindowIndex`와 같은 `WindowIndex`를 우선 확인함. `InputCandidate`는 ID 입력란 후보, `PasswordCandidate`는 비밀번호 입력란 후보, `LoginButtonCandidate`는 로그인 버튼 후보임. `ButtonCandidate`, `LoginLabelCandidate`, `CustomCandidate`는 별도 확인이 필요한 요소임.
- 각 후보는 `AutomationId`, `ControlType`, `ClassName`, 입력란 마스킹 여부, 조작 가능 상태, 지원 패턴과 창 기준 좌표를 제공함. `ScanInterrupted`가 참이면 창이 조사 중 바뀐 경우로, 로그아웃 화면을 다시 표시한 후 재실행함.
- `UnknownState` 및 `LogoutTextNotExposed`는 예상 문구를 가진 화면 요소가 확인되지 않았음을 의미함. 이 경우 Live Inspect로 문구가 노출되는 위치나 실제 속성을 조사함.
- `PClientUiNotInSession`이면 PClient 창을 연 데스크톱에서 다시 실행함. `MultiplePClientUiProcesses` 또는 프로세스명 변경으로 자동 선택을 할 수 없으면 작업 관리자에서 창의 PID를 찾아 `-ProcessId <PID>`로 지정함. `WindowNotFound`이면 창을 표시한 후 다시 실행함.
- 진단은 상태 문구와 컨트롤 속성을 읽기 전용으로 조사함. 입력란 값과 일반 접근성 이름은 출력하지 않으며, 로그아웃 상태에서 계정 입력 없이 실행할 수 있음.

### 입력란 역할과 입력 동작 확인

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inspect-PClient.ps1 -CheckInput -AsJson
```

- PClient 로그아웃 창과 PowerShell 창을 나란히 표시함. 비밀번호란은 빈 상태에서 시작함.
- 스크립트가 순서대로 안내하면 오른쪽 방향키로 커서를 해당 입력란 끝까지 옮긴 뒤 숫자 `0`을 한 글자 추가함. 감지 안내 후 `Backspace`로 추가한 글자를 지움. ID 입력란이 가득 찬 경우 원래 글자를 알고 있을 때만 마지막 한 글자를 지운 뒤 안내에 따라 복원함. `Enter`와 로그인 버튼은 사용하지 않음.
- `InputCheck.Fields`에서 `IsNativeEdit`, `IsMasked`, `IsReadOnly`, `InputObserved`, `OriginalLengthRestored`를 확인함. 스크립트는 입력이나 버튼 클릭을 직접 수행하지 않고 입력 전후의 길이만 내부에서 비교함. 필드값과 길이는 출력하지 않음.

### 로그인 제출 없는 자동 입력 진단

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inspect-PClient.ps1 -CheckAutoInput -AsJson
```

- 로그인 창에서 자동 로그인 체크가 해제됐는지 확인하고 비밀번호란을 비운 상태에서 실행함. 실행 중에는 창을 조작하지 않음.
- 로그아웃 요소 `1013`과 대상 프로세스에 속한 네이티브 입력란을 확인함. `1024`와 `1022`에 순서대로 숫자 `0`을 한 글자 추가하고 해당 문자만 제거함. 입력값은 읽지 않으며 로그인 버튼이나 키 입력을 호출하지 않음.
- `InputObserved`, `OriginalLengthRestored`, `OriginalSelectionRestored`가 모두 참이면 삽입과 원래 길이·선택 범위 복구가 확인됨. `InputLimitReached`이면 기존 입력을 보존하고 해당 필드 검사를 건너뜀.
- `RestorationNotVerified`이면 다음 필드로 진행하지 않거나 스크립트를 종료함. 해당 필드에 테스트 문자가 남았는지 화면에서 확인함.

### 전체 입력 미리보기

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inspect-PClient.ps1 -PreviewInput -AsJson
```

- 자동 로그인 체크가 해제된 로그아웃 화면에서 ID와 비밀번호를 모두 비운 뒤 실행함. 실행 중에는 PClient 창을 조작하지 않음.
- ID의 가상 숫자 8자리를 5초간 표시한 후 지움. 이어 비밀번호란에서 가상 숫자 8자리를 5초간 표시한 후 지움. 로그인 버튼과 Enter는 사용하지 않음.
- `InputCheck.Fields`에서 두 입력란의 `InputObservedAndRestored`를 확인함. 기존 입력이 남아 있으면 미리보기를 시작하지 않음.

### 등록 ID 전체 교체 확인

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inspect-PClient.ps1 -CheckIdReplacement -AsJson
```

- PClient 로그아웃 창에서 자동 로그인 체크를 해제하고 비밀번호란을 비움. ID는 현재 상태 그대로 둠.
- PowerShell이 입력을 요청하면 NetAuth에 등록한 ID를 입력함. 진단은 빈 칸과 다른 가상 ID가 입력된 칸을 각각 준비하고, 두 경우 모두 입력란 전체가 등록 ID와 정확히 일치하는지 확인함.
- 진단 결과는 `InputCheck`의 `EmptyIdMatched`, `PrefilledIdMatched`, `OriginalIdRestored`, `OriginalSelectionRestored`로 확인함. 원래 ID와 등록 ID는 출력하지 않으며, 비밀번호 입력과 로그인 제출을 수행하지 않음.
- `BothCasesMatchedAndRestored`이면 두 케이스와 복구에 성공함. `RestorationNotVerified`이면 입력란의 값을 화면에서 확인함.
- 진단이 마지막으로 확인한 ID와 현재 값이 다르면 추가 입력과 복구를 중단하고 현재 입력을 보존함.

### NetAuth의 PClient 계정 채우기

- 같은 Windows 세션에서 실행 중인 `PClientUI.exe`를 자동 탐지함. 왼쪽 배지에 **PClient 로그인됨**, **PClient 로그아웃됨**, **PClient 확인 중**, **PClient 상태 미확인** 또는 **다른 계정 로그인됨**을 표시함. 오른쪽의 **최근 인증 결과**는 마지막 로그인 시도의 결과를 유지함.
- NetAuth 실행 중 로그인과 로그아웃 전환이 확인되면 주 화면 오른쪽 아래에 NetAuth 알림 카드를 표시함. 새 상태가 확인되면 이전 카드를 교체하며, 계정 정보는 제외함. 알림 본문을 누르면 계정 설정을 열고, 닫기 버튼을 누르거나 10초가 지나면 카드를 닫음. Windows 알림 센터에는 기록되지 않음.
- 기존에 등록한 실행 파일의 경로·해시가 같거나, Windows가 `NetMan Co., Ltd.` 게시자의 서명을 유효하다고 확인하면 연결됨을 표시함. 후보가 여러 개이거나 검증에 실패하면 연결되지 않음으로 표시함. [Microsoft Authenticode 서명 확인](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature)
- Debug 빌드에서 자동 로그인 체크를 해제하고 PClient 비밀번호란을 비운 다음 **계정 관리 → PClient 계정 채우기**를 선택함. 입력 직전에 실행 파일과 로그아웃 상태를 다시 확인함.
- ID가 빈 경우와 다른 값이 들어 있는 경우 각각 등록한 ID와 비밀번호 마스킹 표시를 확인함. 테스트 사이에는 비밀번호란을 다시 비움. PClient의 로그아웃 표시가 유지되는지 확인함.
- 앱은 표시된 상태 컨트롤 `1013`이 하나이고 로그아웃으로 확인될 때만 ID `1024`와 마스킹된 비밀번호 `1022`를 입력함. ID 입력 후 상태가 모호해지면 비밀번호 입력을 중단하고 ID 복구를 시도함. ID는 전체 일치로, 비밀번호는 원문을 읽지 않고 마스킹과 길이로 확인함. 로그인 버튼과 Enter 호출은 없음.
- 입력 직전에 비밀번호란이 채워지면 입력을 중단함. 쓰기와 겹친 입력의 출처를 확인할 수 없으면 비밀번호란을 지우지 않고 사용자 확인을 요청함.
- `tests/PClientAccountFill.Tests.ps1`은 PClient와 운영용 저장 계정이 없는 개발 환경에서 실행함. 별도 EXE 검증 시 `-NetAuthPath`로 배포본을 지정함.

### 실제 PClient의 수동 로그인 전후 상태 확인

- `tools/Watch-PClientLogin.ps1`을 PClient 설치 PC에 복사함. PClient 로그아웃 창에서 계정을 채운 뒤, 같은 Windows 세션의 PowerShell에서 아래 명령을 실행함.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Watch-PClientLogin.ps1
```

- 로그아웃 확인 안내가 나오면 30초 안에 PClient의 **로그인** 버튼을 직접 한 번 누름. 창이 트레이로 들어가면 남은 관찰 시간에 트레이의 PClient 아이콘으로 상태 창을 다시 열 수 있음. 관찰 시간은 `-WaitSeconds 60` 등으로 변경 가능함.
- JSON의 `Before`, `After`, `Changes`에 상태 컨트롤 `1013`의 전후 상태와 변화 시점이 기록됨. `SuccessTextObserved`는 명시적인 성공 문구가 관찰된 경우임. 성공 문구 없이 창이 사라지면 `UnknownState`로 기록함.
- 이미 로그인한 상태에서 PClient 창을 다시 열고 같은 명령 끝에 `-CurrentState`를 붙이면 로그인 재시도 없이 `Current` 스냅샷을 출력함. 상태 컨트롤 `1013`이 없으면 같은 프로세스에서 표시 중인 텍스트 컨트롤의 로그인 문구를 확인함. 계정 번호가 포함된 문구는 `[ID] 님으로 로그인 상태입니다.`로 가려서 출력함.
- 진단에서 로그인 버튼·입력란을 조작하지 않음. 공유용 JSON에는 ID·비밀번호 입력값과 미등록 상태 문구 원문을 포함하지 않음.

### NetAuth에서 PClient 로그인 및 결과 확인

- 같은 Windows 세션에서 PClient 로그아웃 창을 열고 비밀번호란을 비운 상태로 NetAuth의 **PClient 로그인**을 선택함. 확인된 프로세스의 창에서 네이티브 버튼 `1029`를 식별함. `5.16.0.93`은 실제 확인한 버튼 ID를 사용하며, 다른 버전은 네이티브 문구도 확인함. 저장된 계정을 입력한 뒤 같은 버튼이 활성화됐을 때 한 번 호출함.
- 창이 사라지면 검증한 `PClientUI.exe`를 추가 로그인 요청 없이 상태 확인용으로 한 번 실행함. 제출 이후 최대 12초 동안 상태 컨트롤 `1013`에서 등록 ID와 일치하는 로그인 문구를 확인함. 일치하면 **인증 확인됨**, 다른 계정이나 확인할 수 없는 상태는 **미확인**으로 표시함.
- 실제 PClient 5.16.0.93에서 **PClient 로그인**을 바로 선택하면 로그인까지 진행된다는 사용자 보고가 있음. 상태 창의 자동 재열기와 NetAuth의 **인증 확인됨** 표시 여부는 미기록임. 공개 전산망 안내는 일반 로그인 절차를 설명하며, 별도 앱을 통한 자동 인증·계정 보관의 허용 범위는 명시하지 않음. [창원대학교 정보전산원 전산망 안내](https://www.changwon.ac.kr/ccenter/cm/cntnts/cntntsView.do?cntntsId=4899&mi=13106)

- 로그인 버튼 식별 오류가 반복되면 해당 상태의 PClient 창을 유지한 채 `Inspect-PClient.ps1 -CheckLoginButton -AsJson`을 실행함. `LoginButtonCheck`에 네이티브 버튼 ID·클래스, 문구 일치 여부, 활성 여부 및 접근성 후보를 표시함. 버튼 문구 원문과 입력란 값은 공유 출력에서 제외함.

### 네이티브 검증 창에서 로그인 결과 확인

- 배포 폴더는 `artifacts/pclient-login-preview-win-x64`임. `NetAuth.PClientPreview.exe`를 열고 같은 폴더에서 `.\NetAuth.exe --settings-pclient-preview`를 실행함.
- 검증 모드에서 가상 ID `demo-user`와 가상 비밀번호 `demo-pass`를 저장한 뒤 **로그인 검증**을 선택함. 검증 창에는 제출 횟수가 표시되고, NetAuth에는 상태가 **인증 확인됨**으로 표시됨.
- NetAuth는 실환경과 동일한 네이티브 입력 경로로 ID `1024`와 비밀번호 `1022`를 채움. 확인한 로그인 버튼 `1029`를 한 번 호출하고 상태 `1013`의 명시적인 성공 또는 거부 문구를 최대 8초 동안 확인함. 창 종료나 무응답은 **미확인**으로 처리함.
- 검증 모드는 `NetAuth.PClientPreview` 프로세스와 테스트 계정 저장소를 사용함. Debug 빌드의 **PClient 계정 채우기**는 입력만 수행하며, 제출과 결과 확인은 **PClient 로그인**에서 수행함.

### 작업 스케줄러에서 자동 실행 검증

- 배포 폴더는 `artifacts/pclient-logon-settings-win-x64`임. 같은 폴더에서 `.\NetAuth.exe --settings-pclient-preview`로 가상 계정 `demo-user`와 `demo-pass`를 저장함.
- **계정 관리 → 자동 로그인**을 켜면 현재 Windows 사용자의 로그온 작업을 등록함. 작업은 대화형 세션에서 일반 사용자 권한으로 실행되며 실행 중 중복 요청은 무시함. 작업 인수에는 계정 정보를 저장하지 않음.
- 즉시 재현하려면 다음 명령을 사용한 뒤 30초 안에 `NetAuth.PClientPreview.exe`를 실행함. 검증 창의 제출 횟수가 1회로 증가하면 결과를 확인함.

```powershell
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Start-ScheduledTask -TaskPath '\' -TaskName "NetAuth PClient Preview Logon - $sid"
```

- NetAuth는 검증 창이 늦게 열리는 경우 최대 30초 동안 기다림. 인증된 상태는 제출 없이 종료하며, 한 번 제출한 뒤 거부되거나 결과를 읽지 못하면 종료함.
- 작업 스케줄러의 마지막 실행 결과는 `0`(인증 확인 또는 이미 인증됨), `3`(가상 계정 미등록), `4`(검증 창 대기 시간 초과), `5`(인증 미확인 또는 제출 전 중단), `6`(계정 저장소 읽기 실패)으로 표시됨.
- 설정에서 **자동 로그인**을 끄거나 저장 계정을 삭제하면 현재 NetAuth 실행 파일을 가리키는 검증 작업을 중지하고 등록을 해제함. 다른 위치에서 등록한 작업은 해당 위치에서 관리할 수 있음. 작업 해제가 실패해도 저장 계정은 삭제하며 해제 실패를 표시함. 기존 수동 등록은 `tools/Register-PClientPreviewStartup.ps1 -Remove`로도 해제할 수 있음. 운영 모드의 자동 로그인 설정은 실제 PClient의 로그인 결과를 확인한 뒤 활성화할 예정임.
- 2026-11-22 Windows x64 단일 배포본에서 설정 켜기·재열기·끄기, 늦게 열린 검증 창에 1회 제출(TC-03·TC-07), 기존 인증 시 추가 제출 없음(TC-02), 거부 후 종료(TC-04), 대기 중 등록 해제 및 작업 중지를 검증함. Windows 재로그온(TC-08)과 실제 PClient 연동은 별도 검증이 필요함.

### Windows 시작과 사용 중 PClient 자동 로그인

- NetAuth에서 계정을 저장하고 **자동 로그인**을 켜면 현재 Windows 사용자 시작 항목에 `--start-in-tray --auto-login` 실행을 등록함. 수동 계정 채우기와 로그인 버튼은 Debug 빌드에서 자동 로그인을 끈 경우에만 표시함. 자동 로그인을 해제하거나 등록 계정을 삭제하면 현재 실행 경로의 자동 로그인 항목을 정리함.
- 자동 로그인이 켜져 있으면 NetAuth 시작 시와 트레이 상주 중 5초마다 같은 Windows 세션의 PClient를 확인함. 검증된 PClient 창에서 로그아웃이 확인된 경우에만 한 번 로그인함. 이미 인증됐거나 대상·상태가 모호하면 제출을 건너뜀.
- 자동 로그인은 로그아웃 확인 후 약 4초 대기하고 상태를 다시 확인한 뒤 한 번 제출함. 성공 직후에는 기존 15초 보호 간격도 적용함. 같은 로그아웃에서 결과가 미확인되면 등록 계정 인증 또는 계정·설정 변경이 확인될 때까지 재제출을 중단함.

### 설치 PC 테스트

- v0.0.9 설치본은 `artifacts/nsis/NetAuth-Setup-0.0.9-win-x64.exe`임. 기존 설치 위에 업데이트할 때 계정과 시작 옵션을 보존함. 제거하면 현재 Windows 사용자의 저장 계정과 시작 항목을 삭제함. 창을 닫으면 트레이에 유지되며, 설치 경로가 같은 NetAuth를 다시 열면 기존 창을 표시함.
- 설치 마법사의 Windows 시작 옵션만 선택하면 트레이에서 시작함. NetAuth에서 **자동 로그인**을 켜면 Windows 시작 등록과 PClient 자동 로그인이 함께 설정됨. 실제 PC 재부팅 검증은 대기 상태임(TC-03·TC-08 관련).

### 초기 실행 파일 배포 기록

- 초기 계정 채우기 검증에 사용한 Windows x64 단일 배포본은 `artifacts/account-fill-win-x64/NetAuth.exe`임.
- `artifacts/NetAuth-win-x64.zip`을 Windows x64 설치 PC에서 모두 압축 해제함. 생성된 `publish-win-x64` 폴더에서 `NetAuth.exe`를 실행함.
- `publish-win-x64`는 .NET Desktop Runtime을 포함하는 배포 폴더임. 빌드는 `dotnet publish src/NetAuth -c Release -r win-x64 --self-contained true -o artifacts/publish-win-x64`로 수행함.
- 기존 `artifacts/publish` 배포 폴더는 설치 PC의 .NET 10 Desktop Runtime을 사용함.
- 설치 PC에서 `0x800711C7`로 `NetAuth.dll`이 차단됨. 이벤트 3077의 정책 ID `{0283ac0f-fff1-49ae-ada1-8a933130cad6}`는 Windows 11 Smart App Control의 `VerifiedAndReputableDesktop` 기본 정책임. 현재 EXE와 DLL은 서명되지 않았으며, 해당 정책을 유지한 배포에는 신뢰된 코드 서명으로 바이너리를 서명하고 설치 PC에서 재검증해야 함. [Microsoft 기본 정책 목록](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/operations/inbox-wdac-policies), [Microsoft 코드 서명 안내](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control)

## 검증 기록

| 날짜 | 환경 | 항목 | 결과 및 근거 |
| --- | --- | --- | --- |
| 2026-11-21 | 개발 PC | 환경 준비 | 기존 검증에서 `Startup.Tests.ps1` 통과 및 Release 실행 확인. UI Automation 어셈블리 로드까지 확인됨 |
| 2026-11-21 | 개발 PC | 더미 창 및 읽기 전용 탐지 | Debug 빌드 경고·오류 0건, 시작 테스트 및 서식 검사 통과. Windows 대화형 세션에서 더미 상태 7개, 제출 횟수, 비밀번호 마스킹 속성, 체크박스 기본값 확인. 테스트 스크립트에서 제출을 수행하고 NetAuth는 상태를 조회함 |
| 2026-11-21 | 개발 PC | PID 기반 진단 | Windows PowerShell로 더미 창을 검사하여 로그아웃 문구가 노출되면 `LoginRequired`, 문구가 없으면 `UnknownState`가 반환됨을 확인함 |
| 2026-11-21 | PClient 설치 PC | 로그아웃 상태 조사 | 수동 PID 지정으로 `PClientUI`의 창 1개에서 `로그아웃 상태입니다.`를 읽어 `LoginRequired` 확인. 상태 요소는 `AutomationId=1013`, `ControlType.Pane`임. 별도 세션의 `SPAgent`를 지정하면 `DifferentSession` 반환됨 |
| 2026-11-21 | 개발 PC | 프로세스 자동 선택 | 더미를 `PClientUI.exe` 이름으로 실행해 PID 자동 선택 및 `LoginRequired` 확인. 기존 더미 시나리오 7개 통과 |
| 2026-11-21 | 개발 PC | 더미 로그인 통합 검증 | `--login-dummy` 추가 전 성공 경로 테스트 실패, 중복 실행 차단 추가 전 동시 실행 테스트 실패 확인. 최종 Debug 빌드 경고·오류 0건, 시작 테스트와 서식 검사 통과, 더미 통합 시나리오 9개 연속 2회 통과 |
| 2026-11-21 | 개발 PC | 계정 설정 UI 및 암호화 저장 | Windows에서 기본 첫 실행 화면 확인. 더미 설정 창으로 필수 입력, 취소, 마스킹, 암호화 파일, 저장·재실행, 계정 변경, 삭제 확인·취소, 저장 계정으로 제출 1회 및 인증 완료 검증. Debug 빌드 경고·오류 0건, 시작·서식 검사 및 기존 더미 시나리오 9개 통과 |
| 2026-11-21 | 개발 PC | 계정 UI 개편 및 NA 아이콘 | 가상 계정으로 등록 전후 화면과 인증 상태 구분 확인. 제목 표시줄의 드래그 영역과 최소화·최대화·복원·닫기 검증. Debug 빌드 경고·오류 0건, 서식·시작·계정 통합 테스트와 기존 더미 시나리오 9개 통과. Release 실행 파일의 NA 아이콘 추출 확인 |
| 2026-11-21 | 개발 PC | PClient 컨트롤 통합 진단 | 더미를 `PClientUI.exe`로 실행해 PID 없이 로그아웃 상태와 입력란·비밀번호란·로그인 버튼 후보의 JSON 출력 확인. 입력값 비노출과 진단 후 제출 0회 확인. 기존 통합 시나리오 9개 통과 |
| 2026-11-21 | PClient 설치 PC | 입력 컨트롤 관찰 | PID 없이 `PClientUI` 창 1개에서 `LoginRequired`, 상태 요소 `1013`, 조사 중단 없음 확인. 두 `Edit`의 Y 좌표와 화면 배치로 위쪽 ID `1024`, 아래쪽 비밀번호 `1022`로 추정함. `1029`가 로그인 버튼 후보로 출력됨 |
| 2026-11-21 | 개발 PC | Win32 입력란 검증 | 네이티브 `Edit` 필드 두 개를 가진 검증용 창에서 위쪽 일반 입력란과 아래쪽 마스킹 입력란을 구분함. 두 필드 모두 한 글자 추가와 원래 길이 복구를 감지함. 실제 PClient의 입력 동작은 미검증임 |
| 2026-11-21 | PClient 설치 PC | 실제 입력란 수동 검증 | `1024`의 `IsMasked=false`, `1022`의 `IsMasked=true` 확인. 두 항목의 `IsNativeEdit=true`, `IsReadOnly=false`, `InputObserved=true`, `OriginalLengthRestored=true` 확인. 로그인 버튼은 사용하지 않음 |
| 2026-11-21 | 개발 PC | 자동 입력 후 복구 | Win32 검증용 창에서 두 필드에 한 글자를 자동으로 추가·제거하고 ID 원문·빈 비밀번호·선택 범위 복구 확인. ID 길이 상한 및 비밀번호가 채워진 경우 입력 제어 확인 |
| 2026-11-21 | PClient 설치 PC | 실제 자동 입력 후 복구 | `1024`(ID)와 `1022`(비밀번호) 모두 `InputObservedAndRestored` 반환. 두 필드의 `InputObserved`, `OriginalLengthRestored`, `OriginalSelectionRestored`가 모두 참임. 로그인 제출은 수행하지 않음 |
| 2026-11-21 | 개발 PC | 전체 입력 미리보기 | Win32 검증용 창에서 가상 8자리 입력이 한 필드씩 표시되고 두 필드 모두 다시 비워짐을 확인함 |
| 2026-11-21 | PClient 설치 PC | 실제 전체 입력 미리보기 | `-PreviewInput` 실행에서 `1024`(ID)와 `1022`(비밀번호)가 모두 `InputObservedAndRestored`를 반환함. 원래 글자 수와 선택 범위 복구는 모두 참임. 로그인 제출은 수행하지 않음 |
| 2026-11-21 | 개발 PC | ID 전체 교체와 원문 복구 | 네이티브 검증용 창에서 빈 칸과 가상 ID가 채워진 칸을 8자리 ID로 교체함. 시작 시 빈 ID 및 기존 ID의 원문·선택 범위가 복구됨을 각각 확인함 |
| 2026-11-21 | PClient 설치 PC | 실제 ID 전체 교체 | `-CheckIdReplacement` 실행 결과 `BothCasesMatchedAndRestored` 확인. `EmptyIdMatched`, `PrefilledIdMatched`, `OriginalIdRestored`, `OriginalSelectionRestored`가 모두 참임. 비밀번호 입력과 로그인 제출을 수행하지 않음 |
| 2026-11-21 | 개발 PC | NetAuth 본체 ID 채우기 | 실제 NetAuth UI와 Windows 보호 저장소를 사용해 빈 ID·다른 ID 입력을 검증함. 인증됨 상태와 비밀번호 입력 상태에서는 ID를 보존함. 검증용 창에서 네 케이스 모두 비밀번호 변경 알림과 로그인 버튼 호출이 발생하지 않음 |
| 2026-11-21 | 개발 PC | NetAuth 계정 채우기 | Debug 및 단일 배포본에서 빈 ID와 다른 ID를 저장 ID로 교체하고 가상 비밀번호 전체 일치를 확인함. 인증 상태(TC-02) 및 비밀번호가 이미 입력된 경우 입력을 건너뜀. 부분 입력 실패 시 기존 ID와 빈 비밀번호 상태 복구를 확인함. 모든 케이스에서 로그인 버튼 호출 0회임. PClient는 개발용 검증 창으로 대체함 |
| 2026-11-21 | 개발 PC | 네이티브 로그인 검증 | Debug와 단일 배포본에서 입력 전용 5개 및 로그인 검증 6개 시나리오 통과. 가상 계정 일치 후 한 번 제출하고 성공·거부를 구분함(TC-01, TC-04). 버튼 누락 및 실제 프로세스명 격리에서 제출 0회, 시간 초과와 창 종료에서 미확인, 동시 요청에서 총 제출 1회 확인(TC-05, TC-07). 실제 PClient 버전과 로그인 후 상태는 별도 확인 필요 |
| 2026-11-21 | 개발 PC | 기존 WPF 더미 회귀 | 응답 지연 시나리오에서 중간 대기 상태 관찰 실패가 이전 계정 채우기 배포본에서도 재현됨. 네이티브 검증 창의 로그인 결과 및 무응답 시나리오는 모두 통과함 |
| 2026-11-22 | 개발 PC | 계정 수신자와 동시 입력 보호 | 등록 경로가 다르거나 등록 당시 해시와 다른 더미에 ID·비밀번호가 입력되지 않음을 확인함. 비밀번호 쓰기 전이나 쓰기와 겹쳐 들어온 가상 수동 입력을 보존함. 계정 채우기 9개와 네이티브 더미 로그인 6개 시나리오 통과함 |
| 2026-11-22 | 개발 PC | 계정 저장소·시작 작업·WPF 더미 회귀 | 잘못된 계정 레코드에서 오류 안내와 파일 보존을 확인함. 시작 작업 해제를 고의로 실패시켜도 가상 계정이 삭제됨. 제출 횟수로 동기화한 WPF 더미 테스트 9개가 통과했으며 로그인 대기 중 창 종료는 `UnknownState`로 반환됨 |
| 2026-11-22 | 개발 PC | ID 진단과 계정 상태 회귀 | 네이티브 더미에서 정상 진단의 원래 ID·선택 범위 복구와 쓰기 직전·복구 도중 들어온 ID 보존을 확인함(TC-05). 두 NetAuth 창에서 등록 경로 취소·삭제 반영을 확인함. 같은 잘못된 가상 계정에서 설정 오류 안내, 로그온 명령 종료 코드 `6`, 저장 파일 보존을 확인함. 실제 PClient 및 제출 동작은 해당 진단에서 사용하지 않음 |
| 2026-11-22 | 개발 PC | 실패 후 가상 시작 작업 정리 | 등록 후 테스트 실패를 유도함. 자체 시작 작업과 실행 중인 작업 프로세스를 정리하고 다른 실행 경로의 가상 작업은 보존함. Windows 재로그온은 수행하지 않음 |
| 2026-11-22 | 개발 PC | 단순화 후 회귀 검증 | Debug 빌드, 서식 검사, 시작·계정 설정·WPF 더미·네이티브 더미 테스트가 종료 코드 `0`으로 통과함. ID 진단 3개, 입력 전용 9개, 네이티브 더미 로그인 6개 및 가상 시작 작업 검증 포함 |
| 2026-11-22 | 개발 PC | 상태 판정 보강 | 네이티브 더미에 상태 표시가 두 개일 때 자격 증명 입력과 더미 제출을 중단함. ID 입력 도중 상태가 모호해지면 ID를 복구하고 비밀번호는 입력하지 않음. 숨겨진 상태 표시가 있을 때는 정상 입력함. 입력 전용 12개와 더미 로그인 7개를 검증함(TC-05·TC-07). 실제 PClient 버전·동작은 이번 검증 범위에서 제외함 |
| 2026-11-24 | 개발 PC | PClient 자동 탐지 및 연결 표시 | 네이티브 더미로 미실행·복수 실행·미서명 파일에서 연결되지 않음과 입력 차단을 확인함. 기존 경로·해시가 일치하면 창을 열 때 연결됨을 표시하고 확인 팝업 없이 가상 계정을 입력함. 입력 전용 12개 및 더미 로그인 7개 회귀를 확인함(TC-05·TC-07) |
| 2026-11-24 | PClient 설치 PC | 실제 계정 채우기 | 설치 PC 사용자가 NetAuth의 계정 채우기로 실제 PClient의 ID와 비밀번호가 입력됨을 확인함. PClient 버전, 최초 연결에 사용된 확인 방식, 입력 전 ID 상태는 미기록임. 로그인 제출과 인증 결과는 별도 검증 항목임 |
| 2026-11-24 | 개발 PC | 수동 로그인 전후 관찰 | 네이티브 검증 창에서 로그아웃 기준 캡처 후 명시적인 성공 문구를 감지함. 알 수 없는 문구를 공유 결과에서 제외하고 프로세스 종료 시 `UnknownState`를 반환함. 관찰 중 입력·제출 없음 확인(TC-01·TC-05 관련). 실제 PClient의 성공 신호는 확인 대기 상태임 |
| 2026-11-24 | PClient 설치 PC | 실제 PClient 5.16.0.93 수동 로그인 관찰 | 사용자 제공 결과에서 로그아웃 문구와 상태 컨트롤 `1013`(`ControlType.Pane`) 확인. 관찰 시작 4.471초에 같은 컨트롤이 `로그인`을 포함한 미등록 문구로 바뀌고 5.281초에 표시된 창이 0개가 됨. 결과는 `UnknownState`이며 로그인 성공 판정에 사용할 문구는 미확인임(TC-01 관련) |
| 2026-11-24 | PClient 설치 PC | PClient 5.16.0.93 로그인 상태 확인 | 로그인 후 다시 연 창에서 `-CurrentState`로 `1013`(`ControlType.Pane`)의 `[ID] 님으로 로그인 상태입니다.` 문구를 읽고 `SuccessTextObserved`를 반환함. 다시 연 창의 로그인 성공 신호 확인(TC-01·TC-02 관련). 닫힌 창에서 사용할 성공 신호는 미확인임 |
| 2026-11-24 | 개발 PC | 기본 모드 로그인 및 결과 확인 | 확인된 네이티브 더미로 저장된 가상 계정 제출 1회, 창 종료 후 재실행과 성공 문구 확인, 다른 계정에서 제출 0회, 무응답에서 재제출 0회를 확인함(TC-01·TC-02·TC-07 관련). Windows GUI 실행 파일 형식과 `dotnet run`의 시작 진단 출력 확인 |
| 2026-11-24 | PClient 설치 PC | PClient 5.16.0.93 버튼 식별 실패 | `preview.9`의 **PClient 로그인** 선택 시 로그인 버튼을 확인할 수 없다는 사용자 보고를 기록함. 당시 네이티브·접근성 버튼 속성은 미확인임(TC-01 관련) |
| 2026-11-24 | 개발 PC | 로그인 버튼 활성화 지연 | 버튼이 비밀번호 입력 전 비활성화된 더미에서 `preview.9`와 같은 오류를 재현함. `preview.10`에서 같은 창의 네이티브 버튼을 입력 전에 식별하고, 활성화 지연 뒤 1회 제출 및 인증 확인 성공. 끝까지 비활성화되는 경우 제출 0회 확인(TC-01·TC-05·TC-07 관련). 실제 PC 원인과 수정 결과는 확인 대기 상태임 |
| 2026-11-24 | PClient 설치 PC | 실제 버튼 문구 불일치 | `preview.10`에서 로그인 버튼 확인 오류가 반복됨. `Inspect-PClient.ps1`로 PClient 5.16.0.93의 네이티브 `Button` `1029`가 올바른 프로세스에 속하며 표시·활성 상태임을 확인함. 네이티브 문구 불일치로 이전 버전의 버튼 식별 단계에서 중단됨(TC-01·TC-05 관련) |
| 2026-11-24 | 개발 PC | 확인된 PClient 버전의 버튼 식별 수정 | 5.16.0.93으로 빌드한 더미에서 문구가 일치하지 않을 때 `preview.10` 오류를 재현함. 수정한 Debug 빌드에서 버튼 `1029`를 찾아 1회 제출하고 재열기 후 등록 계정 성공 문구를 확인함. 버튼이 중복되거나 끝까지 비활성화되는 경우 제출 0회 확인(TC-01·TC-05·TC-07 관련). 실제 PC 제출 결과는 확인 대기 상태임 |
| 2026-11-24 | PClient 설치 PC | 기본 모드에서 실제 로그인 진행 | `preview.11`의 **PClient 로그인** 선택으로 실제 PClient 로그인이 진행됐다는 사용자 보고를 기록함(TC-01 관련). **계정 채우기**를 먼저 실행하면 채워진 비밀번호란을 보호하는 기존 조건에 따라 다음 로그인 동작이 중단됨. NetAuth의 인증 결과 표시 여부는 미기록임 |
| 2026-11-24 | PClient 설치 PC | 실제 로그인 결과 확인 | 사용자가 실제 PClient 로그인과 결과 확인까지 검증됐다고 보고함(TC-01 관련). 실제 Windows 시작 시 자동 인증은 별도 검증 대상임 |
| 2026-11-24 | 개발 PC | 시작 옵션과 트레이 상주 | `preview.12` 설치 마법사에서 두 옵션의 기본 해제, 선택·해제, 업데이트 시 기존 선택 표시, 제거 후 시작 항목·바탕 화면 바로가기 정리를 확인함. Debug 빌드에서 트레이 시작, 닫기 시 창 숨김, 바로가기를 다시 눌러 같은 프로세스의 창을 복원하는 동작을 검증함. 실제 Windows 로그온·재부팅은 미실행임 |
| 2026-11-24 | 개발 PC | 기본 모드 Windows 시작 자동 로그인 | 자동 로그인 설정 켜기·끄기로 현재 경로의 시작 항목 등록·해제를 확인함. 시작 명령을 직접 실행해 늦게 열린 네이티브 더미 `5.16.0.93`에 중복 시작 요청을 포함해 제출 1회, 인증된 더미에 제출 0회 확인. 실제 Windows 로그온·재부팅 검증 대기 상태임(TC-02·TC-03·TC-07·TC-08 관련) |
| 2026-11-24 | 개발 PC | 트레이 상주 중 로그아웃 복구 | 네이티브 더미 `5.16.0.93`의 인증 상태를 확인한 뒤 NetAuth 창을 닫아 트레이에서 유지함. 사용 중 로그아웃 화면으로 바뀌면 1회 제출로 인증 복구 확인. 결과가 미확인되고 로그아웃 화면이 유지되면 이후 두 번의 감시 주기에서 추가 제출 없음 확인(TC-02·TC-07 관련). 실제 PClient의 숨겨진 창 상태와 실환경 복구는 검증 대기 상태임 |
| 2026-11-21 | 개발 PC | 작업 스케줄러 로그온 작업 | 사용자 로그온 트리거, 대화형 세션, 일반 권한 및 중복 실행 무시 설정을 확인함. 배포용 EXE를 스케줄러에서 즉시 실행하여 검증 창이 늦게 열려도 총 1회 제출(TC-03·TC-07), 이미 인증된 상태에서 추가 제출 없음(TC-02), 거부 직후 종료(TC-04)를 확인함. 임시 작업 등록 해제 완료. 실제 PClient 및 재부팅 후 로그온(TC-08) 검증 대기 상태임 |
| 2026-11-21 | 개발 PC | 런타임 포함 Windows x64 배포 | 런타임 위치를 빈 폴더로 지정했을 때 기존 배포본의 실행 실패를 재현함. 같은 조건에서 런타임 포함 배포본의 CLI와 실제 계정 설정 창 실행을 확인함. 설치 PC에서의 실행은 확인 대기 중임 |
| 2026-11-21 | PClient 설치 PC | Smart App Control 차단 | 런타임 포함 배포본의 `NetAuth.dll`이 `0x800711C7`로 차단됨. 이벤트 3077·3033과 정책 ID를 확인함. 개발 PC 배포본 EXE와 DLL은 `NotSigned`이며, 조사한 로컬 인증서 저장소에서 서명용 개인키를 찾지 못함 |
