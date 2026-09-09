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
                container {
                    image = "mysql:latest"
                    name  = "db-container"

                    port {
                        container_port = 3306
                    }

                    resources {
                        requests = {
                            cpu    = "100m"
                            memory = "100Mi"
                        }
                    }
                }
                container {
                    image = "theharbormaster/banking-on-spring-boot-3-5:latest"
                    name  = "app-container"

                    port {
                        container_port = 8080
                    }
                    env {
                        name  = "DATABASE_DIALECT"
                        value = "com.mysql.cj.jdbc.Driver"
                    }
                    env {
                        name  = "DATABASE_URL"
                        value = "jdbc:mysql://db:3306/developmentdb?createDatabaseIfNotExist=true&autoReconnect=true&useSSL=false&allowPublicKeyRetrieval=true"
                    }
                    env {
                        name  = "DATABASE_PASSWORD"
                        value = "letmein2"
                    }
                    resources {
                        requests = {
                            cpu    = "100m"
                            memory = "100Mi"
                        }
                    }
                }
            }
        }

    }
}