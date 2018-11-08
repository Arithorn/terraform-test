# Specify the provider and access details
#provider "aws" {
#  region = "${var.aws_region}"
#}

provider "vault" {
  address = "http://127.0.0.1:8200"
  skip_tls_verify = true
  token = "7NDjjnJX1SAyx8GJTbBhIHRd"
}

data "vault_generic_secret" "aws_secrets" {
  path    = "/secret/aws"
}

data "vault_generic_secret" "db_secrets" {
  path    = "/secret/db_secrets"
}

provider "aws" {
  access_key = "${data.vault_generic_secret.aws_secrets.data["access_key"]}"
  secret_key = "${data.vault_generic_secret.aws_secrets.data["secret_key"]}"
  region = "${var.aws_region}"
}


# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default_az1" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "default_az2" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "app_az1" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.5.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "db_az1" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.15.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "app_az2" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.130.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "db_az2" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.145.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = false
}



# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "lb" {
  name        = "sg_lb"
  description = "ELB SG set up by terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "db" {
  name        = "sg_db"
  description = "Database SG set up by terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # MYSQL access from App DMZ
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24","10.0.130.0/24"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = ["${aws_subnet.db_az1.id}","${aws_subnet.db_az2.id}"]
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "default_sg"
  description = "Default SG set up by terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "web" {
  name = "web-lb"

  subnets         = ["${aws_subnet.default_az1.id}","${aws_subnet.default_az2.id}"]
  security_groups = ["${aws_security_group.lb.id}"]

}

resource "aws_lb_listener" "web" {
  load_balancer_arn = "${aws_lb.web.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.web.arn}"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.default.id}"
}

resource "aws_alb_target_group_attachment" "svc_web" {
  target_group_arn = "${aws_alb_target_group.web.arn}"
  target_id        = "${aws_instance.web.id}"  
  port             = 80
}

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

resource "aws_db_instance" "appdb" {
  allocated_storage    = 10
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "appdb"
  username             = "${data.vault_generic_secret.db_secrets.data["username"]}"
  password             = "${data.vault_generic_secret.db_secrets.data["password"]}"
  parameter_group_name = "default.mysql5.7"
  db_subnet_group_name = "${aws_db_subnet_group.default.name}"
  vpc_security_group_ids = ["${aws_security_group.db.id}"]
}


resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"
  }

  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.auth.id}"
  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.app_az1.id}"

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
      "sudo service nginx start",
    ]
  }
}
