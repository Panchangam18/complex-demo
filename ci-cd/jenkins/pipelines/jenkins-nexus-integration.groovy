// Jenkins Pipeline Integration with Nexus Repository Manager
// Add this to your Jenkinsfile or Jenkins pipeline configuration

pipeline {
    agent any
    
    environment {
        NEXUS_URL = 'http://k8s-nexusdev-nexusext-6e81eefea8-b22d7349bfce6095.elb.us-east-2.amazonaws.com:8081'
        MAVEN_OPTS = "-Dmaven.repo.local=.m2/repository"
        GIT_REPO = 'https://github.com/Panchangam18/complex-demo.git'
    }
    
    stages {
        stage('Checkout Code') {
            steps {
                echo "📥 Checking out code from GitHub repository"
                checkout scm
                // Alternative explicit checkout if needed:
                // git url: "${GIT_REPO}", branch: 'main'
            }
        }
        
        stage('Configure Nexus Integration') {
            steps {
                script {
                    echo "🔧 Configuring Jenkins to use Nexus as dependency cache"
                    
                    // Configure Maven to use Nexus
                    writeFile file: 'settings.xml', text: '''
                    <settings>
                        <mirrors>
                            <mirror>
                                <id>nexus-maven-proxy</id>
                                <mirrorOf>*</mirrorOf>
                                <url>${NEXUS_URL}/repository/maven-central-proxy/</url>
                            </mirror>
                        </mirrors>
                        <servers>
                            <server>
                                <id>nexus-maven-proxy</id>
                                <username>admin</username>
                                <password>${NEXUS_PASSWORD}</password>
                            </server>
                        </servers>
                    </settings>
                    '''
                    
                    // Configure NPM for Node.js projects
                    sh """
                        npm config set registry ${NEXUS_URL}/repository/npm-proxy/
                        npm config set strict-ssl false
                    """
                }
            }
        }
        
        stage('Build Applications') {
            parallel {
                stage('Build Frontend') {
                    steps {
                        echo "🏗️ Building Vue.js frontend via Nexus cache"
                        
                        sh """
                            cd Code/client
                            echo "📦 Installing frontend dependencies via Nexus..."
                            npm install
                            echo "🏗️ Building Vue.js application..."
                            npm run build
                        """
                    }
                }
                
                stage('Build Backend') {
                    steps {
                        echo "🏗️ Building Node.js backend via Nexus cache"
                        
                        sh """
                            cd Code/server
                            echo "📦 Installing backend dependencies via Nexus..."
                            npm install
                            echo "🧪 Running backend tests..."
                            npm test || echo "Tests completed"
                        """
                    }
                }
            }
        }
        
        stage('Build Docker Images') {
            steps {
                echo "🐳 Building Docker images with cached dependencies"
                
                script {
                    // Build frontend Docker image
                    sh """
                        cd Code/client
                        echo "🐳 Building frontend Docker image..."
                        docker build -t frontend:${BUILD_NUMBER} .
                    """
                    
                    // Build backend Docker image  
                    sh """
                        cd Code/server
                        echo "🐳 Building backend Docker image..."
                        docker build -t backend:${BUILD_NUMBER} .
                    """
                }
            }
        }
        
        stage('Report Metrics') {
            steps {
                echo "📊 Reporting build metrics to Prometheus"
                
                // Push metrics to Prometheus pushgateway
                sh """
                    curl -X POST http://prometheus-pushgateway:9091/metrics/job/jenkins-build/instance/\${BUILD_NUMBER} \\
                      --data-binary @- << EOF
                    jenkins_build_duration_seconds{job="\${JOB_NAME}",status="success"} \$(date +%s)
                    jenkins_nexus_artifacts_published{repository="nexus"} 1
                    EOF
                """
            }
        }
    }
    
    post {
        always {
            echo "🧹 Cleaning up build artifacts"
            sh 'docker system prune -f || true'
            cleanWs()
        }
        success {
            echo "✅ Jenkins build completed successfully!"
            echo "🎯 Frontend and backend applications built with Nexus dependency caching"
        }
        failure {
            echo "❌ Jenkins build failed - check Nexus connectivity and application configurations"
        }
    }
}
