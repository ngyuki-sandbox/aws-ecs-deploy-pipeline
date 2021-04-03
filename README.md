# [AWS]CodeBuild/CodeDeploy/CodePipeline で ECS をデプロイする素振り

- rolling
    - ECS アクションプロバイダで Rolling Update
- blue-green
    - CodeDeployToECS アクションプロバイダで Blue-Green Deployment

```sh
cd blue-green/
terraform init
terraform apply

cd -
git remote add aws ssh://APKxxxxxxxxxxxxxxxxx@git-codecommit.ap-northeast-1.amazonaws.com/v1/repos/oreore-ecs-deploy-repo
git push aws master
```
