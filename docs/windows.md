# Windows 연결 및 복원 가이드

[README로 돌아가기](../README.md) · [macOS 설정](macos.md)

## 1. iPhone과 PC 준비

1. iPhone에서 셀룰러 데이터가 되는지 확인하고 **설정 → 개인용 핫스팟 → 다른 사람의 연결 허용**을 켭니다.
2. Windows PC의 Wi-Fi에서 해당 핫스팟에 연결합니다. 일반 공유기의 같은 Wi-Fi에 연결하는 방식은 지원하지 않습니다. 앱은 활성 Personal Hotspot 브리지에서만 수신합니다.
3. iPhone의 Hotspot Proxy를 열고 **Start Proxy**를 누릅니다(기본값은 실행 시 자동 시작). 로컬 네트워크 권한을 허용합니다. 거절했다면 설정 → 개인정보 보호 및 보안 → 로컬 네트워크에서 확인합니다.
4. 앱의 Running 상태와 **현재 표시된 Server, Port**를 확인합니다. `172.20.10.1`과 `8080`은 기본 예시입니다. 앱에서 포트를 바꿨다면 바뀐 값을 입력하세요. 포트 변경은 프록시가 정지된 상태에서 합니다.

이 앱은 프록시 사용자 이름/비밀번호 인증을 지원하지 않습니다. 핫스팟 접속자를 신뢰할 수 있어야 합니다. HTTPS 연결용 인증서나 프로파일 설치는 필요하지 않습니다.

## 2. Windows 수동 HTTP 프록시

먼저 기존 수동 프록시, 자동 설정 스크립트(PAC), 자동 검색, 예외 목록을 기록합니다. 회사 정책으로 관리되는 설정은 관리자에게 확인하세요.

### Windows 11

1. **설정 → 네트워크 및 인터넷 → 프록시**를 엽니다.
2. **수동 프록시 설정 → 프록시 서버 사용 → 설정**(이미 설정됐다면 편집)을 선택합니다.
3. 사용을 켜고 **프록시 IP 주소**에 앱의 IP만, **포트**에 앱의 포트를 입력합니다. 주소에 `http://` 또는 `:8080`을 붙이지 않습니다.
4. 기존 자동 설정/PAC와 충돌하지 않는지 확인하고 저장합니다. 예외 목록과 로컬 주소 우회 옵션에 해당하는 요청은 프록시를 거치지 않습니다.
5. 시스템 프록시를 따르는 브라우저에서 HTTPS 페이지를 열어 봅니다.

### Windows 10

**설정 → 네트워크 및 인터넷 → 프록시 → 수동 프록시 설정**에서 **프록시 서버 사용**을 켭니다. **주소**와 **포트**에 각각 앱 표시값을 입력하고 저장합니다. Windows 11과 마찬가지로 기존 자동 설정 및 예외를 확인합니다. 화면 이름은 OS 언어/버전에 따라 다를 수 있습니다.

공식 설정 위치와 VPN별 설정은 [Microsoft 프록시 안내](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/use-a-proxy-server-in-windows)를 참고하세요.

## 3. HTTP, SOCKS5, 시스템 전체 트래픽의 차이

| 방식 | 설정 위치와 범위 |
|---|---|
| HTTP 프록시 | 위 Windows 설정. 이를 따르는 앱의 HTTP 요청 및 HTTPS CONNECT 터널에 사용합니다. HTTPS 대상 사이트의 TLS는 유지되며, 프록시 자체에 HTTPS로 접속하는 것은 아닙니다. |
| SOCKS5 | SOCKS5를 지원하는 앱의 자체 설정에 같은 서버/포트를 입력하고 인증을 끕니다. Windows의 위 수동 프록시 화면은 SOCKS5 설정 화면이 아닙니다. |
| 시스템 전체 경로 | 이 저장소에는 Windows TUN/VPN 설치·자동 복원 도구가 없습니다. Mac의 `mac/*.sh`는 Windows에서 사용하지 않습니다. |

Windows 프록시 설정은 모든 프로그램, 게임, UDP, DNS 또는 VPN 트래픽을 강제로 보내지 않습니다. 자체 네트워크 구현/프록시 설정/관리 정책을 쓰는 앱은 별도 설정이 필요합니다. WinHTTP 기반 서비스도 별도 설정을 가질 수 있습니다. 관리자 터미널의 전역 변경이나 `netsh winhttp import/reset`은 일반 연결 절차에 필요하지 않습니다. 읽기 전용 `netsh winhttp show proxy` 결과도 Windows 설정 화면과 같다고 가정하지 마세요. [Microsoft WinHTTP 명령 설명](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-winhttp).

SOCKS5 클라이언트에 원격 DNS 옵션이 있으면 켜야 호스트 이름을 프록시에 전달합니다. TCP 지원만으로 UDP 지원까지 의미하지 않습니다. UDP ASSOCIATE를 지원하는 클라이언트는 협상에서 반환된 **임시 UDP 포트**를 사용하고 TCP 제어 연결을 유지해야 합니다. UDP를 무조건 8080으로 보내면 동작하지 않습니다.

