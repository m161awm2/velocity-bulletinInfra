# Velocity Bulletin Infrastructure

Velocity Bulletin의 AWS 인프라 설계와 운영 기준을 정의합니다.

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

설계는 이와 같습니다
vpc의 CIDR : 10.20.0.0./24

서브넷, 리전, CIDR
퍼블릭A 10.20.1.0/24
퍼블릭C 10.20.2.0/24
프라이빗앱A 10.20.11.0/24
프라이빗앱C 10.20.12.0/24

ngw, igw를 라우팅테이블에 붙히고 vpc에 붙히고
ECS클러스터를 만든다 파게이트를 만들 예정이다

ECR레포지토리를 만들고 로컬에서 레포지토리로 푸시하여 ECS의 파게이트 태스크를 만들어주기 전 태스크의 역할을 2개 만들어주자 velocity-task-execution-role velocity-task-role두 역할을 만들어줍니다.

사용사례는 ECS => ECS task로 지정합니다
AmazonECSTaskExecutionRolePolicy정책을 velocity-task-execution-role역할에 붙히고

velocity-task-role얘는 지금은 정책 선택 없이 생성 → 나중에 S3 업로드용 인라인 정책 추가하겠다.
