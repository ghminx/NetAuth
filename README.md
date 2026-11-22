<img src="src/NetAuth/Assets/netauth.png" alt="NetAuth 로고" width="112">

# NetAuth

창원대학교 PClient 로그인 화면에 저장한 계정 정보를 채워주는 Windows 프로그램입니다. ID와 비밀번호는 현재 Windows 사용자 계정에 암호화해 저장합니다.

최종 목표는 PC를 켜고 Windows에 로그인하면 NetAuth가 시작 프로그램으로 실행되어 PClient 로그인까지 자동으로 처리하는 것입니다. 이 기능은 실제 PClient에서 검증한 뒤 제공할 예정입니다.

## 설치와 사용

NetAuth는 64비트 Windows(x64)용입니다. 공개 설치 파일은 아직 배포 전입니다.

1. NetAuth에서 PClient ID, 비밀번호, 설치된 PClient 실행 파일을 등록합니다.
2. PClient 로그인 창을 연 뒤 NetAuth에서 **PClient 계정 채우기**를 누릅니다.
3. 입력 내용을 확인하고 PClient에서 **로그인**을 누릅니다.

## 메인 화면

![NetAuth 메인 화면의 계정 등록 페이지](docs/netauth-main.png)

## 라이선스

NetAuth는 [MIT 라이선스](LICENSE)로 배포합니다.