## 4. PowerShell에서 연결 확인

예시의 주소/포트를 앱 표시값으로 바꿉니다. 시스템 설정을 바꾸지 않는 명령별 검사이며 실제 요청은 example.com에 전송됩니다.

```powershell
$proxyAddress = '172.20.10.1'
$proxyPort = 8080
Test-NetConnection -ComputerName $proxyAddress -Port $proxyPort
curl.exe --connect-timeout 5 --max-time 20 --proxy "http://${proxyAddress}:$proxyPort" https://example.com/
curl.exe --connect-timeout 5 --max-time 20 --socks5-hostname "${proxyAddress}:$proxyPort" https://example.com/
```

`TcpTestSucceeded: True`는 TCP 포트 접근만 확인합니다. 첫 curl은 HTTPS CONNECT, 두 번째는 SOCKS5 TCP 및 프록시 측 이름 해석을 확인하며 UDP 검사가 아닙니다. `curl.exe`를 명시해 일부 PowerShell의 `curl` 별칭과 구별합니다. 실행 파일이 없으면 브라우저/지원 클라이언트로 검사하세요. 위 예시는 IPv4 기준입니다.

`NO_PROXY`/`no_proxy` 환경변수와 curl 설정 파일의 우회 규칙이 결과에 영향을 줄 수 있습니다. 명령별 프록시 성공이 다른 앱이나 Windows 전체 설정 성공을 의미하지 않습니다. 공인 IP가 같다는 사실만으로 프록시 사용을 판정할 수도 없습니다. [curl 공식 옵션 설명](https://curl.se/docs/manpage.html).

## 5. 해제 및 원래 설정 복원

핫스팟을 떠나거나 iPhone 앱을 종료하기 전에 같은 Windows 프록시 화면에서 **프록시 서버 사용**을 끄고 저장합니다. 기존 프록시가 있었다면 단순히 끄는 대신 기록한 원래 주소/포트, 자동 설정/PAC 및 예외를 복원합니다.

앱별 SOCKS 설정과 터미널의 프록시 환경변수는 별도로 되돌립니다. iPhone의 Stop 버튼은 PC 설정을 지우지 않습니다. 이 수동 설정은 PC DNS를 변경할 필요가 없으며, 해제할 때 네트워크 전체 초기화나 레지스트리 수정도 필요하지 않습니다.

## 6. 문제 해결

| 증상 | 확인 및 조치 |
|---|---|
| 앱이 Hotspot off/대기 중 | iPhone 핫스팟과 PC의 실제 Wi-Fi 연결을 확인하고 iPhone 앱을 다시 엽니다. 일반 Wi-Fi 주소로 대신 접속할 수 없습니다. |
| TCP 검사 실패/시간 초과 | 앱의 현재 주소·포트·Running 상태를 확인합니다. VPN/방화벽/관리 정책의 영향도 확인하되 전체 보호 기능을 무작정 끄지 마세요. |
| TCP는 되지만 curl 실패 | HTTP와 SOCKS 옵션을 구별하고 인증을 끕니다. 앱 오류 및 iPhone 셀룰러 인터넷을 확인합니다. |
| curl은 되지만 특정 앱만 실패 | 그 앱의 시스템 프록시 지원 및 자체 프록시/보안 DNS 설정을 확인합니다. Windows 설정을 무시하는 앱일 수 있습니다. |
| 인증 요구/HTTPS 인증서 오류 | 주소와 기존 PAC/프록시를 확인합니다. 이 앱에는 인증 정보가 없습니다. TLS 검증을 끄거나 임의 인증서를 설치하지 마세요. |
| 게임·UDP가 안 됨 | HTTP 프록시는 UDP를 처리하지 않습니다. SOCKS UDP ASSOCIATE를 실제로 지원하는 클라이언트가 필요합니다. |
| 다른 Wi-Fi로 바꾼 뒤 인터넷 불가 | 남아 있는 Windows/앱별 프록시를 위 절차대로 해제·복원합니다. |
| iPhone 화면 잠금/앱 종료 후 끊김 | 앱을 열어 Running인지 확인합니다. 무음 오디오가 iOS의 앱 중단/종료를 막는다는 보장은 없습니다. |
| 위젯은 Running인데 연결 실패 | 위젯은 최근 관측값입니다. 약 2분 후 Unverified 전환을 예약하지만 갱신은 iOS가 제어합니다. 앱 상태와 실제 요청으로 확인하세요. |

프록시는 통신사의 요금/테더링 분류, 익명성 또는 모든 앱의 연결을 보장하지 않습니다. 이 문서는 코드와 공식 OS 안내를 바탕으로 작성했으며, 실제 Windows PC와 iPhone 핫스팟 조합의 확인은 별도로 필요합니다.
