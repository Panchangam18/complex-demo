// Jenkins Pipeline Integration with Nexus Repository Manager
// Add this to your Jenkinsfile or Jenkins pipeline configuration

pipeline {
    agent any
    
    environment {
        NEXUS_URL = 'http://k8s-nexusdev-nexusext-6e81eefea8-b22d7349bfce6095.elb.us-east-2.amazonaws.com:8081'
        MAVEN_OPTS = "-Dmaven.repo.local=.m2/repository"
    }
    
    stages {
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
        
        stage('Build Legacy Artifacts') {
            steps {
                echo "🏗️ Building legacy JVM artifacts via Nexus cache"
                
                // Maven build using Nexus proxy
                sh """
                    mvn clean package -s settings.xml \
                        -Dmaven.repo.local=.m2/repository \
                        -DskipTests=false
                """
            }
        }
        
        stage('Publish to Nexus') {
            steps {
                echo "📤 Publishing artifacts to Nexus (nightly job as per architecture)"
                
                // Publish to Nexus hosted repository
                sh """
                    mvn deploy -s settings.xml \
                        -DskipTests=true \
                        -Dmaven.repo.local=.m2/repository
                """
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
            cleanWs()
        }
        success {
            echo "✅ Jenkins build completed successfully with Nexus integration"
        }
        failure {
            echo "❌ Jenkins build failed - check Nexus connectivity"
        }
    }
}
