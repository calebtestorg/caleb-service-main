FROM java:8-alpine

ADD target/caleb-service-main-0.0.1-SNAPSHOT-standalone.jar /caleb-service-main/app.jar

EXPOSE 6001

ENTRYPOINT ["java", "-jar", "/caleb-service-main/app.jar"]
