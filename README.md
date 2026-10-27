# Habit Tracker

A self-contained Spring Boot REST API + dashboard for tracking daily/weekly habits and streaks.
**No external database** — all data is held in memory (`ConcurrentHashMap`) for the life of the process.

> This repository also contains a complete CI/CD setup (Jenkins, SonarQube, Docker, Helm, Argo CD).
> Jump to [CI/CD pipeline](#cicd-pipeline-jenkins--argo-cd-gitops). The original application docs follow below it.

## CI/CD pipeline (Jenkins + Argo CD GitOps)

Jenkins does **Continuous Integration**. Argo CD does **Continuous Deployment**.
Jenkins never runs `kubectl` or `helm install`; it only commits a new image tag to Git.

```
GitHub (this repo)
   -> Jenkins -> Maven build -> Unit tests -> SonarQube + Quality Gate
   -> Docker build -> Docker Hub (narayanathota/habitapp:<build>-<sha>)
   -> commit new image.tag to the config repo
HabitApp-config repo (GitOps)
   -> Argo CD detects the commit -> syncs -> Kubernetes rolling update
```

### Repositories

| Repo | Purpose |
|---|---|
| [narayanathota/HabitApp](https://github.com/narayanathota/HabitApp) (this repo) | Application code, `pom.xml`, `Dockerfile`, `Jenkinsfile` |
| [narayanathota/HabitApp-config](https://github.com/narayanathota/HabitApp-config) | Helm chart (`charts/habitapp`) and Argo CD manifest (`argocd/application.yaml`) |

Two repos are used on purpose: when Jenkins commits a new image tag it only touches the config
repo, so it can never re-trigger this repo's pipeline (no build loop).

### What was added to the original app

| File | Why |
|---|---|
| `pom.xml` | Added `spring-boot-starter-actuator` for health endpoints |
| `application.properties` | Exposes `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` |
| `HabitControllerTests.java` | 6 extra tests (health probes, create, validation, streak, delete) - 7 tests total |
| `Dockerfile`, `.dockerignore`, `.gitignore` | Container image (see below) |
| `Jenkinsfile` | The CI pipeline |

### Docker image

- Multi-stage build: Maven + JDK 21 builds the jar, `eclipse-temurin:21-jre-alpine` runs it.
- Runs as non-root (UID/GID 10001), exposes port 8080, has a `HEALTHCHECK`.
- JVM is PID 1 (`exec`) so it shuts down gracefully on `SIGTERM`.
- No credentials in the image; `.dockerignore` keeps `.env`, keys and `target/` out of the build context.

```bash
docker build -t narayanathota/habitapp:local .
docker run -p 8080:8080 narayanathota/habitapp:local
curl http://localhost:8080/actuator/health        # {"status":"UP",...}
```

### Jenkins pipeline (`Jenkinsfile`, declarative)

| # | Stage | What it does |
|---|---|---|
| 1 | Checkout | `checkout scm` |
| 2 | Maven Build | `mvn clean package -DskipTests` |
| 3 | Unit Test | `mvn test`, publishes JUnit results |
| 4 | SonarQube Analysis | `mvn sonar:sonar` through `withSonarQubeEnv` |
| 5 | Quality Gate | `waitForQualityGate abortPipeline: true` (stops the pipeline on failure) |
| 6 | Image Versioning | tag = `<build-number>-<git-sha>` |
| 7 | Docker Build | builds `narayanathota/habitapp:<tag>` |
| 8 | Push Image | `docker push` (main branch only) |
| 9 | Update Helm Configuration | clones the config repo, changes only the `image.tag` line in `values.yaml` |
| 10 | Commit Deployment Change | commits and pushes to the config repo |

Jenkins needs: tools `maven-3.9` and `jdk-21`, a SonarQube server named `sonarqube`, and two
credentials stored in Jenkins (never in Git): `dockerhub-creds` and `github-creds`
(username + access token each). The SonarQube webhook is `http://<jenkins>:8080/sonarqube-webhook/`.

### Kubernetes (Helm chart in the config repo)

- Deployment: 2 replicas, `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1`.
- Startup, readiness and liveness probes on the Actuator endpoints.
- Resource requests (250m CPU / 384Mi) and limits (500m / 768Mi).
- Service, ConfigMap, optional Secret, optional Ingress, dedicated ServiceAccount.
- Zero-downtime rollouts: graceful shutdown (`SERVER_SHUTDOWN=graceful`) plus a 10 s `preStop` sleep.
  Without these, a test run dropped 4 of 196 requests during a rollout; with them, 0 of 250.

### Argo CD

`argocd/application.yaml` (in the config repo) defines an `AppProject` limited to the config repo
and the `habitapp` namespace, and an `Application` with automated sync, `prune` and `selfHeal`.
Change anything in Git and Argo CD applies it; a manual `kubectl scale` is reverted by self-heal.

### Deploy, update and roll back

```bash
# install Argo CD once, then:
kubectl apply -f argocd/application.yaml        # from the config repo

# a deployment = a commit to the config repo (Jenkins does this automatically)
# roll back = revert that commit; Argo CD syncs the previous version
git revert <bad-commit> && git push
```

### Security

- Credentials live only in the Jenkins credential store; the Jenkinsfile uses credential IDs.
- No secrets in either repo (checked across the full Git history).
- Pods run as UID 10001 with `runAsNonRoot`, read-only root filesystem, all Linux capabilities
  dropped, no privilege escalation, `RuntimeDefault` seccomp and no service-account token mounted.
- The `habitapp` namespace enforces Kubernetes Pod Security `restricted`; a root pod is rejected.
- The app's ServiceAccount cannot read Secrets, list or delete pods, or create anything.
- Application secrets are created outside Git: `kubectl -n habitapp create secret generic habitapp-secret ...`.

### Monitoring and troubleshooting

```bash
kubectl -n habitapp get pods                    # status and RESTARTS
kubectl -n habitapp top pods                    # CPU / memory (needs metrics-server)
kubectl -n habitapp logs deploy/habitapp        # application logs
kubectl -n habitapp logs <pod> --previous       # logs of the crashed/restarted container
kubectl -n habitapp get events --sort-by=.lastTimestamp
kubectl -n argocd get application habitapp      # Synced / Healthy
```

Example drill: changing the liveness path to a wrong URL in Git produced restarts and the event
`Liveness probe failed: HTTP probe failed with statuscode: 404`; reverting the commit fixed it.

### Known limitation

All data is stored in memory. With several replicas each pod has its own data, and a restart clears it.

### Application URL and evidence

- Application URL: _to be added after the AWS deployment_
- Container registry: https://hub.docker.com/r/narayanathota/habitapp
- Screenshots: _to be added_ (Maven build, SonarQube Quality Gate, Jenkins stage view, Docker Hub tags,
  Argo CD Synced/Healthy, rolling update, rollback, monitoring).

---

## Original application documentation

## Tech stack
- Java 21 (or higher — LTS)
- Spring Boot 3.3.4 (`spring-boot-starter-web`, `spring-boot-starter-validation`)
- Maven (packaged as an executable jar)
- Vanilla HTML/CSS/JS dashboard (served as a static resource, no frontend build step)

## Requirements
- **JDK 21+** installed and set as `JAVA_HOME` (verify with `java -version`)
- Maven 3.6+ (verify with `mvn -version`)

## Build

```bash
mvn clean package
```

This produces `target/habit-tracker.jar`.

## Run

```bash
java -jar target/habit-tracker.jar
```

Then open **http://localhost:8080** in your browser for the dashboard, or call the API directly.

## REST API

| Method | Endpoint                        | Description                          |
|--------|----------------------------------|---------------------------------------|
| GET    | `/api/habits`                    | List all habits                      |
| GET    | `/api/habits/{id}`               | Get a single habit                   |
| POST   | `/api/habits`                    | Create a habit                       |
| PUT    | `/api/habits/{id}`               | Update a habit's name/description    |
| DELETE | `/api/habits/{id}`               | Delete a habit                       |
| PATCH  | `/api/habits/{id}/active`        | Activate/deactivate a habit          |
| POST   | `/api/habits/{id}/complete`      | Mark habit complete for today (or `?date=YYYY-MM-DD`) |
| DELETE | `/api/habits/{id}/complete`      | Unmark completion for a date         |
| GET    | `/api/habits/{id}/stats`         | Streaks + last-7-day completion rate |

### Example: create a habit

```bash
curl -X POST http://localhost:8080/api/habits \
  -H "Content-Type: application/json" \
  -d '{"name":"Drink water","description":"8 glasses a day","frequency":"DAILY"}'
```

### Example: mark it done today

```bash
curl -X POST http://localhost:8080/api/habits/1/complete
```

## SonarQube code scan

### Requirements
- A running SonarQube server (Community Edition is fine) — locally via Docker is easiest, or use SonarCloud
- Java 21+ (same JDK used to build the project)
- Maven 3.6+
- A Sonar authentication token (generate from the SonarQube UI: **My Account → Security → Generate Token**)
- Network access from your machine to the SonarQube server (default port `9000`)

### 1. Start a local SonarQube server (skip if you already have one, or are using SonarCloud)
```bash
docker run -d --name sonarqube -p 9000:9000 sonarqube:community
```
Wait ~1 minute, then open http://localhost:9000 (default login `admin` / `admin`, it'll prompt you to change the password). Generate a token as noted above.

### 2. Run the scan via Maven (recommended — no separate scanner install needed)
```bash
mvn clean verify sonar:sonar \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.token=YOUR_GENERATED_TOKEN
```
- `clean verify` compiles, runs tests, and generates the JaCoCo coverage report the `pom.xml` is already configured to produce.
- `sonar:sonar` (from the `sonar-maven-plugin` already added to `pom.xml`) runs the actual analysis and uploads results to the server.

### 3. Alternative: standalone `sonar-scanner` CLI
If you'd rather not use the Maven plugin, install the [SonarScanner CLI](https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/scanners/sonarscanner/), then from the project root:
```bash
mvn clean verify        # still needed, to produce target/classes + jacoco.xml
sonar-scanner -Dsonar.token=YOUR_GENERATED_TOKEN
```
This picks up settings from `sonar-project.properties`, already included in the project.

### 4. Using SonarCloud instead of a local server
Replace `-Dsonar.host.url` with SonarCloud's URL and add your organization key:
```bash
mvn clean verify sonar:sonar \
  -Dsonar.host.url=https://sonarcloud.io \
  -Dsonar.organization=YOUR_ORG_KEY \
  -Dsonar.token=YOUR_SONARCLOUD_TOKEN
```

### Where results show up
After the scan finishes, open the SonarQube/SonarCloud dashboard for project key `habit-tracker` to see bugs, code smells, vulnerabilities, and test coverage (from JaCoCo).

## Notes
- Streaks (`currentStreak`, `longestStreak`) are recalculated automatically whenever a habit is marked/unmarked complete.
- Because storage is in-memory, restarting the app clears all data. Swapping in a real database later just means replacing `HabitRepository` with a Spring Data JPA repository — the service/controller layers don't need to change.
