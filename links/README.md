# Project links

All links for the HabitApp CI/CD project (Jenkins, Maven, SonarQube, Docker Hub, Helm, Argo CD on AWS).

## Source code

| What | Link |
|---|---|
| Application repo (code, Dockerfile, Jenkinsfile) | https://github.com/narayanathota/HabitApp |
| Jenkinsfile | https://github.com/narayanathota/HabitApp/blob/main/Jenkinsfile |
| Dockerfile | https://github.com/narayanathota/HabitApp/blob/main/Dockerfile |
| Screenshots (evidence) | https://github.com/narayanathota/HabitApp/tree/main/screenshots |
| Config / GitOps repo (Helm chart, Argo CD manifest) | https://github.com/narayanathota/HabitApp-config |
| Helm chart | https://github.com/narayanathota/HabitApp-config/tree/main/charts/habitapp |
| Argo CD Application manifest | https://github.com/narayanathota/HabitApp-config/blob/main/argocd/application.yaml |
| Config repo commits made by Jenkins | https://github.com/narayanathota/HabitApp-config/commits/main |

## Container registry

| What | Link |
|---|---|
| Docker Hub repository (public) | https://hub.docker.com/r/narayanababut/habitapp |
| Tags (`<build>-<commit>`) | https://hub.docker.com/r/narayanababut/habitapp/tags |

## Running application (AWS EC2, ap-south-1)

| What | Link |
|---|---|
| Application | http://13.235.80.22/ |
| Health check | http://13.235.80.22/actuator/health |

## Tools on the AWS server

These three are restricted to the owner's IP address by the AWS security group, so they will not open
from other networks. Screenshots of each are in the `screenshots` folder.

| Tool | Link |
|---|---|
| Jenkins (job `habitapp-ci`) | http://13.235.80.22:8080/job/habitapp-ci/ |
| SonarQube (project `habit-tracker`) | http://13.235.80.22:9000/dashboard?id=habit-tracker |
| Argo CD (application `habitapp`) | https://13.235.80.22:30443/applications/argocd/habitapp |

## Notes

- The AWS server is temporary. It will be shut down after the project is reviewed, so the links in
  "Running application" and "Tools on the AWS server" will stop working then.
- No passwords or tokens are stored in either repository.
