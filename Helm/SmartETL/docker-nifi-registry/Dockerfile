FROM docker.io/apache/nifi-registry:1.24.0
COPY keycloak.crt /usr/local/share/ca-certificates/
USER root
RUN keytool -import -noprompt -trustcacerts -alias keycloak.crt -file  /usr/local/share/ca-certificates/keycloak.crt -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit
RUN update-ca-certificates
