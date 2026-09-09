
            # -------------------------------------------------------
# Specify the provider and access details
# -------------------------------------------------------
provider "aws" {
  region     = "us-east-2"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = {
      CreatedBy = "Harbormaster"
      Blueprint = "Spring Boot 3.5"
      DomainModel = "Banking Industry Domain Model"
      CertificationId = "41df5e36-9b1a-4026-9025-18e8abcb6568"
    }
  }
}

locals {
  public_key_filename  = "${path.root}/keys/id_rsa.pub"
  private_key_filename = "${path.root}/keys/id_rsa"
}

# Generate an RSA key to be used
resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

# Generate the local SSH Key pair in the directory specified
resource "local_file" "public_key_openssh" {
  content  = tls_private_key.generated.public_key_openssh
  filename = local.public_key_filename
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = local.private_key_filename
}

resource "aws_key_pair" "generated" {
  key_name   = "pjsk-sshtest-0.9783400913880959"
  public_key = tls_private_key.generated.public_key_openssh

  lifecycle {
  ignore_changes = [key_name]
  }
}
# -------------------------------------------------------
# create a default VPC is none provided
# -------------------------------------------------------


# Default vpc
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "default" {
  vpc_id     = aws_vpc.default.id
  cidr_block = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "secondary" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
}

resource "aws_route_table_association" "default" {
  subnet_id      = aws_subnet.default.id
  route_table_id = aws_route_table.public.id
}

# bug: RDS must use DB subnet group in same VPC
resource "aws_db_subnet_group" "default" {
  name       = "bankingbackend-db-subnet"
  subnet_ids = [aws_subnet.default.id, aws_subnet.secondary.id]
}

# -------------------------------------------------------
# Default security group to access
# the instances over SSH and HTTP
# -------------------------------------------------------

resource "aws_security_group" "web" {
#  name        = "bankingbackend-security-group-from-terraform" #optional, when omitted, terraform creates a random name
  description = "security group for application bankingbackend created from terraform"
  vpc_id      = aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------------------------------------
# The default security group for the database
# -------------------------------------------------------

resource "aws_security_group" "db" {
  description = "security group for bankingbackend and mysql created from terraform"
  vpc_id      = aws_vpc.default.id

  # mysql access from anywhere
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "default" {
  depends_on             = [aws_security_group.db]
#  identifier             = "bankingbackend-rds" # Terraform will create a unique id if not assigned
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.medium"
  db_name                = "bankingbackend"
  username               = "no_user_name"
  password               = "no_password"
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name # bug: wire RDS to VPC subnet group
  skip_final_snapshot    = true # bug: allow terraform destroy without final snapshot prompt

}
 
# -------------------------------------------------------
# eks cluster
# -------------------------------------------------------

resource "aws_iam_role" "eks" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
     Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name
}

resource "aws_eks_cluster" "this" {
  name     = "eks_cluster_bankingbackend"
  role_arn = aws_iam_role.eks.arn
  vpc_config {
    # EKS requires subnet IDs in at least 2 AZs
    subnet_ids = [aws_subnet.default.id, aws_subnet.secondary.id]
  }
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# -------------------------------------------------------
# ec2 instance
# -------------------------------------------------------

resource "aws_instance" "web" {
  # -------------------------------------------------------
  # The connection block tells the provisioner how to
  # communicate with the resource (instance)
  # -------------------------------------------------------

  connection {
    # The default username for our ec2 instance
    type = "ssh"
    host = self.public_ip
    user = "ec2-user"
    private_key = tls_private_key.generated.private_key_pem
  }

  instance_type = "t2.medium"
  
  tags = { Name = "bankingbackend instance" } 

  # -------------------------------------------------------
  # standard harbormaster community AMI with docker pre-installed
  # -------------------------------------------------------
  ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

  # -------------------------------------------------------
  # The name of the  SSH keypair you've created and downloaded
  # from the AWS console.
  #
  # https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#KeyPairs:
  #
  # -------------------------------------------------------

  # -------------------------------------------------------
  # use a generate key and share it here
  # -------------------------------------------------------
  key_name = aws_key_pair.generated.key_name

  # -------------------------------------------------------
  # Our Security group to allow HTTP and SSH access
  # -------------------------------------------------------
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.default.id
  associate_public_ip_address = true

  # -------------------------------------------------------
  # remote execution commands
  # -------------------------------------------------------

  provisioner "remote-exec" {
    inline = [
      "sudo dnf -y install docker",
      "sudo systemctl enable --now docker",
      "sudo docker login --username tylertravismya --password 69Cutlass",
      "sudo docker pull theharbormaster/banking-on-spring-boot-3-5:latest",
      "sudo docker run -d -p 8000:8000 -p 8080:8080 -e DATABASE_URL=jdbc:mysql://${aws_db_instance.default.endpoint}/bankingbackend theharbormaster/banking-on-spring-boot-3-5:latest"
    ]
  }
}

output "ssh_command" {
  description = "Command to use to SSH into the instance."
  value = "ssh -i ${local.private_key_filename} ec2-user@${aws_instance.web.public_ip}"
}


