# macOS 연결 및 복원 가이드

[README로 돌아가기](../README.md) · [Windows 설정](windows.md)

## 1. iPhone과 Mac 준비

1. iPhone의 셀룰러 데이터 연결을 확인하고 **설정 → 개인용 핫스팟 → 다른 사람의 연결 허용**을 켭니다.
2. Mac에서 해당 핫스팟 Wi-Fi에 연결합니다. 일반 공유기의 같은 Wi-Fi에 연결하는 방식은 지원하지 않습니다. 앱은 활성 Personal Hotspot 브리지에만 수신합니다.
3. iPhone에서 Hotspot Proxy를 열고 **Start Proxy**를 누릅니다. 기본적으로 앱 실행 시 자동 시작합니다. 로컬 네트워크 권한을 요청하면 허용하고, 이전에 거절했다면 설정 → 개인정보 보호 및 보안 → 로컬 네트워크에서 확인합니다.
4. 앱이 실행 중인지 확인하고 **현재 표시된 Server와 Port**를 사용합니다. `172.20.10.1:8080`은 기본 예시이며, 수동 연결에서는 실제 값을 우선합니다. 포트 변경은 프록시를 정지한 상태에서 합니다.

서버 주소 칸에는 `http://`나 `:8080`을 붙이지 않고 IP만 입력합니다. 이 앱은 사용자 이름/비밀번호 인증을 지원하지 않습니다. 핫스팟에 접속한 기기를 신뢰할 수 있어야 합니다. HTTPS 사용을 위해 인증서나 구성 프로파일을 설치할 필요는 없습니다.

## 2. 연결 방식 선택

| 방식 | 적용 범위 | 주의점 |
|---|---|---|
| macOS HTTP + HTTPS 프록시 | 시스템 프록시를 따르는 앱의 웹 요청 | 모든 앱, UDP, DNS를 자동으로 처리하지 않습니다. |
| 앱별 SOCKS5 | SOCKS5 설정을 지원하는 앱 | TCP 연결과 UDP ASSOCIATE는 클라이언트 지원이 각각 필요합니다. |
| 선택 사항: Mac TUN 자동화 | 가상 네트워크 인터페이스로 포착하는 트래픽 | 관리자 권한과 sing-box가 필요하며 우회 경로와 제약이 있습니다. |

HTTP와 HTTPS(CONNECT), SOCKS5의 **TCP 접속 주소/포트**는 같습니다. HTTPS(CONNECT)는 대상 사이트의 TLS 연결을 터널링하며, 프록시 서버 자체에 TLS로 접속한다는 뜻은 아닙니다. SOCKS5 UDP는 협상 결과로 받은 별도 임시 UDP 포트를 사용하고 TCP 제어 연결도 유지해야 합니다.

## 3. macOS 수동 프록시 설정

먼저 해당 네트워크 서비스의 기존 프록시, 자동 구성(PAC), 우회 목록을 기록합니다. 회사 관리 설정은 임의로 덮어쓰지 마세요.

1. **Apple 메뉴 → 시스템 설정 → 네트워크**에서 핫스팟에 연결한 서비스(보통 Wi-Fi)를 선택합니다.
2. **세부사항 → 프록시**를 엽니다.
3. **웹 프록시(HTTP)** 및 **보안 웹 프록시(HTTPS)**를 켜고, 각각 앱의 현재 IP와 포트를 입력합니다. 인증은 켜지 않습니다.
4. 기존 PAC/자동 프록시와 충돌하지 않는지 확인하고 저장합니다. 우회 목록에 해당하는 요청은 프록시를 거치지 않습니다.
5. 브라우저에서 HTTPS 페이지를 열어 봅니다. 앱 자체 프록시 설정, VPN, 관리 정책이 있으면 별도로 확인합니다.

