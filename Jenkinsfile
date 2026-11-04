// CI/CD for the movie/cast microservices
// dev -> qa -> staging run automatically on every branch.
// prod is deployed only from master, after a manual approval.

def deployTo(String namespace, String nodePort) {
  sh """
    helm upgrade --install fastapiapp charts \
      --namespace ${namespace} \
      --set imageTag=${env.IMAGE_TAG} \
      --set nginx.nodePort=${nodePort} \
      --wait --timeout 5m
    kubectl get pods -n ${namespace}
  """
}

def smokeTest(String namespace, String nodePort) {
  sh """
    for api in movies casts; do
      code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${nodePort}/api/v1/\$api/docs)
      echo "${namespace}: /api/v1/\$api/docs -> HTTP \$code"
      [ "\$code" = "200" ] || exit 1
    done
  """
}

pipeline {
  agent any

  environment {
    MOVIE_IMAGE = 'patelpayal/movie-service'
    CAST_IMAGE  = 'patelpayal/cast-service'
  }

  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  stages {
    stage('Prepare') {
      steps {
        script {
          env.IMAGE_TAG = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}".replaceAll('[^A-Za-z0-9_.-]', '-')
        }
        echo "Branch: ${env.BRANCH_NAME} | Image tag: ${env.IMAGE_TAG}"
        sh 'docker --version && kubectl version --client && helm version --short'
      }
    }

    stage('Build images') {
      steps {
        sh '''
          docker build -t $MOVIE_IMAGE:$IMAGE_TAG ./movie-service
          docker build -t $CAST_IMAGE:$IMAGE_TAG  ./cast-service
        '''
      }
    }

    stage('Push to DockerHub') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_TOKEN')]) {
          sh '''
            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
            docker push $MOVIE_IMAGE:$IMAGE_TAG
            docker push $CAST_IMAGE:$IMAGE_TAG
            if [ "$BRANCH_NAME" = "master" ]; then
              docker tag $MOVIE_IMAGE:$IMAGE_TAG $MOVIE_IMAGE:latest
              docker tag $CAST_IMAGE:$IMAGE_TAG  $CAST_IMAGE:latest
              docker push $MOVIE_IMAGE:latest
              docker push $CAST_IMAGE:latest
            fi
          '''
        }
      }
    }

    stage('Deploy & test dev') {
      steps { script { deployTo('dev', '30007'); smokeTest('dev', '30007') } }
    }

    stage('Deploy & test qa') {
      steps { script { deployTo('qa', '30008'); smokeTest('qa', '30008') } }
    }

    stage('Deploy & test staging') {
      steps { script { deployTo('staging', '30009'); smokeTest('staging', '30009') } }
    }

    stage('Deploy & test prod') {
      when { branch 'master' }
      steps {
        timeout(time: 15, unit: 'MINUTES') {
          input message: 'Deploy to PRODUCTION?', ok: 'Deploy to prod'
        }
        script { deployTo('prod', '30010'); smokeTest('prod', '30010') }
      }
    }
  }

  post {
    always {
      sh 'docker logout || true'
      sh 'docker rmi $MOVIE_IMAGE:$IMAGE_TAG $CAST_IMAGE:$IMAGE_TAG || true'
    }
    success { echo "Pipeline OK for ${env.BRANCH_NAME} (tag ${env.IMAGE_TAG})" }
    failure { echo "Pipeline FAILED for ${env.BRANCH_NAME}" }
  }
}
