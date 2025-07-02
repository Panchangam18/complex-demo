# 🚀 Jenkins-Nexus Integration Triggers & Configuration

## 🎯 What Triggers Jenkins to Use Nexus?

The Jenkins-Nexus integration is triggered in **multiple ways** depending on your architecture plan requirements:

## 1. 🔧 **Configuration-Based Triggers** (Currently Active)

### **A. Pipeline Job Configuration** ✅
- **What**: Jenkins jobs configured with Nexus endpoints
- **When**: Every time a configured job runs
- **Where**: In the pipeline script itself

```groovy
// In Jenkins Pipeline (already configured)
environment {
    NEXUS_URL = 'http://k8s-nexusdev-nexuster-3c4349a0ff-2a35bf4d26813bc4.elb.us-east-2.amazonaws.com:8081'
    NPM_REGISTRY = "${NEXUS_URL}/repository/npm-public/"
    MAVEN_REPO = "${NEXUS_URL}/repository/maven-public/"
}
```

### **B. Build Tool Configuration** ✅
- **Maven**: Uses `settings.xml` pointing to Nexus
- **NPM**: Registry configured to Nexus proxy
- **Python**: pip index-url set to Nexus PyPI proxy

## 2. 🕐 **Time-Based Triggers** (Architecture Plan: "Nightly Tasks")

### **Manual Triggers** (Current State)
- **URL**: http://3.149.193.86:8080/job/nexus-integration-test/build
- **Method**: Click "Build Now" or API call
- **Purpose**: On-demand testing and validation

### **Scheduled Triggers** (Need to Configure)
```groovy
// For nightly builds (as per architecture plan)
triggers {
    cron('H 2 * * *')  // Run at 2 AM daily
}
```

### **SCM Polling Triggers** (For Git Integration)
```groovy
triggers {
    pollSCM('H/15 * * * *')  // Check Git every 15 minutes
}
```

## 3. 🔗 **Event-Based Triggers** (Architecture Plan: Git-Centric)

### **GitHub Webhooks** (Next Phase)
- **What**: Automatic builds on Git push/PR
- **Configuration**: GitHub webhook → Jenkins
- **URL**: `http://3.149.193.86:8080/github-webhook/`

### **CircleCI Integration** (Architecture Plan)
- **What**: Jenkins handles legacy JVM builds while CircleCI does modern apps
- **Trigger**: CircleCI can trigger Jenkins jobs via API
- **Use Case**: Heavy JVM compilation, Maven artifacts

## 4. 📦 **Dependency-Based Triggers** (Nexus Configuration)

### **Automatic Nexus Usage** ✅
```bash
# NPM automatically uses Nexus when configured
npm config set registry http://nexus-url/repository/npm-public/
npm install  # ← This now triggers Nexus caching

# Maven automatically uses Nexus with settings.xml
mvn clean install -s settings.xml  # ← This triggers Nexus caching

# Python automatically uses Nexus when configured
pip install requests  # ← This triggers Nexus PyPI proxy
```

## 5. 🎯 **Current Trigger Configuration Status**

| Trigger Type | Status | Configuration Location |
|-------------|--------|------------------------|
| **Manual Build** | ✅ Active | Jenkins UI + API |
| **Pipeline Configuration** | ✅ Active | `nexus-integration-test` job |
| **Nexus Repository Usage** | ✅ Active | Maven/NPM/Python configs |
| **Scheduled Builds** | ⚠️ Not Set | Need to add cron triggers |
| **Git Webhooks** | ❌ Not Set | Need GitHub webhook setup |
| **Service Discovery** | ✅ Active | Consul health checks |

## 6. 🔧 **Where Triggers Are Configured**

### **A. Jenkins Job Level** (Pipeline Script)
```groovy
pipeline {
    agent any
    
    triggers {
        // Nightly builds for legacy artifacts (architecture plan)
        cron('H 2 * * *')
        
        // SCM polling for Git changes
        pollSCM('H/15 * * * *')
    }
    
    environment {
        // Nexus configuration (already set)
        NEXUS_URL = 'http://nexus-host:8081'
    }
    
    stages {
        stage('Legacy Build') {
            steps {
                // This triggers Nexus usage automatically
                sh 'mvn clean install -s settings.xml'
            }
        }
    }
}
```

