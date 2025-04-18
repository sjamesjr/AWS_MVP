provider "aws" {
  profile = var.profile_default
  region  = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_subnet" "subnet" {
  count             = 2
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow inbound HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_launch_template" "ec2_template" {
  name_prefix   = "web-template"
  image_id      = "ami-0df8c184d5f6ae949" # Amazon Linux 2 (Free Tier)
  instance_type = "t2.micro"

  network_interfaces {
    security_groups = [aws_security_group.ec2_sg.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
            EOF
  )
}

resource "aws_autoscaling_group" "ec2_asg" {
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.subnet[*].id
  launch_template {
    id      = aws_launch_template.ec2_template.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.tg.arn]
  tag {
    key                 = "Name"
    value               = "web-asg"
    propagate_at_launch = true
  }
}

resource "aws_lb" "alb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.subnet[*].id
  security_groups    = [aws_security_group.ec2_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


resource "aws_db_instance" "db" {
  identifier         = "free-tier-db"
  engine             = "mysql"
  instance_class     = "db.t3.micro"
  allocated_storage  = 20
  db_name            = "mydb"
  username           = "admin"
  password        = var.db_password
  skip_final_snapshot = true
  publicly_accessible = false
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "db-subnet-group"
  subnet_ids = aws_subnet.subnet[*].id
}

resource "aws_cloudwatch_metric_alarm" "ec2_cost_alert" {
  alarm_name          = "ec2-cost-exceeds-10"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600
  statistic           = "Maximum"
  threshold           = 10
  dimensions = {
    ServiceName = "Amazon Elastic Compute Cloud - Compute"
    Currency    = "USD"
  }

  alarm_description = "EC2 cost exceeds $10"
  actions_enabled   = false
}