SOCKS를 사용하는 앱은 그 앱에서 SOCKS5 서버를 지정하세요. 시스템의 SOCKS 프록시는 이를 따르는 앱에만 적용되므로 HTTP/HTTPS/SOCKS를 모두 켜면 모든 트래픽이 처리된다고 가정하지 마세요. 원격 DNS 옵션을 지원하는 SOCKS 클라이언트는 해당 옵션을 사용해야 호스트 이름을 프록시로 전달합니다.

설정 위치 참고: [Apple의 Mac 프록시 설정 안내](https://support.apple.com/en-gb/guide/mac-help/mchlp2591/mac).

### 터미널에서 연결 확인

아래 IP/포트를 **앱 표시값으로 바꿔서** 실행합니다. 명령별 테스트이며 시스템 설정을 변경하지 않습니다. 실제 요청은 example.com에 전송됩니다.

```bash
proxy_ip='172.20.10.1'
proxy_port='8080'
nc -vz "$proxy_ip" "$proxy_port"
curl --connect-timeout 5 --max-time 20 --proxy "http://${proxy_ip}:${proxy_port}" https://example.com/
curl --connect-timeout 5 --max-time 20 --socks5-hostname "${proxy_ip}:${proxy_port}" https://example.com/
```

`nc` 성공은 TCP 포트 접근만 확인합니다. 첫 curl은 HTTPS CONNECT, 두 번째는 SOCKS5 TCP 및 프록시 측 이름 해석을 확인하며 UDP 테스트는 아닙니다. `NO_PROXY`/`no_proxy` 환경변수나 curl 설정 파일에 우회 규칙이 있으면 결과에 영향을 줍니다. 자세한 옵션은 [curl 공식 매뉴얼](https://curl.se/docs/manpage.html)을 참고하세요. 위 예시는 IPv4 기준입니다.

### 해제 및 원래 설정 복원

핫스팟을 떠나거나 앱을 종료하기 전에 같은 프록시 화면에서 이번에 켠 HTTP/HTTPS/SOCKS를 끄고, 기록한 기존 PAC·프록시·우회 설정을 복원합니다. 다른 앱에 입력한 SOCKS 설정과 터미널 환경변수는 별도로 해제합니다. 앱의 Stop 버튼은 Mac 설정을 지우지 않습니다. 수동 프록시 방식은 DNS를 변경할 필요가 없습니다.

## 4. 선택 사항: sing-box TUN 자동화

먼저 위 수동 연결이 동작하는지 확인하세요. TUN을 사용할 때는 이번에 추가한 수동 프록시를 해제하여 문제를 구분하기 쉽게 합니다. 이 기능은 **macOS 전용**이며 Windows 설치 스크립트는 없습니다.

### 현재 스크립트가 지원하는 조건

- Mac 인터페이스의 IPv4가 `172.20.10.x`, iPhone 프록시가 **`172.20.10.1:8080`**이어야 합니다. 앱의 사용자 지정 포트를 자동으로 읽지 않습니다.
- 해당 인터페이스에 연결된 네트워크 서비스 이름을 찾으므로 이름을 바꾼 서비스나 USB도 이 주소 조건을 만족하면 탐지 대상입니다. 실제 USB 연결은 별도 확인이 필요합니다.
- 기본 TUN은 `utun199`, DNS는 `172.19.0.2`입니다. 다른 VPN/TUN과 충돌할 수 있습니다.
- `100.64.0.0/10`, `fd7a:115c:a1e0::/48`, `10.0.0.0/8`, `192.168.0.0/16`, `169.254.0.0/16`은 TUN 경로에서 제외합니다. 라우팅 규칙도 사설 IP를 직접 연결합니다. **모든 시스템 트래픽을 보장하는 VPN이나 차단 장치가 아닙니다.**
- 기본 DNS 전략은 IPv4 전용이며 원격 DNS는 프록시를 통한 `1.1.1.1` TCP입니다. `.local`, `.lan`, `.ts.net`도 현재 설정에서 원격 DNS로 보내므로 사설 이름/MagicDNS 해석을 보장하지 않습니다. IPv6, VPN 및 별도 보안 DNS를 사용하는 앱도 별도 확인해야 합니다.

### 설치

Homebrew가 설치된 Mac에서 저장소를 내려받고 저장소 루트로 이동합니다. 이미 받은 저장소가 있으면 그 디렉터리를 사용하세요.

```bash
git clone https://github.com/Indosaram/hotspot-proxy.git
cd hotspot-proxy
brew install sing-box
sudo bash mac/install.sh
```

설치기는 sing-box 설정을 검사하고 파일을 `/usr/local/etc/hotspot-tun`, `/usr/local/bin`, `/Library/LaunchDaemons`에 복사합니다. Homebrew의 Apple Silicon 및 Intel 경로를 탐색합니다. 원본 파일 수정은 설치본에 자동 반영되지 않습니다. 사용자 지정 포트는 [config.json](../mac/config.json)의 outbound와 [hotspot-tun.sh](../mac/hotspot-tun.sh)의 `proxy_up` 포트를 함께 수정한 뒤 재설치해야 합니다. 다른 IP/서브넷은 탐지 코드도 변경해야 하므로 기본 자동화의 지원 범위 밖입니다.

감시기는 네트워크 설정 변경과 30초 주기로 확인합니다. 즉시 전환을 보장하지 않습니다. 프록시 TCP 응답뿐 아니라 sing-box 프로세스, TUN 인터페이스, TUN을 통한 DNS 질의까지 확인한 뒤 DNS를 바꿉니다. 변경 전에 서비스 이름과 원래 DNS 목록을 저장하고, 핫스팟 이탈/건강 검사 실패 시 복원합니다. 사용자가 나중에 변경한 DNS는 보존합니다. 복원에 실패하면 백업과 TUN을 유지하고 실패를 알리므로 재시도가 필요합니다.

### 상태 확인과 DNS 복구

다음은 읽기 전용 진단입니다. 서비스 이름은 `-listnetworkserviceorder` 결과의 실제 이름으로 바꾸세요.

```bash
sudo launchctl print system/com.indo.hotspot-tun.watch
sudo launchctl print system/com.indo.hotspot-tun.singbox
ifconfig utun199
networksetup -listnetworkserviceorder
networksetup -getdnsservers 'Wi-Fi'
sudo tail -n 80 /usr/local/var/hotspot-tun/sing-box.log
```

핫스팟 밖에서는 sing-box 작업이나 TUN이 없는 것이 정상일 수 있습니다. launchd 작업이 등록됐다는 것만으로 동작을 판정하지 마세요. DNS 복원 오류가 있으면 다음 백업을 확인합니다(활성화 전/복원 후에는 없을 수 있음).

```bash
sudo cat /usr/local/var/hotspot-tun/dns-state/service
sudo cat /usr/local/var/hotspot-tun/dns-state/servers
```

`servers`의 `Empty`는 원래 자동 DNS였다는 뜻입니다. 백업을 지우지 말고 실제 서비스가 존재하는지 확인한 뒤 제거 명령을 재시도하세요. 예전 설치가 백업 없이 `172.19.0.2`만 남겼다면 원래 DNS를 추정할 수 없습니다. 기록한 원래 DNS를 시스템 설정에서 먼저 복원해야 합니다. 무조건 자동 DNS로 초기화하지 마세요.

### 자동화 해제/제거

저장소 루트에서 실행합니다.

```bash
sudo bash mac/uninstall.sh
```

감시기를 내리고 DNS를 복원한 뒤 설치 파일을 제거합니다. 복원/잠금 오류가 나면 원인을 해결하고 재시도하세요. 복구 상태를 수동 삭제하지 마세요. 내부 스크립트의 `--stop`만 실행하면 감시기가 다음 주기에 다시 켤 수 있어 지속적인 해제 방법이 아닙니다. 제거는 Homebrew sing-box 패키지나 수동 OS 프록시 설정을 지우지 않습니다. 남아 있는 `/usr/local/var/hotspot-tun.lock`은 비활성 잠금 파일입니다.

### 고급 선택 사항: Tailscale CLI 전환

일반 프록시/TUN 사용에는 필요하지 않습니다. [install-tailscale.sh](../mac/install-tailscale.sh)는 실행 중인 Tailscale GUI/데몬을 종료하고 별도의 CLI launchd 서비스로 전환합니다. 기존 VPN 연결에 영향을 줍니다. Tailscale 바이너리는 따로 설치되어 있어야 하고, 현재 스크립트/래퍼는 `/opt/homebrew/bin`을 고정 사용하므로 Intel Homebrew 경로에는 그대로 적용할 수 없습니다.

TUN 설치 후 이 전환이 필요한 경우에만 저장소 루트에서 `sudo bash mac/install-tailscale.sh`를 실행하고 로그인 절차를 완료합니다. 래퍼가 설정하는 HTTP(S) 프록시는 제어/DERP HTTPS 연결용이며 Tailscale 데이터 전체가 iPhone 프록시를 지난다는 보장은 없습니다. 기본 IP/포트를 변경했다면 래퍼도 맞춰야 합니다. TUN 제거기는 이 선택적 CLI 서비스도 제거하며 GUI Tailscale을 자동 복구하지 않습니다.

## 5. 문제 해결

| 증상 | 확인 및 조치 |
|---|---|
| 앱에 Hotspot off/대기 표시 | 개인용 핫스팟과 Mac 연결을 확인하고 iPhone 앱을 다시 엽니다. 일반 Wi-Fi 주소는 대체 서버가 아닙니다. |
| TCP 연결 실패/시간 초과 | 현재 IP/포트, 앱 Running 상태, 같은 핫스팟인지 확인합니다. VPN/방화벽 정책도 확인합니다. |
| 인증 요구 또는 HTTPS 인증서 오류 | 프록시 인증은 끕니다. IP/포트와 기존 PAC를 확인합니다. 인증서 검증을 끄거나 임의 인증서를 설치하지 마세요. |
| 브라우저만 되고 특정 앱은 안 됨 | 그 앱의 시스템 프록시 지원 여부 및 자체 HTTP/SOCKS 설정을 확인합니다. |
| SOCKS TCP는 되지만 UDP는 안 됨 | 클라이언트의 UDP ASSOCIATE 지원, 반환된 임시 포트 사용, TCP 제어 연결 유지 여부를 확인합니다. |
| TUN 설치 뒤 이름 해석 실패 | 로그·실제 서비스 DNS·백업을 확인하고 위 복원 절차를 따릅니다. 사설 DNS와 VPN 경로는 별도 문제일 수 있습니다. |
| 잠금 오류 | 다른 설치/제거/감시 작업이 끝난 뒤 재시도합니다. 잠금 파일 삭제로 우회하지 마세요. |
| 앱 잠금/종료 후 연결 끊김 | 앱을 다시 열고 Running 상태를 확인합니다. 무음 오디오가 iOS의 종료/중단을 막는다는 보장은 없습니다. |
| 위젯에 Unverified 또는 예전 상태 | 위젯은 독립 연결 검사가 아닙니다. 약 2분간 새 관측이 없으면 Unverified로 바뀌도록 예약되지만 iOS가 갱신 시점을 결정합니다. 앱과 실제 요청으로 확인합니다. |

프록시는 통신사의 요금/테더링 분류, 모든 앱의 연결, 익명성을 보장하지 않습니다. 이 문서는 코드와 OS 공식 안내를 기반으로 합니다. 실제 iPhone 핫스팟, macOS DNS 전환 및 복구는 기기에서 검증해야 합니다.