### **B. Global Jenkins Configuration**
- **System Configuration** → Global Tool Configuration
- **Maven installations** pointing to Nexus-configured settings
- **Node.js installations** with Nexus npm registry

### **C. Build Tool Level** (settings.xml, .npmrc, pip.conf)
```xml
<!-- Maven settings.xml (already configured) -->
<settings>
    <mirrors>
        <mirror>
            <id>nexus-maven-proxy</id>
            <mirrorOf>*</mirrorOf>
            <url>http://nexus-url/repository/maven-public/</url>
        </mirror>
    </mirrors>
</settings>
```

## 7. 🚀 **Architecture Plan Integration**

### **Current Implementation** (Phase 1)
```
✅ Jenkins: Legacy JVM builds & nightly tasks
✅ Nexus: Upstream cache for Maven, NPM, PyPI
✅ Integration: Pipeline job with dependency caching
✅ Monitoring: Prometheus metrics on builds
```

### **Next Phase Triggers** (Enhanced)
```
🔄 Git Webhooks: Automatic builds on code changes
🔄 CircleCI Integration: Trigger Jenkins for heavy builds
🔄 Scheduled Nightly: Artifact cleanup and maintenance
🔄 Cross-Cloud: Trigger builds across AWS/GCP/Azure
```

## 8. 🎯 **Practical Trigger Examples**

### **Manual Trigger** (Current)
```bash
# Via Jenkins UI
curl -X POST -u admin:password http://3.149.193.86:8080/job/nexus-integration-test/build

# Via API with parameters
curl -X POST -u admin:password \
  "http://3.149.193.86:8080/job/nexus-integration-test/buildWithParameters?BRANCH=main"
```

### **Automatic Trigger** (When Configured)
```groovy
// GitHub webhook trigger
@Library('jenkins-shared-library') _

pipeline {
    triggers {
        githubPush()  // Automatic on Git push
    }
    
    stages {
        stage('Legacy Maven Build') {
            when { 
                anyOf {
                    changeset "**/*.java"
                    changeset "**/pom.xml"
                }
            }
            steps {
                // Automatically uses Nexus
                sh 'mvn clean package -s nexus-settings.xml'
            }
        }
    }
}
```

## 9. 🔍 **How to Check Current Triggers**

### **Via Jenkins UI**
1. Go to http://3.149.193.86:8080/job/nexus-integration-test/configure
2. Scroll to "Build Triggers" section
3. Currently shows: No triggers configured (manual only)

### **Via API** (Check Configuration)
```bash
# Get job configuration
curl -u admin:password http://3.149.193.86:8080/job/nexus-integration-test/config.xml

# Get job info
curl -u admin:password http://3.149.193.86:8080/job/nexus-integration-test/api/json
```

## 10. 💡 **Key Points About Triggers**

### **Current State** ✅
- **Nexus Usage**: Triggered automatically when Jenkins jobs run
- **Manual Builds**: Can be triggered via UI or API
- **Dependency Caching**: Happens automatically during builds
- **Service Discovery**: Health checks trigger Consul updates

### **Missing Triggers** (Next Steps)
- **Scheduled Builds**: Need cron configuration for nightly tasks
- **Git Integration**: Need webhook setup for automatic builds
- **Cross-Pipeline**: Need CircleCI → Jenkins triggers

### **Architecture Compliance** 📋
- ✅ **"Legacy JVM builds"**: Jenkins configured for Maven builds
- ✅ **"Nightly tasks"**: Infrastructure ready, need schedule triggers
- ✅ **"Nexus integration"**: Automatic dependency caching working
- ⚠️ **"Git-centric automation"**: Need webhook triggers

## 🎊 **Summary**

**The Jenkins-Nexus integration is TRIGGERED by:**

1. **Build Execution** ✅ - Any Jenkins job using configured Maven/NPM/Python
2. **Manual Triggers** ✅ - UI clicks or API calls  
3. **Automatic Caching** ✅ - Nexus proxies dependencies automatically
4. **Scheduled Jobs** ⚠️ - Need to configure cron triggers for nightly tasks
5. **Git Webhooks** ❌ - Need to set up for automated CI/CD

**The configuration is in Jenkins pipelines, tool configurations, and Nexus repository settings - all working together to provide enterprise-grade dependency caching for your legacy builds!** 🚀 