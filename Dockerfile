FROM public.ecr.aws/lambda/python:3.9

COPY container-error-handling-and-cleanup-sf.py ${LAMBDA_TASK_ROOT}
COPY script.sh ${LAMBDA_TASK_ROOT}
RUN curl -o /etc/yum.repos.d/gh-cli.repo https://cli.github.com/packages/rpm/gh-cli.repo
RUN yum install -y git
RUN yum install -y gh
RUN yum install -y jq
CMD [ "container-error-handling-and-cleanup-sf.lambda_handler" ]

