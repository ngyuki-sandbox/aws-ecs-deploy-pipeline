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
    - family/executionRoleArn/taskRoleArn/secrets などを CodeBuild の環境変数に入れて置換
- terraform 管理のタスク定義からイメージのみ置換して taskdef.json を生成
    - タスク定義は terraform 管理、イメージのみ CodePipeline で更新
    - 前者のタスク定義をテンプレートと位置付けて、CodePipeline が作成するタスク定義とは別にするとスッキリするかも
- CodeBuild の環境変数に taskdef.json そのものを入れる
    - タスク定義は terraform 管理、イメージのみ CodePipeline で更新、なのは前者と同じ
    - buildspec.yml でやることが少なくて済むのでシンプル
- terraform で S3 に taskdef.json を作成して CodePipeline のソースにする
    - terraform で taskdef.json を更新すればデプロイが走るし、良さそう
    - jsonencode を使うと `<` や `>` がエスケープされてしまってダメなので注意

## キューワーカー用のサービス

CodeDeployToECS によるデプロイだとロードバランサが必須なのでキューワーカー用のサービスの場合は ECS の Rolling Update にするしかない。
その場合に CodePipeline を使うと、デプロイ時のタスク定義が元のサービスに適用されているタスク定義の一部置換になってしまうため、
CodeDeployToECS のときのように taskdef.json を別に提供、みたいなことができない。

ECS アクションも taskdef.json を別に指定する、とかであれば簡単だったのだけど・・方針を揃えるためには
キューワーカー用のサービスでは CodeBuild でタスク定義＆サービス更新を個別に処理するしかない。

## EventBridge Schedule

定期バッチ的なものを EventBridge Schedule で実行している場合、EventBridge のターゲットでもタスク定義を設定する必要があるため、
デプロイ時にそちらの更新も必要になる。

CodePipeline の ECS や CodeDeployToECS アクションが作成したタスク定義を元に更新できれば良いが・・
これらのアクションの出力変数としてタスク定義の arn が得られれば良いが、実際にはなにも出力しないので、
ファミリ指定で最新のタスク定義を取得してその arn で更新する、とかしかできなさそう。

もしくは EventBridge のターゲットであればタスク定義のリビジョンを未指定で常に最新を参照させることができるので、
単にそれだけで良いかもしれない。
