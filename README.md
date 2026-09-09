# Velocity Bulletin Infrastructure

Velocity Bulletin의 AWS 인프라 설계와 운영 기준을 정의합니다. 현재는 설계 단계이며, 아래 리소스가 이미 배포되어 있다고 가정하지 않습니다.

백엔드 저장소:

- [Backend](https://github.com/m161awm2/velocity-bulletinBE)

## 목표

- 서울 리전(`ap-northeast-2`)의 2개 가용 영역에 운영 워크로드를 분산합니다.
- 프런트엔드, API, 사용자 업로드 파일의 origin을 외부에 직접 노출하지 않습니다.
- 사람은 AWS IAM Identity Center(SSO), CI/CD는 GitHub OIDC, 워크로드는 IAM Role로 인증합니다.
- 단일 AZ 장애 시 서비스를 계속 제공할 수 있어야 합니다.
- 월 AWS 비용은 Neon 비용과 세금을 제외하고 약 20만~25만 원을 초기 운영 범위로 봅니다.
- 불필요한 상시 관리 서버와 장기 Access Key를 만들지 않습니다.

## 아키텍처
![다이어그램이미지](./diagram.png)
### 요청 흐름

1. `app.example.com/*` 요청은 CloudFront의 private frontend S3 origin으로 전달됩니다.
2. `app.example.com/api/*` 요청은 캐시하지 않고 CloudFront VPC Origin을 통해 internal ALB로 전달됩니다.
3. ALB는 포트 `8080`의 Fargate Task로 요청을 분산합니다.
4. Fargate Task는 Neon의 pooled PostgreSQL endpoint에 각 AZ의 NAT Gateway를 통해 연결합니다.
5. 이미지는 API가 직접 받지 않습니다. API가 presigned URL을 발급하고 브라우저가 quarantine S3에 직접 업로드합니다.
6. 검증 Lambda가 정상 이미지인 경우에만 media S3로 복사하며, 사용자는 `media.example.com`을 통해 파일을 읽습니다.

## 네트워크

VPC는 `10.20.0.0/16` CIDR과 서울 리전의 2개 AZ를 사용합니다.

| Subnet | 수량 | 용도 |
| --- | ---: | --- |
| Public | AZ별 1개 | NAT Gateway 전용 |
| Private App | AZ별 1개 | internal ALB, Fargate Task, CloudFront VPC Origin ENI |
| Private Management | AZ A에 1개 | 필요할 때만 생성하는 break-glass EC2 |

각 Private App subnet의 기본 경로는 같은 AZ의 NAT Gateway를 가리킵니다. 이렇게 해야 AZ 간 데이터 처리 비용과 단일 NAT 장애 의존성을 피할 수 있습니다.

CloudFront VPC Origin 사용을 위해 VPC에는 Internet Gateway를 연결합니다. ALB와 Fargate에는 public IP를 할당하지 않으며 Internet Gateway에서 이 리소스로 직접 들어오는 경로도 만들지 않습니다.

### VPC Endpoint 정책

S3 Gateway Endpoint는 기본 적용합니다. 별도 시간당 요금 없이 S3와 ECR 이미지 레이어 트래픽이 NAT Gateway를 우회하게 할 수 있습니다.

다음 Interface Endpoint는 선택적으로 구성하며 초기 기본값은 비활성화합니다.

- `ecr.api`
- `ecr.dkr`
- `logs`
- `secretsmanager`
- `ssm`, `ssmmessages`: break-glass EC2 또는 ECS Exec 요구에 따라 사용

Interface Endpoint는 비용이 나가므로 NAT Gateway로 만족합니다.
Neon public endpoint는 AWS VPC Endpoint로 대체할 수 없습니다. Neon Private Networking을 도입하기 전까지 NAT Gateway가 필요합니다.

## CloudFront, Route 53 및 TLS

### 애플리케이션 배포

`app.example.com` CloudFront 배포에는 두 origin을 둡니다.

| Behavior | Origin | 허용 Method | Cache |
| --- | --- | --- | --- |
| Default `/*` | Private frontend S3 + OAC | GET, HEAD, OPTIONS | 활성화 |
| `/api/*` | Internal ALB VPC Origin | GET, HEAD, OPTIONS, POST, PUT, PATCH, DELETE | `CachingDisabled` |

API origin request policy는 모든 query string과 다음 header를 전달합니다.

- `Authorization`
- `Content-Type`
- `Origin`
- `Accept`
- `X-Request-ID`

인증된 API 응답은 절대로 캐시하지 않습니다. 특히 `Authorization`을 origin에 전달하면서 cache key에서 제외하고 캐시를 활성화하면 다른 사용자의 응답이 공유될 수 있습니다.

React SPA deep link는 default behavior에 연결한 CloudFront Function으로 필요한 경로만 `/index.html`로 rewrite합니다. 배포 전체에 403/404 custom error response를 적용하면 API의 정상적인 4xx 응답까지 HTML로 바뀔 수 있으므로 사용하지 않습니다.

### 미디어 배포

사용자 파일은 `media.example.com`의 별도 CloudFront 배포에서 제공합니다. media S3는 Block Public Access를 활성화하고 CloudFront OAC에만 `s3:GetObject`를 허용합니다. 사용자 콘텐츠를 애플리케이션 origin과 분리하여 업로드 파일이 앱의 인증 정보와 동일 origin에서 실행되지 않게 합니다.

Viewer 인증서는 ACM `us-east-1`에서 발급합니다. ALB origin에 HTTPS listener를 사용할 경우 origin 인증서는 `ap-northeast-2`에서 별도로 관리합니다. HTTP 요청은 HTTPS로 redirect합니다.

## WAF

CloudFront용 Web ACL은 `CLOUDFRONT` scope로 `us-east-1`에서 생성하여 `app.example.com` 배포에 연결합니다.

초기 규칙:

1. AWS Managed Amazon IP Reputation List: `BLOCK`
2. AWS Managed Known Bad Inputs: 최초 1~2주 `COUNT`, 검토 후 `BLOCK`
3. AWS Managed Common Rule Set: 최초 1~2주 `COUNT`, 검토 후 `BLOCK`
4. 전체 IP rate limit: 즉시 `BLOCK`
5. `/api/v1/auth/login`: 더 낮은 IP rate limit으로 즉시 `BLOCK`
6. `/api/v1/auth/register`: 더 낮은 IP rate limit으로 즉시 `BLOCK`
7. `/api/v1/uploads/presign`: 인증 사용자 남용을 제한하도록 즉시 `BLOCK`

Rate limit의 정확한 값은 정상 트래픽을 관찰한 뒤 확정합니다. WAF 로그에는 authorization token이나 민감한 request body가 남지 않도록 logging filter와 redacted field를 설정합니다.

Presigned PUT은 브라우저에서 S3로 직접 전송되므로 애플리케이션 CloudFront의 WAF를 통과하지 않습니다. 업로드 보호는 짧은 URL 만료 시간, 서명된 content type/size, S3 CORS, quarantine 검증 및 presign API rate limit으로 수행합니다.

## ALB와 ECS Fargate

### ALB

- Scheme: `internal`
- Target type: `ip`
- Target port: `8080`
- Health check: `/health/ready`
- Success code: `200`
- CloudFront VPC Origin을 유일한 외부 진입점으로 사용

Security Group 흐름:

```text
CloudFront VPC Origin managed SG
    └─> ALB SG: listener port
          └─> Task SG: TCP 8080
```

ALB SG는 CloudFront VPC Origin의 service-managed SG에서 오는 요청만 허용합니다. Task SG는 ALB SG에서 오는 TCP 8080만 허용합니다.

### ECS Service

초기 설정:

```text
Launch type       ECS Fargate
Architecture      Linux/ARM64
CPU               256 units (0.25 vCPU)
Memory            512 MiB
Desired count     2
Min/Max capacity  2/4
Network mode      awsvpc
Public IP         disabled
Container port    8080
```

ECS는 두 Private App subnet에 Task를 분산합니다. Auto Scaling은 CPU 60%, memory 70%를 초기 target으로 사용하되 실제 부하 테스트 결과로 조정합니다.

- Deployment circuit breaker와 automatic rollback을 활성화합니다.
- `minimumHealthyPercent=100`, `maximumPercent=200`으로 무중단 rolling deployment를 구성합니다.
- SIGTERM 이후 애플리케이션의 10초 graceful shutdown보다 긴 stop timeout과 target deregistration 시간을 둡니다.
- 최대 Task 4개와 Task당 기본 DB connection 10개를 기준으로 Neon pooled connection을 최소 40개 이상 수용할 수 있는지 확인합니다.

## IAM과 Secret

역할은 공유하지 않고 목적별로 나눕니다.

| IAM 주체 | 권한 |
| --- | --- |
| Task Execution Role | ECR pull, CloudWatch Logs, Task Definition의 Secrets Manager 참조, 필요한 KMS decrypt |
| Application Task Role | quarantine bucket의 지정 prefix에 대한 `s3:PutObject` |
| Migration Task Role | migration secret 읽기와 ECS Task 실행에 필요한 최소 권한 |
| Validator Lambda Role | quarantine read/delete, media bucket write, 검증 로그 작성 |
| GitHub Deploy Role | ECR push, ECS 배포, migration task 실행; 승인 후 사용 |
| Break-glass EC2 Role | SSM과 승인된 진단용 read 권한만 허용 |

Backend가 환경변수로 Secret을 읽으므로 Task Definition에서 Secrets Manager 값을 주입합니다. 이 접근은 Application Task Role이 아니라 Task Execution Role 권한입니다.

권장 Secret 분리:

- App runtime: Neon pooled `DATABASE_URL`, `JWT_SECRET`
- Migration: Neon direct `MIGRATION_DATABASE_URL`
- Initial seed: `ADMIN_EMAIL`, `ADMIN_PASSWORD`; 시드 완료 후 접근과 보존 정책 검토

정적 설정인 `AWS_REGION`, `S3_BUCKET`, `S3_PUBLIC_BASE_URL`, `CORS_ORIGINS`는 일반 Task Definition environment로 관리합니다. 소스나 GitHub repository variable에 Secret 평문을 저장하지 않습니다.

## ECR

ECR는 Private Repository로 생성합니다.

- Tag immutability 활성화
- 기본 또는 enhanced image scanning 활성화
- 오래된 untagged 및 미사용 이미지 lifecycle 적용
- 배포 태그는 `latest`가 아니라 Git commit SHA 사용
- GitHub Actions만 운영 이미지 push 허용
- 개발자는 SSO Permission Set으로 기본 pull만 허용
- Fargate는 Task Execution Role로 pull

개발자 SSO와 GitHub-hosted runner가 ECR public service endpoint를 사용할 수 있어야 하므로 repository 전체에 `aws:SourceVpce`를 강제하지 않습니다. Fargate 경로만 VPC Endpoint로 제한할 때는 별도 역할 조건과 endpoint policy를 사용합니다.

## 사용자 이미지 처리

현재 Backend는 `posts/<uuid>.<ext>`에 대한 presigned PUT URL과 즉시 사용할 public URL을 반환합니다. 이 방식은 사용자가 선언한 MIME type을 검사하지만 파일 내용 자체를 검증하지 않습니다.

운영 배포 전 다음 흐름으로 변경합니다.

```text
Browser
  └─> quarantine/<upload-id> 로 presigned PUT
        └─> S3 ObjectCreated event
              └─> Validator Lambda
                    ├─ 파일 크기 재확인
                    ├─ JPEG/PNG/WebP 실제 decode
                    ├─ 메타데이터 제거 및 안전한 재인코딩
                    ├─ media/posts/<uuid>.<ext> 생성
                    └─ quarantine 원본 삭제
```

검증 실패 객체와 완료되지 않은 업로드는 lifecycle policy로 자동 삭제합니다. 애플리케이션은 검증 완료 전 이미지를 게시글에 확정하지 않도록 upload 상태 확인 API 또는 완료 단계를 추가해야 합니다.

S3 CORS는 `app.example.com` origin, `PUT`, 필요한 request header만 허용합니다. 업로드 최대 크기는 현재 애플리케이션과 동일하게 5 MiB로 유지합니다.

## Database

- App Task는 Neon pooled URL을 사용합니다.
- Migration Task만 Neon direct URL을 사용합니다.
- 모든 운영 연결에 TLS를 강제하고 `sslmode=require` 이상을 사용합니다.
- 가능하면 Neon IP allowlist에 NAT Gateway A/B의 Elastic IP만 등록합니다.
- 각 Task는 같은 AZ의 NAT Gateway를 통해 Neon에 연결합니다.
- RTO 목표는 1시간이며 RPO는 사용 중인 Neon 플랜의 PITR 보존 범위를 따릅니다.
- Neon Private Networking 비용과 NAT 비용을 주기적으로 비교하고 전환 여부를 검토합니다.

## 관측성과 보안 운영

- Backend JSON stdout을 CloudWatch Logs로 전송
- 애플리케이션 로그 30일 보존
- ALB access log와 CloudFront log는 전용 S3 log bucket에 저장하고 lifecycle 적용
- CloudWatch Alarm: ALB 5xx, target unhealthy, ECS CPU/memory, Task count, deployment failure
- WAF blocked/count 지표와 로그인/presign rate rule 알람
- CloudTrail management events를 보존하고 log bucket 변경을 제한
- GuardDuty와 IAM Access Analyzer 활성화
- Security Hub와 AWS Config는 예상 비용을 측정한 후 필요한 control부터 도입
- AWS Budgets와 Cost Anomaly Detection 알림 설정

모든 리소스에 최소한 다음 태그를 적용합니다.

```text
Project=velocity-bulletin
Service=network|frontend|backend|security|observability
Owner=<team-or-owner>
```

## CI/CD

### Backend

1. `go test ./...`
2. `linux/arm64` 이미지 build
3. 이미지 취약점 검사
4. Git SHA tag로 ECR push
5. 동일 이미지로 migration one-off ECS Task 실행
6. migration 성공 후 ECS Service 배포
7. service 안정화와 ALB health 확인
8. 실패 시 circuit breaker rollback

### Frontend

1. `npm run lint`
2. `npm run build`
3. build artifact를 private frontend S3에 동기화
4. hash asset은 장기 cache, `index.html`은 짧은 cache 적용
5. 필요한 경로만 CloudFront invalidation

## 애플리케이션 변경 필요 사항

인프라 구현 전에 다음 코드 변경이 필요합니다.

1. Backend Dockerfile이 현재 server 바이너리만 포함하므로 `migrate`, `seed`, `migrations/`도 runtime image에 포함해야 합니다.
2. 고정 `ENTRYPOINT` 대신 기본 `CMD` 또는 ECS `entryPoint` override가 가능한 구조로 바꿔 migration one-off Task를 실행할 수 있어야 합니다.
3. Backend 이미지를 `linux/arm64`로 빌드하는 CI 설정이 필요합니다.
4. 이미지 key를 직접 공개하는 `posts/*` 방식에서 quarantine/validation/clean media 방식으로 변경해야 합니다.
5. Frontend는 업로드 완료 및 검증 상태를 처리해야 합니다.
6. 운영 `DATABASE_URL`은 TLS를 강제해야 합니다.
