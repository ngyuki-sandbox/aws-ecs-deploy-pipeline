# [AWS]CodeBuild/CodeDeploy/CodePipeline で ECS をデプロイする素振り

- rolling
    - ECS アクションプロバイダで Rolling Update
- blue-green
    - CodeDeployToECS アクションプロバイダで Blue-Green Deployment

## Rolling Update

```sh
terraform -chdir=terraform/rolling init
terraform -chdir=terraform/rolling plan
terraform -chdir=terraform/rolling apply

git remote add aws "$(terraform -chdir=terraform/rolling output -raw git_ssh_url)"
git push aws main

open "$(terraform -chdir=terraform/rolling output -raw app_url)"
```

## Blue-Green Deployment

```sh
terraform -chdir=terraform/blue-green init
terraform -chdir=terraform/blue-green plan
terraform -chdir=terraform/blue-green apply

git remote add aws "$(terraform -chdir=terraform/blue-green output -raw git_ssh_url)"
git push aws main

open "$(terraform -chdir=terraform/blue-green output -raw app_url)"
```

## ECS Rolling Update の ignore changes

CodePipeline で ECS を Rolling Update デプロイしていると terraform 管理外でタスク定義が更新されるため差分が出続ける問題。

- `aws_ecs_task_definition.container_definitions` を `ignore_changes`
    - タスク定義の arn はリビジョンも含むためタスク定義の変更を無視してもサービスの方でタスク定義のリビジョンアップが検出される
    - そもそもタスク定義は terraform 外でリビジョン更新しても terraform は変更を検知しないので無視する意味無し
    - よって、全くダメ
- `aws_ecs_service.task_definition` を `ignore_changes`
    - タスク定義で環境変数などの image 以外の属性を変更したときにそれを反映する術が難しくなる
    - CodePipeline の ECS アクションは更新しようとしているサービスに適用されているタスク定義のリビジョンのコピーを作成するため
    - 環境変数などの更新はマネコンから手作業のみ、とかに割り切るならアリかもだけど微妙
- `aws_ecs_service.task_definition` に `data.aws_ecs_service.task_definition` を入れる
    - 条件で `data.aws_ecs_service.task_definition` と `aws_ecs_task_definition` のどちらを入れるか分岐する
    - `aws_ecs_task_definition` の `image` も `data.aws_ecs_service.task_definition` から間接的に参照させることで現状を維持させる
    - タスク定義更新時にそのトリガとなる変数を設けることでできなくも無さそうだけど、無駄に複雑すぎる気がする

CodeDeploy ならこの類の問題は解決できそうなので CodeDeploy でいいかも。
あるいは CodePipeline の ECS アクションは使わずに CodeBuild で自前でサービス更新のうえで `aws ecs wait services-stable` でもよいかも。

## CodeDeployToECS の taskdef.json

CodeDeployToECS の taskdef.json をどこから生成するかが問題。

- リポジトリに taskdef.json を入れて CodeBuild で一部置換
    - 環境変数にリソースの arn を入れる場合にそれを置換させるのがちょっと煩雑ではある
    - 環境変数を S3 上のファイルにも出来るので ConfigMap のような感覚で別ファイル参照させると良いかも
- terraform 管理のタスク定義からイメージのみ置換
    - イメージ以外は terraform での管理で、イメージのみ CodePipeline にできる
    - 環境変数などの変更時に最新のタスク定義を仮のイメージで作成する必要があるため後述の EventBridge ターゲットで最新リビジョン指定していると都合が悪い

## EventBridge Schedule

定期バッチ的なものを EventBridge Schedule で実行している場合、EventBridge のターゲットでもタスク定義を設定する必要があるため、
デプロイ時にそちらの更新も必要になる。

CodePipeline の ECS や CodeDeployToECS アクションが作成したタスク定義を元に更新できれば良いが・・
これらのアクションの出力変数としてタスク定義の arn が得られれば良いが、実際にはなにも出力しないので、
ファミリ指定で最新のタスク定義を取得してその arn で更新する、とかしかできなさそう。

もしくは EventBridge のターゲットであればタスク定義のリビジョンを未指定で常に最新を参照させることができるので、
単にそれだけで良いかもしれない。
