<img src="src/NetAuth/Assets/netauth.png" alt="NetAuth 로고" width="112">

# NetAuth

창원대학교 네트워크 접근제어용 PClient 로그인을 자동화하기 위해 개발 중인 Windows 프로그램입니다. 시작 프로그램에 등록해 두면 PC를 켜고 Windows에 로그인할 때 NetAuth가 실행되어 PClient에 자동 로그인하는 것이 목표입니다.

현재 버전은 계정 정보를 암호화해 저장하고 PClient 로그인 화면에 자동으로 입력합니다. 자동 로그인은 실제 PClient 환경에서 검증한 뒤 제공할 예정입니다.

## 메인 화면

![NetAuth 메인 화면의 계정 등록 페이지](docs/netauth-main.png)

## 설치

NetAuth 설치본은 64비트 Windows(x64)용이며 필요한 .NET 런타임을 포함합니다. 설치본으로 사용하는 경우 .NET SDK와 NSIS를 따로 설치할 필요가 없습니다.

소스 코드에서 설치본을 직접 만드는 방법은 [빌드 안내](docs/NSIS_DISTRIBUTION.md)를 참고하세요.

## 라이선스

NetAuth는 [MIT 라이선스](LICENSE)로 배포합니다.
