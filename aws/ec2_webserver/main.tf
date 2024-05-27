/*
NOTE:
the following configuration uses the default AWS vpc since 
this is just an example scipt to show case my understanding of terraform

#######################################
Order of Operation
#######################################
1. create a private pem file locally
2. add the pem file to AWS
3. create a security group to allow for inbound traffic 
      to HTTP/HTTPS/SSH and outbound traffic to all
3. create an Amazon Linux t2.micro EC2 server
4. attach security group to server
4. add a provisioner remote to ssh into the server 
5. ssh in and install Apache web server on the EC2
    * clean the http web page folder
    * create a index.html file with a simple message
    * setup ssl to allow access for HTTPS (this will be a self signed cert)
    * restart the web server
*/

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_ami" "linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["137112412989"]
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = "foo.pem"
}

resource "aws_key_pair" "aws_gerneated_key" {
  key_name   = "foo"
  public_key = tls_private_key.generated.public_key_openssh
  lifecycle {
    ignore_changes = [key_name]
  }
}

resource "aws_instance" "web_server" {
  ami           = data.aws_ami.linux.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.aws_gerneated_key.key_name
  vpc_security_group_ids = [
    aws_security_group.web_security_group.id
  ]
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.generated.private_key_pem
      host        = self.public_ip
    }

    inline = [
      "sudo yum install -y httpd mod_ssl",
      "sudo mkdir -p /etc/httpd/ssl",
      "sudo chown -R ec2-user:ec2-user /etc/httpd/ssl",
      "sudo openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj \"/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=example.com\" -keyout /etc/httpd/ssl/apache.key -out /etc/httpd/ssl/apache.crt",
      "sudo bash -c 'cat <<EOF > /etc/httpd/conf.d/ssl.conf\nListen 443\n<VirtualHost *:443>\n  DocumentRoot \"/var/www/html\"\n  ServerName example.com\n  SSLEngine on\n  SSLCertificateFile \"/etc/httpd/ssl/apache.crt\"\n  SSLCertificateKeyFile \"/etc/httpd/ssl/apache.key\"\n  <Directory \"/var/www/html\">\n    AllowOverride All\n    Require all granted\n  </Directory>\n</VirtualHost>\nEOF'",
      "sudo rm -rf /var/www/html/*",
      "echo 'Hello, World!' | sudo tee /var/www/html/index.html",
      "sudo systemctl restart httpd"
    ]
  }
  tags = {
    Name      = "demo web server"
    Terraform = "true"
  }
  lifecycle {
    ignore_changes = [security_groups]
  }
}

resource "aws_security_group" "web_security_group" {
  name        = "web_security_group"
  description = "Allow SSH and HTTP traffic"

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

  tags = {
    Terraform = "true"
  }
}
