<div align="center">
  <img src="src/NetAuth/Assets/netauth.png" width="112" alt="NetAuth 로고">
  <h1>NetAuth</h1>
  <p><strong>창원대학교 PClient 로그인 자동화</strong></p>
  <p>저장한 계정으로 캠퍼스 네트워크에 연결하는 과정을 줄이는 Windows 앱입니다.</p>
  <p><a href="#미리보기">화면 미리보기</a> · <a href="#지원-범위">지원 범위</a> · <a href="#license">License</a></p>
</div>

## 미리보기

<div align="center">
  <img src="docs/netauth-main.png" width="880" alt="NetAuth 계정 설정 화면">
</div>

## 지원 범위

**계정 자동 입력** · PClient가 로그아웃 상태일 때 저장한 ID와 비밀번호를 로그인 화면에 채웁니다. 계정 정보는 현재 Windows 사용자 범위에서 암호화해 보관합니다.

**자동 로그인 및 연결 복구** · 계정을 저장하고 **자동 로그인**을 켜면 Windows 로그인 후뿐 아니라 NetAuth가 트레이에서 실행되는 동안에도 PClient 상태를 확인합니다. 로그아웃이 확인되면 약 4초 뒤 상태를 다시 확인하고 로그인합니다. 실제 PC의 재부팅 및 사용 중 연결 복구는 검증 예정입니다.

**Windows x64** · [GitHub Releases](https://github.com/ghminx/NetAuth/releases)에서 검증용 설치본을 받을 수 있습니다.

## License

NetAuth is licensed under the [MIT License](LICENSE).
