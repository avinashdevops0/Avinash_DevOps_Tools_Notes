```sh
eksctl  create cluster --name=sweety --region=us-east-1 --zones=us-east-1a,us-east-1b --without-nodegroup

eksctl utils  associate-iam-oidc-provider --region=us-east-1 --cluster=sweety --approve

eksctl create nodegroup \
  --cluster=sweety \
  --region=us-east-1 \
  --name=sweety \
  --node-type=c7i-flex.large \
  --nodes=2 \
  --nodes-min=2 \
  --nodes-max=3 \
  --node-volume-size=30 \
  --ssh-public-key=kaido \
  --managed \
  --asg-access \
  --external-dns-access \
  --full-ecr-access \
  --appmesh-access \
  --alb-ingress-access

aws eks update-kubeconfig --name=sweety --region=us-east-1

```