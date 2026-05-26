terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "eu-west-3"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "ssh_key_name" {
  description = "Name to give the created AWS key pair"
  type        = string
  default     = "gestion-produits-key"
}

variable "ssh_public_key" {
  description = "SSH public key material (openssh) to create a key pair for instance access"
  type        = string
}

variable "app_repo" {
  description = "Git repository URL (HTTPS) containing the application (root must contain php/ and database/ folders)"
  type        = string
}

variable "mysql_ebs_size_gb" {
  description = "Size (GB) of the EBS volume for MySQL data"
  type        = number
  default     = 8
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
}

resource "aws_security_group" "web_sg" {
  name        = "gestion-produits-sg"
  description = "Allow SSH, HTTP and HTTPS"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  root_block_device {
    volume_size = 16
    volume_type = "gp2"
  }

  tags = {
    Name = "gestion-produits-web"
  }

  user_data = <<-EOF
                #!/bin/bash
                set -eux

                apt-get update
                apt-get install -y ca-certificates curl gnupg lsb-release git

                mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
                  > /etc/apt/sources.list.d/docker.list
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
                systemctl enable --now docker

                # Wait for EBS device to be available and mount it to /opt/data/mysql
                DEVICE="/dev/xvdf"
                for i in {1..60}; do
                  if [ -b "$DEVICE" ]; then break; fi
                  sleep 1
                done
                mkdir -p /opt/data/mysql
                if [ -b "$DEVICE" ]; then
                  # only format if no filesystem
                  if ! blkid $DEVICE; then
                    mkfs -t ext4 $DEVICE
                  fi
                  mount $DEVICE /opt/data/mysql
                  chmod 775 /opt/data/mysql
                fi

                # Clone application repository
                if [ -n "${app_repo}" ]; then
                  git clone ${app_repo} /opt/app || (cd /opt/app && git pull)
                fi

                cd /opt/app || exit 0

                # Create nginx reverse-proxy config
                mkdir -p /opt/app/nginx/conf.d
                cat > /opt/app/nginx/conf.d/default.conf <<'NGINXCONF'
                server {
                  listen 80;
                  server_name _;

                  location / {
                    proxy_pass http://webapp:80;
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                  }
                }
                NGINXCONF

                # Write a production docker-compose file
                cat > /opt/app/docker-compose.prod.yml <<'COMPOSE'
                version: '3.8'
                services:
                  webapp:
                    build:
                      context: ./php
                      dockerfile: Dockerfile
                    container_name: gestion_produits_app
                    environment:
                      - DB_TYPE=mysql
                      - DB_HOST=db
                      - DB_NAME=gestion_produits
                      - DB_USER=root
                      - DB_PASS=root
                    volumes:
                      - ./php/www/uploads:/var/www/html/uploads
                      - ./php/www/img:/var/www/html/img
                    depends_on:
                      - db

                  db:
                    image: mysql:8.0
                    container_name: gestion_produits_db
                    environment:
                      - MYSQL_DATABASE=gestion_produits
                      - MYSQL_ROOT_PASSWORD=root
                    volumes:
                      - /opt/data/mysql:/var/lib/mysql
                    restart: unless-stopped

                  proxy:
                    image: nginx:stable
                    container_name: gestion_produits_nginx
                    ports:
                      - "80:80"
                      - "443:443"
                    volumes:
                      - ./nginx/conf.d:/etc/nginx/conf.d:ro
                    depends_on:
                      - webapp
                COMPOSE

                # Start application stacks
                docker compose -f /opt/app/docker-compose.prod.yml up -d
                EOF

}

resource "aws_ebs_volume" "mysql_data" {
  availability_zone = aws_instance.web.availability_zone
  size              = var.mysql_ebs_size_gb
  type              = "gp2"
  tags = {
    Name = "gestion-produits-mysql-data"
  }
}

resource "aws_volume_attachment" "mysql_attach" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.mysql_data.id
  instance_id  = aws_instance.web.id
  force_detach = true
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "ssh_command" {
  description = "Example SSH command to access the instance (use your private key)"
  value       = "ssh -i <private_key.pem> ubuntu@${aws_instance.web.public_ip}"
}