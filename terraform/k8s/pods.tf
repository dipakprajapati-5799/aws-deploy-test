resource "kubernetes_replication_controller" "app-master" {
    metadata {
        name = "app-master"
    }

    spec {
        replicas = 1

        selector = {
            app  = "bankingbackend"
        }

        template {

            metadata {
                labels = {
                    app  = "bankingbackend"
                }
            }

            spec {
                # # bug: mysql:latest exits immediately without MYSQL_ROOT_PASSWORD / MYSQL_DATABASE
                container {
                    image = "mysql:8.0"
                    name  = "db-container"

                    port {
                        container_port = 3306
                    }

                    env {
                        name  = "MYSQL_ROOT_PASSWORD"
                        value = "letmein2"
                    }
                    env {
                        name  = "MYSQL_DATABASE"
                        value = "bankingbackend"
                    }

                    resources {
                        requests = {
                            cpu    = "100m"
                            # # bug: 100Mi is too small for MySQL; container crash-looped under memory pressure
                            memory = "512Mi"
                        }
                    }
                }
                # # bug: Hub image theharbormaster/banking-on-spring-boot-3-5:latest runs Java 11;
                # Spring Boot 3.5 app needs Java 17 → UnsupportedClassVersionError until Hub image is rebuilt.
                # # bug: app pointed at host "db" (no such service); use 127.0.0.1 + SPRING_DATASOURCE_* for Boot.
                container {
                    image = "theharbormaster/banking-on-spring-boot-3-5:latest"
                    name  = "app-container"

                    port {
                        container_port = 8080
                    }
                    env {
                        name  = "SPRING_DATASOURCE_URL"
                        value = "jdbc:mysql://127.0.0.1:3306/bankingbackend?createDatabaseIfNotExist=true&autoReconnect=true&useSSL=false&allowPublicKeyRetrieval=true"
                    }
                    env {
                        name  = "SPRING_DATASOURCE_USERNAME"
                        value = "root"
                    }
                    env {
                        name  = "SPRING_DATASOURCE_PASSWORD"
                        value = "letmein2"
                    }
                    resources {
                        requests = {
                            cpu    = "100m"
                            memory = "512Mi"
                        }
                    }
                }
            }
        }

    }
}
