
참고로 "구축 순서"는 이 설계(인터널 ALB + CloudFront VPC Origin) 그대로 실제 콘솔에서 끝까지 진행했던 기록입니다. VPC Origin 리소스(`velocity-api-origin`) 생성까지는 문제없이 됐지만, **이 VPC Origin을 실제 CloudFront 배포의 오리진으로 연결(association)하는 단계에서 막혔습니다** — 사용 중인 CloudFront 배포가 Free 플랜이었고, Free 플랜에서는 VPC Origin을 오리진으로 붙일 수 없다는 오류가 발생했습니다.

즉 이 메모/설계대로 계속 진행했다면 "그후 인터널 ALB가 보내면 태스크가 받아줘야 하니..." 이후, CloudFront에 오리진을 붙이는 시점에서 더 진행이 안 됐을 것입니다.

실제로는 여기서 설계를 바꿔서 다음과 같이 해결했습니다.

- 같은 VPC의 **Public 서브넷 2곳**에 **Internet-facing ALB**(`velocity-public-alb`)를 새로 생성
- 이 ALB의 보안 그룹 인바운드는 `0.0.0.0/0` 대신 AWS 관리형 prefix list `com.amazonaws.global.cloudfront.origin-facing`으로 제한 (CloudFront 엣지 이외의 직접 접근 차단)
- ALB 타겟 그룹은 **하나의 타겟 그룹을 두 ALB에 동시에 연결할 수 없다는 AWS 제약**(`TargetGroupAssociationLimit`) 때문에 새 타겟 그룹(`velocity-backend-tg-public`)을 추가로 만들고, ECS 서비스에 로드밸런서를 하나 더 등록(`aws ecs update-service --load-balancers`)해서 기존 internal ALB용 타겟 그룹과 새 public ALB용 타겟 그룹 모두에 태스크가 등록되도록 함
- CloudFront의 `/api/*` 오리진을 VPC Origin이 아니라 이 public ALB의 **일반 Custom(ELB) Origin**(HTTP:80)으로 교체

즉 최종적으로 배포된 구조는 internal ALB가 아니라 **public ALB + Custom Origin**입니다. internal ALB(`velocity-internal-alb`)와 미사용 VPC Origin(`velocity-api-origin`)은 당장 지우지 않고 새 경로가 안정적으로 동작하는지 확인한 뒤 정리하기로 했습니다.

이 저장소의 Terraform 코드(아래 "Terraform" 절)는 **원래 설계(인터널 ALB + VPC Origin)를 그대로 코드화한 것**입니다 — 실제로 막혔던 지점까지 포함해서 일부러 그대로 남겨뒀습니다. CloudFront 플랜이 VPC Origin을 지원하는 계정에서는 이 코드가 그대로 동작해야 합니다. Free 플랜을 유지해야 하는 경우 `aws_cloudfront_vpc_origin`과 관련 오리진/behavior를 위 public ALB 방식으로 바꿔야 합니다.
