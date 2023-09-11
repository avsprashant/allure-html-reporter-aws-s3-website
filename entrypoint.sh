#! /usr/bin/env bash

#this isn't required if html file already present
          cat > index-template.html <<EOF

<!DOCTYPE html>
<html>
<head>
 <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
 <title>Test Results</title>
 <style type="text/css">
  BODY { font-family : monospace, sans-serif;  color: black;}
  P { font-family : monospace, sans-serif; color: black; margin:0px; padding: 0px;}
  A:visited { text-decoration : none; margin : 0px; padding : 0px;}
  A:link    { text-decoration : none; margin : 0px; padding : 0px;}
  A:hover   { text-decoration: underline; background-color : yellow; margin : 0px; padding : 0px;}
  A:active  { margin : 0px; padding : 0px;}
  .VERSION { font-size: small; font-family : arial, sans-serif; }
  .NORM  { color: black;  }
  .FIFO  { color: purple; }
  .CHAR  { color: yellow; }
  .DIR   { color: blue;   }
  .BLOCK { color: yellow; }
  .LINK  { color: aqua;   }
  .SOCK  { color: fuchsia;}
  .EXEC  { color: green;  }
 </style>
</head>
<body>
	<h1>Test Results</h1><p>
	<a href=".">.</a><br>

EOF

export AWS_S3_BUCKET=habitat-build-artifacts
export S3_WEBSITE_URL=https://artifact.habitatenergy.online/allure/${INPUT_GITHUB_REPO}/${INPUT_GITHUB_RUN_NUM}/

mkdir -p ./${INPUT_ALLURE_HISTORY}

#echo "executor.json"
echo '{"name":"GitHub Actions","type":"github","reportName":"Allure Report with history",' > executor.json
echo "\"url\":\"${S3_WEBSITE_URL}\"," >> executor.json
# echo "\"reportUrl\":\"${GITHUB_PAGES_WEBSITE_URL}/${INPUT_GITHUB_RUN_NUM}/\"," >> executor.json
echo "\"buildUrl\":\"https://github.com/${INPUT_GITHUB_REPO}/actions/runs/${INPUT_GITHUB_RUN_ID}\"," >> executor.json
echo "\"buildName\":\"GitHub Actions Run #${INPUT_GITHUB_RUN_ID}\",\"buildOrder\":\"${INPUT_GITHUB_RUN_NUM}\"}" >> executor.json
#cat executor.json
mv ./executor.json ./${INPUT_ALLURE_RESULTS}

#environment.properties
echo "URL=${S3_WEBSITE_URL}" >> ./${INPUT_ALLURE_RESULTS}/environment.properties

echo "generating report from ${INPUT_ALLURE_RESULTS} to ${INPUT_ALLURE_REPORT} ..."
ls -l ${INPUT_ALLURE_RESULTS}
allure generate --clean ${INPUT_ALLURE_RESULTS} -o ${INPUT_ALLURE_REPORT}
echo "listing report directory ..."
ls -l ${INPUT_ALLURE_REPORT}

echo "copy allure-report to ${INPUT_ALLURE_HISTORY}/${INPUT_GITHUB_RUN_NUM}"
cp -r ./${INPUT_ALLURE_REPORT}/. ./${INPUT_ALLURE_HISTORY}/${INPUT_GITHUB_RUN_NUM}
# echo "copy allure-report history to /${INPUT_ALLURE_HISTORY}/last-history"
# cp -r ./${INPUT_ALLURE_REPORT}/history/. ./${INPUT_ALLURE_HISTORY}/last-history

# #echo "index.html"
# echo "<!DOCTYPE html><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"0; URL=${S3_WEBSITE_URL}/${INPUT_GITHUB_RUN_NUM}/\">" > ./${INPUT_ALLURE_HISTORY}/index.html # path
# echo "<meta http-equiv=\"Pragma\" content=\"no-cache\"><meta http-equiv=\"Expires\" content=\"0\">" >> ./${INPUT_ALLURE_HISTORY}/index.html
# cat ./${INPUT_ALLURE_HISTORY}/index.html

cat index-template.html > ./${INPUT_ALLURE_HISTORY}/index.html

echo "├── <a href="./${INPUT_GITHUB_RUN_NUM}/index.html">Latest Test Results - RUN ID: ${INPUT_GITHUB_RUN_NUM}</a><br>" >> ./${INPUT_ALLURE_HISTORY}/index.html;
sh -c "AWS_PROFILE=uk aws s3 ls s3://${AWS_S3_BUCKET}/allure/${INPUT_GITHUB_REPO}/" |  grep "PRE" | sed 's/PRE //' | sed 's/.$//' | sort -nr | while read line;
    do
        echo "├── <a href="./"${line}"/">RUN ID: "${line}"</a><br>" >> ./${INPUT_ALLURE_HISTORY}/index.html; 
    done;
echo "</html>" >> ./${INPUT_ALLURE_HISTORY}/index.html;


echo "copy allure-results to ${INPUT_ALLURE_HISTORY}/${INPUT_GITHUB_RUN_NUM}"
cp -R ./${INPUT_ALLURE_RESULTS}/. ./${INPUT_ALLURE_HISTORY}/${INPUT_GITHUB_RUN_NUM}

set -e

if [ -z "$AWS_S3_BUCKET" ]; then
  echo "AWS_S3_BUCKET is not set. Quitting."
  exit 1
fi

# we don't want this
# Override default AWS endpoint if user sets AWS_S3_ENDPOINT.
if [ -n "$AWS_S3_ENDPOINT" ]; then
  ENDPOINT_APPEND="--endpoint-url $AWS_S3_ENDPOINT"
fi

# All other flags are optional via the `args:` directive.
sh -c "AWS_PROFILE=uk aws s3 sync ./${INPUT_ALLURE_HISTORY}/${INPUT_GITHUB_RUN_NUM} s3://${AWS_S3_BUCKET}/allure/${INPUT_GITHUB_REPO}/${INPUT_GITHUB_RUN_NUM}/ \
              --no-progress \
              ${ENDPOINT_APPEND} $*"

# Delete history
COUNT=$( sh -c "AWS_PROFILE=uk aws s3 ls s3://${AWS_S3_BUCKET}/allure/${INPUT_GITHUB_REPO}/" | sort -n | grep "PRE" | wc -l )
echo "current folders in allure-history: ${COUNT}"
echo "keep reports count ${INPUT_KEEP_REPORTS}"
INPUT_KEEP_REPORTS=$((INPUT_KEEP_REPORTS+1))
echo "if ${COUNT} > ${INPUT_KEEP_REPORTS}"
if (( COUNT > INPUT_KEEP_REPORTS )); then
  NUMBER_OF_FOLDERS_TO_DELETE=$((${COUNT}-${INPUT_KEEP_REPORTS}))
  echo "remove old reports"
  echo "number of folders to delete ${NUMBER_OF_FOLDERS_TO_DELETE}"
  sh -c "AWS_PROFILE=uk aws s3 ls s3://${AWS_S3_BUCKET}/allure/${INPUT_GITHUB_REPO}/" |  grep "PRE" | sed 's/PRE //' | sed 's/.$//' | head -n ${NUMBER_OF_FOLDERS_TO_DELETE} | sort -n | while read -r line;
    do
      sh -c "AWS_PROFILE=uk aws s3 rm s3://${AWS_S3_BUCKET}/allure/${INPUT_GITHUB_REPO}/${line}/ --recursive";
      echo "deleted prefix folder : ${line}";
    done;
fi
