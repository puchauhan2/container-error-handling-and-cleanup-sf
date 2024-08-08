#!/bin/bash
rm -rf /tmp/github_code/
mkdir -p /tmp/github_code/

PR_ALL_STATUS="/tmp/all_pr"
MAIN_BRANCH="main"

echo "Setting variables"
export REPO_URL="${1}"
export GITHUB_TOKEN="${2}"
export BRANCH_NAME="${3}"
export GITHUB_API_BASE_URL="${4}"

TIMESTAMP=$(date +%s)
REVERT_BRANCH_NAME="${BRANCH_NAME}-${TIMESTAMP}-revert"

cd /tmp/github_code/
git clone https://${GITHUB_TOKEN}@${REPO_URL} .

git config user.email "accountvendingautomation@github.com"
git config user.name "Account Vending Automation"

gh pr list --state all --limit 100 > ${PR_ALL_STATUS}
PR_BRANCH_STATUS=` grep "${BRANCH_NAME}" ${PR_ALL_STATUS} `
PR_NUMBER=`echo ${PR_BRANCH_STATUS} | awk '{print $1}'`
PR_STATUS=`echo ${PR_BRANCH_STATUS} | awk '{print $4}'`

get_merge_commit_sha() {
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    ${GITHUB_API_BASE_URL}/pulls/$PR_NUMBER | jq -r '.merge_commit_sha'
}

function revert_changes() {
  MERGE_COMMIT_SHA=$(get_merge_commit_sha)
  if [ -z "$MERGE_COMMIT_SHA" ] || [ "$MERGE_COMMIT_SHA" == "null" ]; then
    echo "Merge commit SHA not found. Exiting."
    exit 1
  fi


git checkout ${BRANCH_NAME} || { echo 'Failed to checkout branch'; exit 1; }
git pull origin ${BRANCH_NAME} || { echo 'Failed to pull latest changes'; exit 1; }
git checkout -b ${REVERT_BRANCH_NAME} || { echo 'Failed to create or switch to revert branch'; exit 1; }
echo "Executing revert"
git revert -m 1 -n ${MERGE_COMMIT_SHA}|| { echo 'Failed to revert last commit'; exit 1; }
git add .
git commit -m "Reverting from ${BRANCH_NAME}"
echo "Executing push "
git push https://${GITHUB_TOKEN}@${REPO_URL} ${REVERT_BRANCH_NAME}
  
gh pr create --title "${REVERT_BRANCH_NAME}" --body "Reverting Branch ${BRANCH_NAME}" --base main --head "${REVERT_BRANCH_NAME}"  2>&1 | tee /tmp/result
  
pull_request_url=`cat /tmp/result | grep https`
echo ${pull_request_url}
pull_request_number="${pull_request_url##*/}"
echo ${pull_request_number}

git fetch origin
git checkout $BASE_BRANCH
git pull origin $BASE_BRANCH

if git merge --no-commit --no-ff ${REVERT_BRANCH_NAME}; 
then
echo "No conflicts detected. Ready to merge.";     
git merge --abort; 
else     
echo "Conflicts detected. Please resolve conflicts before merging."; 
git merge --abort;
exit 1
echo "Reverting commit in main branch"    
fi

echo "Merging Pull request"
gh pr merge ${pull_request_number} --merge

if [[ "$?" == "0" ]]
then 
echo " Pull request merged"
else 
echo "Pull request merge failed"
exit 1
fi

}

case "${PR_STATUS}" in

   "OPEN")
		echo -e "PR is OPEN"
		gh pr close ${PR_NUMBER} && echo "PR is closed now"
		exit 0
      ;;
   "CLOSED")
		echo -e "PR is already closed"
		exit 0
      ;;
   "MERGED")
		echo -e "PR is already merged ,reverting changes"
		revert_changes
      ;;
   *)
		echo -e "Some error occured";
		exit 1
     ;;
esac
