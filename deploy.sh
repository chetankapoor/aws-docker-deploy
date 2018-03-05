#!/bin/bash

echo $PROFILE
# Download template
curl -LSso Dockerrun.aws.json.template https://raw.githubusercontent.com/chetankapoor/aws-docker-deploy/master/Dockerrun.aws.json.template

# Set vars that typically do not vary by app
BRANCH=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
SHA1=$(git rev-parse HEAD)
VERSION=$BRANCH-$SHA1-$(date +%s)
DESCRIPTION=$(git log -1 --pretty=%B)
DESCRIPTION=${DESCRIPTION:0:180} # truncate to 180 chars - max beanstalk version description is 200
ZIP=$VERSION.zip

aws configure set default.region $AWS_REGION

# Authenticate against our Docker registry
eval $(aws ecr get-login --region $AWS_REGION --profile $PROFILE | sed "s/-e none //")

# Build and push the image
export IMAGE_NAME=$NAME:$VERSION
echo docker-compose
docker-compose -f docker-compose.yaml build
echo Tagging Image
docker tag $IMAGE_NAME $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_NAME
echo Docker push
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_NAME

# Copy template Dockerrun.aws.json and replace template vars
cp Dockerrun.aws.json.template Dockerrun.aws.json

# Replace the template values
sed -i.bak "s/<AWS_ACCOUNT_ID>/$AWS_ACCOUNT_ID/" Dockerrun.aws.json
sed -i.bak "s/<AWS_REGION>/$AWS_REGION/" Dockerrun.aws.json
sed -i.bak "s/<NAME>/$NAME/" Dockerrun.aws.json
sed -i.bak "s/<TAG>/$VERSION/" Dockerrun.aws.json
sed -i.bak "s/<CONTAINER_PORT>/$CONTAINER_PORT/" Dockerrun.aws.json
sed -i.bak "s/<BUCKET>/$BUCKET/" Dockerrun.aws.json
sed -i.bak "s/<KEY>/$KEY/" Dockerrun.aws.json

# Zip up the Dockerrun file (feel free to zip up an .ebextensions directory with it)
zip -r $ZIP Dockerrun.aws.json

aws s3 cp $ZIP s3://$EB_BUCKET/$ZIP --profile $PROFILE --region $AWS_REGION

# Create a new application version with the zipped up Dockerrun file
aws elasticbeanstalk create-application-version --application-name "$EB_APP_NAME" \
    --version-label $VERSION --description "$DESCRIPTION" --source-bundle S3Bucket=$EB_BUCKET,S3Key=$ZIP  --profile $PROFILE

# Update the environment to use the new application version
if [ -z "$EB_ENV_NAME" ]; then
    echo "EB_ENV_NAME is not set, skipping deployment step"
else
    aws elasticbeanstalk update-environment --environment-name $EB_ENV_NAME \
        --version-label $VERSION --profile $PROFILE
fi

# Clean up
rm $ZIP
rm Dockerrun.aws.json
rm Dockerrun.aws.json.bak
rm Dockerrun.aws.json.template
